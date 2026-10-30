import SwiftUI

/// The root owns toolbar presentation; each catalog page retains its filters
/// and responds only to requests addressed to its own content kind.
@MainActor @Observable
final class DiaryMaterialToolbarState {
    enum Category: String, CaseIterable {
        case templates = "模板"
        case albums = "相册"
        case stickers = "贴纸"
        case fonts = "字体"

        var contentKind: String? {
            switch self {
            case .templates: "journal"
            case .albums: "album"
            case .stickers, .fonts: nil
            }
        }
    }

    struct FilterRequest: Equatable {
        let id = UUID()
        let category: Category
    }

    var category: Category = .templates
    var catalog: RemotePresetCatalog?
    private(set) var filterRequest: FilterRequest?
    private var filteredCategories: Set<Category> = []

    var hasActiveFilters: Bool { filteredCategories.contains(category) }

    func requestFilters() {
        guard category.contentKind != nil else { return }
        filterRequest = FilterRequest(category: category)
    }

    func consumeFilterRequest(contentKind: String) -> Bool {
        guard filterRequest?.category.contentKind == contentKind else { return false }
        filterRequest = nil
        return true
    }

    func setFiltersActive(_ active: Bool, contentKind: String) {
        guard let category = Category.allCases.first(where: { $0.contentKind == contentKind }) else { return }
        if active { filteredCategories.insert(category) }
        else { filteredCategories.remove(category) }
    }
}
