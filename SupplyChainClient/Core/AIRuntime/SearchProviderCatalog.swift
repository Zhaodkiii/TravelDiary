import Foundation

nonisolated struct SearchProviderFieldSpec: Equatable, Sendable {
    var showsAPIKey: Bool
    var showsBaseURL: Bool
    var requiresAPIKey: Bool
    var requiresBaseURL: Bool

    static let keyOnly = SearchProviderFieldSpec(
        showsAPIKey: true,
        showsBaseURL: true,
        requiresAPIKey: true,
        requiresBaseURL: false
    )
    static let baseURLOnly = SearchProviderFieldSpec(
        showsAPIKey: false,
        showsBaseURL: true,
        requiresAPIKey: false,
        requiresBaseURL: true
    )
    static let noCredentials = SearchProviderFieldSpec(
        showsAPIKey: false,
        showsBaseURL: false,
        requiresAPIKey: false,
        requiresBaseURL: false
    )
    static let unknown = SearchProviderFieldSpec(
        showsAPIKey: true,
        showsBaseURL: true,
        requiresAPIKey: false,
        requiresBaseURL: false
    )
}

nonisolated enum SearchProviderCatalog {
    /// Server-aligned primary catalog (`provider_runtime.py` / `search-providers.ts`).
    static let primaryProviders: [SearchProviderID] = [
        .none,
        .brave,
        .tavily,
        .jina,
        .searxng,
        .duckduckgo,
        .perplexity,
        .serper
    ]

    /// Legacy iOS providers kept for backward compatibility with existing profiles.
    static let legacyProviders: [SearchProviderID] = [
        .spark,
        .serpAPI,
        .zhipu,
        .bocha,
        .exa,
        .langSearch
    ]

    static let pickerProviders: [SearchProviderID] = primaryProviders + legacyProviders

    static func fieldSpec(for provider: SearchProviderID) -> SearchProviderFieldSpec {
        switch provider {
        case .none, .duckduckgo:
            return .noCredentials
        case .searxng:
            return .baseURLOnly
        case .brave, .tavily, .jina, .perplexity, .serper:
            return .keyOnly
        case .spark:
            return .noCredentials
        case .serpAPI, .zhipu, .bocha, .exa, .langSearch:
            return .unknown
        }
    }

    static func displayName(for provider: SearchProviderID) -> String {
        switch provider {
        case .none: return "None"
        case .brave: return "Brave"
        case .tavily: return "Tavily"
        case .jina: return "Jina"
        case .searxng: return "SearXNG"
        case .duckduckgo: return "DuckDuckGo"
        case .perplexity: return "Perplexity"
        case .serper: return "Serper"
        case .spark: return "Spark"
        case .serpAPI: return "SerpAPI"
        case .zhipu: return "ZhipuAI"
        case .bocha: return "BochaAI"
        case .exa: return "Exa"
        case .langSearch: return "LangSearch"
        }
    }

    static func defaultRequestURL(for provider: SearchProviderID) -> String {
        switch provider {
        case .tavily:
            return "https://api.tavily.com/search"
        case .brave:
            return "https://api.search.brave.com/res/v1/web/search"
        case .jina:
            return "https://s.jina.ai"
        case .perplexity:
            return "https://api.perplexity.ai/chat/completions"
        case .serper:
            return "https://google.serper.dev/search"
        case .serpAPI:
            return "https://serpapi.com/search"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4/tools"
        case .bocha:
            return "https://api.bochaai.com/v1/web-search"
        case .exa:
            return "https://api.exa.ai/search"
        case .langSearch:
            return "https://api.langsearch.com/v1/web-search"
        case .duckduckgo:
            return "https://html.duckduckgo.com/html"
        case .none:
            return "https://local.invalid/none"
        case .searxng, .spark:
            return ""
        }
    }

    static func defaultHelpURL(for provider: SearchProviderID) -> String {
        switch provider {
        case .brave: return "https://brave.com/search/api/"
        case .tavily: return "https://tavily.com"
        case .jina: return "https://jina.ai/reader"
        case .searxng: return "https://docs.searxng.org/"
        case .duckduckgo: return "https://duckduckgo.com"
        case .perplexity: return "https://docs.perplexity.ai"
        case .serper: return "https://serper.dev"
        case .serpAPI: return "https://serpapi.com"
        case .zhipu: return "https://open.bigmodel.cn"
        case .bocha: return "https://bochaai.com"
        case .exa: return "https://exa.ai"
        case .langSearch: return "https://langsearch.com"
        default: return ""
        }
    }

    static func requiresAPIKey(for provider: SearchProviderID) -> Bool {
        fieldSpec(for: provider).requiresAPIKey
    }

    static func requiresBaseURL(for provider: SearchProviderID) -> Bool {
        fieldSpec(for: provider).requiresBaseURL
    }

    static func canActivateWithoutCredentials(provider: SearchProviderID) -> Bool {
        switch provider {
        case .none, .duckduckgo, .spark:
            return true
        case .searxng:
            return false
        default:
            return false
        }
    }

    static func makeDefaultDuckDuckGoProfile() -> SearchKeys {
        SearchKeys(
            name: displayName(for: .duckduckgo),
            company: SearchProviderID.duckduckgo.rawValue,
            key: "",
            requestURL: defaultRequestURL(for: .duckduckgo),
            isUsing: true,
            searchClass: "web",
            help: defaultHelpURL(for: .duckduckgo),
            source: .system,
            timestamp: Date(),
            authType: .none,
            priority: 0,
            enabledScopes: ["chat", "small_task"],
            revision: 1
        )
    }

    static func applyDefaults(to key: inout SearchKeys, provider: SearchProviderID) {
        key.company = provider.rawValue
        if key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key.requestURL = defaultRequestURL(for: provider)
        }
        if key.help.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key.help = defaultHelpURL(for: provider)
        }
        if key.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            key.name = displayName(for: provider)
        }
        if provider == .duckduckgo {
            let url = key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if url.isEmpty || (url.contains("duckduckgo.com") && url.contains("html.duckduckgo.com") == false) {
                key.requestURL = defaultRequestURL(for: .duckduckgo)
            }
        }
        switch provider {
        case .none, .duckduckgo, .searxng, .spark:
            key.authType = .none
        case .brave:
            key.authType = .headerToken
        case .serpAPI:
            key.authType = .queryAPIKey
        default:
            key.authType = .bearer
        }
    }
}
