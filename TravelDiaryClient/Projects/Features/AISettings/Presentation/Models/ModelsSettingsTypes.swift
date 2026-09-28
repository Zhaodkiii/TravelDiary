import Foundation

/// 模型页顶部分段：与 Health `ModelsView` 的 `IdentityFilter` 一致（文案走 L10n）。
enum ModelsSettingsIdentityFilter: CaseIterable, Hashable {
    case all
    case model
    case agent

    var localizedTitle: String {
        switch self {
        case .all:
            return L10n.text("common.all")
        case .model:
            return L10n.text("ai_settings.models.filter.models_only")
        case .agent:
            return L10n.text("ai_settings.models.filter.agents_only")
        }
    }
}
