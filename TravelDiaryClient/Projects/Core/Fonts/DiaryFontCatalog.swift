import UIKit
import CoreText
import CryptoKit

/// 作品只保存稳定引用，字体路径和 UIKit 对象不进入文档。
nonisolated struct DiaryFontReference: Codable, Equatable, Sendable {
    var id: String
    var version: String
    static let system = DiaryFontReference(id: "system", version: "1")
}

nonisolated struct DiaryFontEntry: Codable, Identifiable, Sendable {
    let id: String
    let version: String
    let displayName: String
    let category: String
    let postScriptName: String?
    let relativePath: String?
    let sha256: String?
    var reference: DiaryFontReference { DiaryFontReference(id: id, version: version) }
}

/// 资源提供者可替换为下载到本地的目录；作品不依赖下载 URL。
nonisolated protocol DiaryFontResourceProvider {
    func entries() throws -> [DiaryFontEntry]
    func url(for entry: DiaryFontEntry) -> URL?
}
nonisolated struct BundledDiaryFonts: DiaryFontResourceProvider {
    var root: URL? { Bundle.main.url(forResource: "DiaryFonts", withExtension: "bundle") }
    func entries() throws -> [DiaryFontEntry] {
        guard let root else { return [] }
        return try JSONDecoder().decode([DiaryFontEntry].self, from: Data(contentsOf: root.appendingPathComponent("catalog.json")))
    }
    func url(for entry: DiaryFontEntry) -> URL? {
        guard let path = entry.relativePath, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { return nil }
        return root?.appendingPathComponent(path)
    }
}

/// 主线程串行注册，所有入口（包含导出）共享一次注册结果和字体解析。
@MainActor
final class DiaryFontCatalog {
    static let shared = DiaryFontCatalog()
    private let provider: any DiaryFontResourceProvider
    private(set) var entries: [DiaryFontEntry] = []
    private(set) var failures: [String: String] = [:]
    private var prepared = false
    private var registeredIDs = Set<String>()

    init(provider: any DiaryFontResourceProvider = BundledDiaryFonts()) { self.provider = provider }
    func prepare() {
        guard !prepared else { return }
        prepared = true
        entries = [DiaryFontEntry(id: "system", version: "1", displayName: "系统字体", category: "system",
                                 postScriptName: nil, relativePath: nil, sha256: nil)]
        do {
            // 目录只载入轻量元数据；大字体在列表实际显示时再校验和注册，避免打开弹窗一次读入全部字库。
            let bundledEntries = try provider.entries()
            var seenIDs = Set(entries.map(\.id))
            entries.append(contentsOf: bundledEntries.filter { !$0.id.isEmpty && seenIDs.insert($0.id).inserted })
        } catch { failures["catalog"] = "字体目录读取失败" }
    }
    func entry(_ reference: DiaryFontReference?) -> DiaryFontEntry? {
        prepare()
        let ref = reference ?? .system
        return entries.first { $0.id == ref.id && $0.version == ref.version }
    }
    func available(_ reference: DiaryFontReference?) -> Bool {
        guard let entry = entry(reference) else { return false }
        return registerIfNeeded(entry)
    }
    func font(_ reference: DiaryFontReference?, size: CGFloat) -> UIFont {
        guard let entry = entry(reference), registerIfNeeded(entry), let name = entry.postScriptName,
              let font = UIFont(name: name, size: size) else { return .systemFont(ofSize: size) }
        return font
    }

    private func registerIfNeeded(_ entry: DiaryFontEntry) -> Bool {
        guard entry.id != "system" else { return true }
        guard failures[entry.id] == nil else { return false }
        guard !registeredIDs.contains(entry.id) else { return true }
        do {
            guard let url = provider.url(for: entry), let name = entry.postScriptName,
                  let expectedDigest = entry.sha256 else { throw CocoaError(.fileNoSuchFile) }
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expectedDigest else { throw CocoaError(.fileReadCorruptFile) }
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !registered, let failure = error?.takeRetainedValue(), CFErrorGetCode(failure) != CTFontManagerError.alreadyRegistered.rawValue {
                throw failure as Error
            }
            guard UIFont(name: name, size: 20) != nil else { throw CocoaError(.fileReadCorruptFile) }
            registeredIDs.insert(entry.id)
            return true
        } catch {
            failures[entry.id] = "字体暂不可用"
            return false
        }
    }
    func warning(_ reference: DiaryFontReference?, text: String) -> String? {
        guard available(reference) else { return "字体暂不可用，已临时使用系统字体；原字体引用将保留。" }
        guard reference != nil, reference != .system else { return nil }
        let units = Array(text.utf16)
        guard !units.isEmpty else { return nil }
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        let ctFont = font(reference, size: 20) as CTFont
        if !CTFontGetGlyphsForCharacters(ctFont, units, &glyphs, units.count) {
            return "部分字符可能使用系统字体显示。"
        }
        return nil
    }
}
