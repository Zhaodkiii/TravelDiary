import Foundation

nonisolated enum AIRecordSource: String, Codable, CaseIterable, Sendable {
    case system
    case custom
    case pro
}

nonisolated enum AIModelIdentity: String, Codable, CaseIterable, Sendable {
    case model
    case agent
}

nonisolated enum AIModelSelectionSource: String, Codable, CaseIterable, Sendable {
    case localKey
    case trial
}

nonisolated enum AIProviderIdentifier {
    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9_\\-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
    }
}

nonisolated enum AIProviderLocalization {
    static func localizedCompanyName(for company: String) -> String {
        let key = "company_\(AIProviderIdentifier.normalize(company))"
        return L10n.text(key, fallback: company)
    }
}

nonisolated struct APIKeys: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var providerID: String
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var help: String
    var from: String
    var privacyPolicyURL: String
    var isEnabled: Bool
    var source: AIRecordSource
    var privacyPolicyAccepted: Bool
    var privacyPolicyAcceptedAt: Date?
    var timestamp: Date

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        help: String,
        from: String = AIRecordSource.system.rawValue,
        privacyPolicyURL: String = "",
        isEnabled: Bool = true,
        source: AIRecordSource,
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.name = name
        self.company = company
        self.key = key
        self.requestURL = requestURL
        self.help = help
        self.from = from
        self.privacyPolicyURL = privacyPolicyURL
        self.isEnabled = isEnabled
        self.source = source
        self.privacyPolicyAccepted = privacyPolicyAccepted
        self.privacyPolicyAcceptedAt = privacyPolicyAcceptedAt
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        providerID: String? = nil,
        name: String,
        company: String,
        key: String,
        requestURL: String,
        isHidden: Bool,
        help: String,
        source: AIRecordSource,
        privacyPolicyURL: String = "",
        privacyPolicyAccepted: Bool = false,
        privacyPolicyAcceptedAt: Date? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            id: id,
            providerID: providerID,
            name: name,
            company: company,
            key: key,
            requestURL: requestURL,
            help: help,
            from: source.rawValue,
            privacyPolicyURL: privacyPolicyURL,
            isEnabled: isHidden == false,
            source: source,
            privacyPolicyAccepted: privacyPolicyAccepted,
            privacyPolicyAcceptedAt: privacyPolicyAcceptedAt,
            timestamp: timestamp
        )
    }
}

nonisolated struct AllModels: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var displayName: String
    var identity: AIModelIdentity
    var position: Int
    var providerID: String
    var company: String
    var price: Int
    var isEnabled: Bool
    var supportsSearch: Bool
    var supportsTextGen: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var supportReasoningChange: Bool
    var supportsImageGen: Bool
    var supportsVoiceGen: Bool
    var supportsToolUse: Bool
    var systemProvision: String
    var icon: String
    var briefDescription: String
    var characterDesign: String
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var baseModelName: String?
    var localFilename: String?
    var source: AIRecordSource
    var timestamp: Date

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        price: Int = 0,
        isEnabled: Bool = true,
        supportsSearch: Bool,
        supportsTextGen: Bool = true,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportReasoningChange: Bool = false,
        supportsImageGen: Bool,
        supportsVoiceGen: Bool,
        supportsToolUse: Bool,
        systemProvision: String = "",
        icon: String = "",
        briefDescription: String = "",
        characterDesign: String = "",
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        baseModelName: String? = nil,
        localFilename: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.identity = identity
        self.position = position
        self.providerID = AIProviderIdentifier.normalize(providerID ?? company)
        self.company = company
        self.price = price
        self.isEnabled = isEnabled
        self.supportsSearch = supportsSearch
        self.supportsTextGen = supportsTextGen
        self.supportsMultimodal = supportsMultimodal
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.supportsImageGen = supportsImageGen
        self.supportsVoiceGen = supportsVoiceGen
        self.supportsToolUse = supportsToolUse
        self.systemProvision = systemProvision
        self.icon = icon
        self.briefDescription = briefDescription
        self.characterDesign = characterDesign
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.baseModelName = baseModelName
        self.localFilename = localFilename
        self.source = source
        self.timestamp = timestamp
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String,
        identity: AIModelIdentity,
        position: Int,
        providerID: String? = nil,
        company: String,
        isHidden: Bool,
        supportsSearch: Bool,
        supportsMultimodal: Bool,
        supportsReasoning: Bool,
        supportsToolUse: Bool,
        supportsVoiceGen: Bool,
        supportsImageGen: Bool,
        iconSymbol: String? = nil,
        baseModelName: String? = nil,
        localFilename: String? = nil,
        systemPrompt: String? = nil,
        source: AIRecordSource,
        timestamp: Date = Date(),
        priceTier: Int = 0,
        supportsText: Bool = true,
        reasoningControllable: Bool = false,
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = []
    ) {
        self.init(
            id: id,
            name: name,
            displayName: displayName,
            identity: identity,
            position: position,
            providerID: providerID,
            company: company,
            price: priceTier,
            isEnabled: isHidden == false,
            supportsSearch: supportsSearch,
            supportsTextGen: supportsText,
            supportsMultimodal: supportsMultimodal,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: reasoningControllable,
            supportsImageGen: supportsImageGen,
            supportsVoiceGen: supportsVoiceGen,
            supportsToolUse: supportsToolUse,
            systemProvision: systemPrompt ?? "",
            icon: iconSymbol ?? "",
            briefDescription: "",
            characterDesign: "",
            aiToolScenarios: aiToolScenarios,
            relatedTaskCodes: relatedTaskCodes,
            baseModelName: baseModelName,
            localFilename: localFilename,
            source: source,
            timestamp: timestamp
        )
    }
}

nonisolated struct AIScenarioModelBinding: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var ownerAccountID: Int64
    var scenario: String
    var identity: AIModelIdentity
    var modelID: UUID
    var temperature: Double
    var maxTokens: Int
    var position: Int
    var isDefault: Bool
    var isActive: Bool
    var systemProvision: String
    var briefDescription: String
    var aiToolScenarios: [String]
    var relatedTaskCodes: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        ownerAccountID: Int64 = 0,
        scenario: String,
        identity: AIModelIdentity = .model,
        modelID: UUID,
        temperature: Double = Self.defaultTemperature,
        maxTokens: Int = Self.defaultMaxTokens,
        position: Int = 0,
        isDefault: Bool = false,
        isActive: Bool = true,
        systemProvision: String = "",
        briefDescription: String = "",
        aiToolScenarios: [String] = [],
        relatedTaskCodes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerAccountID = ownerAccountID
        self.scenario = scenario
        self.identity = identity
        self.modelID = modelID
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.position = position
        self.isDefault = isDefault
        self.isActive = isActive
        self.systemProvision = systemProvision
        self.briefDescription = briefDescription
        self.aiToolScenarios = aiToolScenarios
        self.relatedTaskCodes = relatedTaskCodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultTemperature: Double = 0.68
    static let defaultMaxTokens: Int = 12_800
}

nonisolated struct AISearchToolPreferences: Codable, Equatable, Sendable {
    var useKnowledge: Bool
    var knowledgeCount: Int
    var knowledgeSimilarity: Double
    var useSearch: Bool
    var bilingualSearch: Bool
    var searchCount: Int
}

nonisolated struct SearchRuntimeConfigRevision: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var schemaVersion: Int = SearchRuntimeConfigRevision.schemaVersion
    var localRevision: Int = 1
    var updatedAt: Date = Date()
    var activeSearchKeyID: UUID?
    var preferencesHash: String = ""
}

nonisolated enum SearchProviderAuthType: String, Codable, Equatable, Sendable {
    case bearer
    case headerToken
    case queryAPIKey
    case none
}

nonisolated struct SearchKeys: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var searchClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date = Date()
    var authType: SearchProviderAuthType = .bearer
    var priority: Int = 0
    var enabledScopes: [String] = ["chat", "small_task"]
    var revision: Int = 1
}

nonisolated struct ToolKeys: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var company: String
    var key: String
    var requestURL: String
    var isUsing: Bool
    var toolClass: String
    var help: String
    var source: AIRecordSource
    var timestamp: Date = Date()
}

nonisolated struct PromptRepo: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var content: String
    var isSystem: Bool
    var timestamp: Date = Date()
    var localizationKey: String?
    var position: Int = 0

    var localizedTitle: String {
        if let localizationKey, localizationKey.isEmpty == false {
            let localized = L10n.text(localizationKey)
            if localized != localizationKey { return localized }
        }
        return title
    }

    var localizedContent: String {
        if let localizationKey, localizationKey.isEmpty == false {
            let contentKey = "\(localizationKey).content"
            let localized = L10n.text(contentKey)
            if localized != contentKey { return localized }
        }
        return content
    }
}

nonisolated struct MemoryArchive: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var content: String
    var pinned: Bool
    var timestamp: Date = Date()
}

nonisolated struct TranslationDic: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var sourceText: String
    var targetText: String
    var note: String
    var timestamp: Date = Date()
}

nonisolated enum AISettingsDefaults {
    static let searchToolPreferences = AISearchToolPreferences(
        useKnowledge: true,
        knowledgeCount: 12,
        knowledgeSimilarity: 0.55,
        useSearch: true,
        bilingualSearch: true,
        searchCount: 8
    )

    static let searchKeys: [SearchKeys] = [
        SearchProviderCatalog.makeDefaultDuckDuckGoProfile()
    ]
    static let toolKeys: [ToolKeys] = []
    static let promptRepo: [PromptRepo] = []
    static let memoryArchive: [MemoryArchive] = []
    static let translationDic: [TranslationDic] = []
}

extension APIKeys {
    nonisolated var providerCompany: String { company }
    nonisolated var isHidden: Bool {
        get { isEnabled == false }
        set { isEnabled = newValue == false }
    }
}

extension AllModels {
    nonisolated var localizedDisplayName: String { displayName }
    nonisolated var localizedCompanyName: String { AIProviderLocalization.localizedCompanyName(for: company) }
    nonisolated var priceTier: Int {
        get { price }
        set { price = newValue }
    }
    nonisolated var supportsText: Bool {
        get { supportsTextGen }
        set { supportsTextGen = newValue }
    }
    nonisolated var isHidden: Bool {
        get { isEnabled == false }
        set { isEnabled = newValue == false }
    }
    nonisolated var isLocalModel: Bool {
        providerID.uppercased() == "LOCAL"
    }
    nonisolated var iconSymbol: String? {
        get { icon.isEmpty ? nil : icon }
        set { icon = newValue ?? "" }
    }
    nonisolated var systemPrompt: String {
        get { systemProvision }
        set { systemProvision = newValue }
    }
    nonisolated var reasoningControllable: Bool {
        get { supportReasoningChange }
        set { supportReasoningChange = newValue }
    }
    var selectedToolNames: Set<String> {
        get { SparkToolName.selectedSet(fromStoredToolNames: aiToolScenarios) }
        set { aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: newValue) }
    }
}
