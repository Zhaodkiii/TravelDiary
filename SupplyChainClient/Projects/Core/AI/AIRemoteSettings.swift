import Foundation

protocol AIRemoteConfigProvider: Sendable {
    func fetchRemotePatch() async throws -> AIRemoteSettingsPatch
}

struct AIRemoteSettingsPatch: Equatable, Sendable {
    var revision: String?
    /// Pro 专属场景模型（仅内存，不落库）。
    var scenarioRemoteBundles: AIScenarioRemoteBundlesCollection?
    var smallTasks: [SmallTask]

    init(
        revision: String? = nil,
        scenarioRemoteBundles: AIScenarioRemoteBundlesCollection? = nil,
        smallTasks: [SmallTask] = []
    ) {
        self.revision = revision
        self.scenarioRemoteBundles = scenarioRemoteBundles
        self.smallTasks = smallTasks
    }
}

struct AIRemoteUserInfoPatch: Equatable, Sendable {
    var chooseEmbeddingModel: String?
    var optimizationTextModel: String?
    var optimizationVisualModel: String?
    var contextFoldingModel: String?
    var routerModel: String?
    var dataExtractionModel: String?
    var reportInterpretationModel: String?
    var textToSpeechModel: String?
    var useContextFolding: Bool?
    var maxToolSets: Int?
    var useKnowledge: Bool?
    var knowledgeCount: Int?
    var knowledgeSimilarity: Double?
    var useSearch: Bool?
    var bilingualSearch: Bool?
    var searchCount: Int?
    var useMap: Bool?
    var useCalendar: Bool?
    var useWeather: Bool?
    var useCanvas: Bool?
    var useCode: Bool?
}
