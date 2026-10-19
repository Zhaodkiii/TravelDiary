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
    var coverPageID: UUID?
    /// 外壳独立于列表封面；旧帐本不配置外壳。
    var shellPageID: UUID? = nil
    /// 导入操作发布记录，用于崩溃后重试去重。旧作品缺省为空。
    var presetImports: [String: [UUID]]? = nil
    var pages: [DiaryPageEntry] = []
    var trashedPages: [DiaryTrashedPage] = []
    var shell: DiaryPageEntry? { pages.first { $0.id == shellPageID } }
    var contentPages: [DiaryPageEntry] { pages.filter { $0.id != shellPageID } }
    var effectiveCover: DiaryPageEntry? { pages.first { $0.id == coverPageID } ?? pages.first }
}

nonisolated struct DiaryPageEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    /// 完整不可变快照的标识；本目录是当前版本唯一发布入口。
    var revisionID: UUID
    var size: CGSize
    var presetSource: DiaryPresetSource? = nil
}

nonisolated struct DiaryTrashedPage: Codable, Identifiable, Equatable, Sendable {
    var entry: DiaryPageEntry
    var originalIndex: Int
    var deletedAt = Date()
    var id: UUID { entry.id }
}

/// 新建本子的标准页面规格；设计坐标直接采用 A5 在 300 DPI 下的整数像素。
nonisolated enum DiaryPagePreset: String, CaseIterable, Identifiable, Sendable {
    case a5, b5, portrait, square
    var id: String { rawValue }
    var title: String {
        switch self {
        case .a5: "A5｜148 × 210 mm @300 DPI"
        case .b5: "B5（ISO）｜176 × 250 mm @300 DPI"
        case .portrait: "竖版｜1000 × 1400 px"
        case .square: "正方形｜1000 × 1000 px"
        }
    }
    var size: CGSize {
        switch self {
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
