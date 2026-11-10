import Foundation
import CoreGraphics

/// 手帐本只保存目录。页序由 pages 决定；完整图层按页读取，避免一次加载整本原图。
nonisolated struct DiaryBook: Codable, Identifiable, Equatable, Sendable {
    var format = "TravelDiary.Book"
    var schemaVersion = 1
    var id = UUID()
    var catalogRevision = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var defaultPageSize = DiaryPagePreset.a5.size
    static let coverSize = CGSize(width: 2185, height: 3130)
    var coverPageID: UUID?
    var coverDraft: DiaryPageEntry? = nil
    /// 外壳独立于列表封面；旧帐本不配置外壳。
    var shellPageID: UUID? = nil
    /// 导入操作发布记录，用于崩溃后重试去重。旧作品缺省为空。
    var presetImports: [String: [UUID]]? = nil
    var pages: [DiaryPageEntry] = []
    var trashedPages: [DiaryTrashedPage] = []
    var shell: DiaryPageEntry? { pages.first { $0.id == shellPageID } }
    var contentPages: [DiaryPageEntry] { pages.filter { $0.id != shellPageID } }
    var effectiveCover: DiaryPageEntry? { pages.first { $0.id == coverPageID && $0.canBeCover && $0.id != shellPageID } }
    var bodyPages: [DiaryPageEntry] { contentPages.filter { $0.id != effectiveCover?.id } }
    var bodyPageCount: Int { bodyPages.reduce(0) { $0 + ($1.canvasLayout == .spread ? 2 : 1) } }
    /// The opening is always reserved, including when no cover has been made yet.
    var readingSpreads: [[DiaryPageEntry?]] { [[nil, effectiveCover]] + bodySpreads }
    var exportSpreads: [[DiaryPageEntry?]] {
        (effectiveCover.map { [[nil, Optional($0)]] } ?? []) + bodySpreads
    }
    var bodySpreads: [[DiaryPageEntry?]] {
        let content = bodyPages
        var result: [[DiaryPageEntry?]] = [], index = 0
        while index < content.count {
            let page = content[index]
            if page.canvasLayout == .spread {
                result.append([page, nil]); index += 1
            } else if let pair = page.presetSpreadID {
                if page.presetSpreadSide == "left", index + 1 < content.count,
                   content[index + 1].presetSpreadID == pair, content[index + 1].presetSpreadSide == "right" {
                    result.append([page, content[index + 1]]); index += 2
                } else {
                    result.append(page.presetSpreadSide == "right" ? [nil, page] : [page, nil]); index += 1
                }
            } else if index + 1 < content.count, content[index + 1].canvasLayout == .single,
                      content[index + 1].presetSpreadID == nil {
                result.append([page, content[index + 1]]); index += 2
            } else {
                result.append([page, nil]); index += 1
            }
        }
        return result
    }
    func pageLabel(_ page: DiaryPageEntry) -> String {
        if page.id == effectiveCover?.id { return "封面" }
        if page.id == shellPageID { return "外壳" }
        guard let index = bodyPages.firstIndex(where: { $0.id == page.id }) else { return page.title }
        let first = bodyPages.prefix(index).reduce(1) { $0 + ($1.canvasLayout == .spread ? 2 : 1) }
        return page.canvasLayout == .spread ? "第 \(first)–\(first + 1) 页" : "第 \(first) 页"
    }

}

nonisolated struct DiaryPageEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    /// 完整不可变快照的标识；本目录是当前版本唯一发布入口。
    var revisionID: UUID
    var size: CGSize
    var aiSaveAnchor: String? = nil
    var aiOriginBook: UUID? = nil
    var aiOriginTask: UUID? = nil
    var aiFirstSavedAt: Date? = nil
    var presetSource: DiaryPresetSource? = nil
    /// Explicit imported spread membership survives reopening and user edits.
    var presetSpreadID: UUID? = nil
    var presetSpreadSide: String? = nil
    /// Optional for backward compatibility. Older documents infer their layout from size.
    var layout: DiaryCanvasLayout? = nil
    var canBeCover: Bool { canvasLayout == .single && size.width.isFinite && size.height.isFinite && size.width > 0 && size.width < size.height }
    var canvasLayout: DiaryCanvasLayout { layout ?? DiaryCanvasLayout.infer(from: size) }
}

nonisolated enum DiaryCanvasLayout: String, Codable, Sendable {
    case single, spread

    static func infer(from size: CGSize) -> Self {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return .single }
        return abs(size.width / size.height - 4370.0 / 3130.0) < 0.000001 ? .spread : .single
    }
}

nonisolated struct DiaryTrashedPage: Codable, Identifiable, Equatable, Sendable {
    var entry: DiaryPageEntry
    var originalIndex: Int
    var deletedAt = Date()
    var id: UUID { entry.id }
}

/// 新建本子的标准页面规格；设计坐标直接采用 A5 在 300 DPI 下的整数像素。
nonisolated enum DiaryPagePreset: String, CaseIterable, Identifiable, Sendable {
    case a5, b5, portrait, square, spread
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spread: "完整跨页｜4370 × 3130 px"
        case .a5: "A5｜148 × 210 mm @300 DPI"
        case .b5: "B5（ISO）｜176 × 250 mm @300 DPI"
        case .portrait: "竖版｜1000 × 1400 px"
        case .square: "正方形｜1000 × 1000 px"
        }
    }
    var size: CGSize {
        switch self {
        case .spread: CGSize(width: 4370, height: 3130)
        case .a5: CGSize(width: 1748, height: 2480)
        case .b5: CGSize(width: 2079, height: 2953)
        case .portrait: CGSize(width: 1000, height: 1400)
        case .square: CGSize(width: 1000, height: 1000)
        }
    }
}

/// 来源只用于追踪；用户作品不依赖模板路径或模板后续版本。
nonisolated struct DiaryPresetSource: Codable, Equatable, Sendable {
    let bookID: String
    let pageID: String
    let version: Int
}
