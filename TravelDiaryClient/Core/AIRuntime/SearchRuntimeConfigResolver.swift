import Foundation

nonisolated enum SearchRuntimeConfigResolver {
    static func resolve(from snapshot: AISettingsSnapshot) throws -> SearchRuntimeConfig {
        guard snapshot.searchToolPreferences.useSearch else {
            throw SearchRuntimeError.disabled
        }

        let activeKeys = snapshot.searchKeys.filter { $0.searchClass.lowercased() == "web" && $0.isUsing }
        if activeKeys.isEmpty {
            return try makeDefaultDuckDuckGoConfig(snapshot: snapshot)
        }

        let active: SearchKeys
        if let single = activeKeys.first, activeKeys.count == 1 {
            active = single
        } else {
            // Defensive fallback for legacy multi-active data.
            active = activeKeys.sorted {
                if $0.priority == $1.priority {
                    return $0.timestamp > $1.timestamp
                }
                return $0.priority > $1.priority
            }.first!
        }

        return try makeConfig(
            from: active,
            snapshot: snapshot,
            allowFallback: true
        )
    }

    static func makeDefaultDuckDuckGoConfig(snapshot: AISettingsSnapshot) throws -> SearchRuntimeConfig {
        try makeConfig(
            from: SearchProviderCatalog.makeDefaultDuckDuckGoProfile(),
            snapshot: snapshot,
            allowFallback: false
        )
    }

    static func makeConfig(
        from active: SearchKeys,
        snapshot: AISettingsSnapshot,
        allowFallback: Bool
    ) throws -> SearchRuntimeConfig {
        var provider = SearchProviderID(company: active.company)
        var apiKey = active.key.trimmingCharacters(in: .whitespacesAndNewlines)
        var requestURLString = active.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var displayName = active.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? active.company
            : active.name

        if provider == .none {
            return SearchRuntimeConfig(
                provider: .none,
                displayName: displayName,
                apiKey: "",
                requestURL: URL(string: requestURLString) ?? URL(string: SearchProviderCatalog.defaultRequestURL(for: .none))!,
                searchCount: max(1, min(snapshot.searchToolPreferences.searchCount, 50)),
                bilingualSearch: snapshot.searchToolPreferences.bilingualSearch,
                revision: snapshot.searchConfigRevision,
                rawKeyID: active.id
            )
        }

        if allowFallback {
            switch provider {
            case .brave, .tavily, .jina where apiKey.isEmpty:
                provider = .duckduckgo
                requestURLString = SearchProviderCatalog.defaultRequestURL(for: .duckduckgo)
                apiKey = ""
                displayName = SearchProviderCatalog.displayName(for: .duckduckgo)
            case .searxng where requestURLString.isEmpty:
                provider = .duckduckgo
                requestURLString = SearchProviderCatalog.defaultRequestURL(for: .duckduckgo)
                apiKey = ""
                displayName = SearchProviderCatalog.displayName(for: .duckduckgo)
            default:
                break
            }
        }

        if SearchProviderCatalog.requiresAPIKey(for: provider), apiKey.isEmpty, provider != .spark {
            throw SearchRuntimeError.missingAPIKey(displayName)
        }

        if SearchProviderCatalog.requiresBaseURL(for: provider), requestURLString.isEmpty {
            throw SearchRuntimeError.invalidEndpoint("SearXNG Base URL is required.")
        }

        if requestURLString.isEmpty {
            requestURLString = SearchProviderCatalog.defaultRequestURL(for: provider)
        }

        guard let url = URL(string: requestURLString), url.scheme != nil else {
            throw SearchRuntimeError.invalidEndpoint(requestURLString)
        }

        return SearchRuntimeConfig(
            provider: provider,
            displayName: displayName,
            apiKey: apiKey,
            requestURL: url,
            searchCount: max(1, min(snapshot.searchToolPreferences.searchCount, 50)),
            bilingualSearch: snapshot.searchToolPreferences.bilingualSearch,
            revision: snapshot.searchConfigRevision,
            rawKeyID: active.id
        )
    }

    static func normalizedHash(preferences: AISearchToolPreferences, searchKeys: [SearchKeys]) -> String {
        let keyRows = searchKeys
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map {
                [
                    $0.id.uuidString,
                    $0.name,
                    $0.company,
                    stableHash($0.key),
                    $0.requestURL,
                    "\($0.isUsing)",
                    $0.searchClass,
                    $0.authType.rawValue,
                    "\($0.priority)",
                    $0.enabledScopes.sorted().joined(separator: ","),
                    "\($0.revision)"
                ].joined(separator: "|")
            }
            .joined(separator: "\n")
        let source = [
            "\(preferences.useSearch)",
            "\(preferences.bilingualSearch)",
            "\(preferences.searchCount)",
            keyRows
        ].joined(separator: "\n")
        return stableHash(source)
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
