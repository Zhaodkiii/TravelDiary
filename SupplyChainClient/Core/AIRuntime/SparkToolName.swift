import Foundation

enum SparkToolName: String, CaseIterable {
    case fetchStepDetails = "fetch_step_details"
    case fetchEnergyDetails = "fetch_energy_details"
    case fetchNutritionDetails = "fetch_nutrition_details"
    case makeNutritionData = "make_nutrition_data"
    case showMedicalRiskNotice = "show_medical_risk_notice"
    case fetchSleepDetails = "fetch_sleep_details"
    case fetchWorkoutDetails = "fetch_workout_details"
    case generateStructuredHealthCard = "generate_structured_health_card"
    case listMemberHealthSources = "list_member_health_sources"
    case getHealthResourceReference = "get_health_resource_reference"
    case getHealthResourceContext = "get_health_resource_context"
    case searchKnowledgeBag = "search_knowledge_bag"
    case createKnowledgeDocument = "create_knowledge_document"
    case searchCalendarAndReminders = "search_calendar_and_reminders"
    case writeSystemEvent = "write_system_event"
    case queryLocation = "query_location"
    case getCurrentLocation = "get_current_location"
    case searchNearbyLocations = "search_nearby_locations"
    case getRoute = "get_route"
    case queryWeather = "query_weather"
    case saveMemory = "save_memory"
    case retrieveMemory = "retrieve_memory"
    case updateMemory = "update_memory"
    case generateChatTitle = "generate_chat_title"
    case showCustomMessageCard = "show_custom_message_card"
    case askUserQuestion = "ask_user_question"
    case getCurrentMember = "get_current_member"
    case requestMemberSelection = "request_member_selection"
    case switchMember = "switch_member"
    case findMember = "find_member"
    case queryMemberProfile = "query_member_profile"
    case searchOnline = "search_online"
    case readWebPage = "read_web_page"
    case searchArxivPapers = "search_arxiv_papers"
    case extractRemoteFileContent = "extract_remote_file_content"
    case createCanvas = "create_canvas"
    case editCanvas = "edit_canvas"
    case queryTasksByMember = "query_tasks_by_member"
    case generateTask = "generate_task"

    static var all: [String] { allCases.map(\.rawValue) }
}

extension SparkToolName {
    static let noSelectionSentinel = "__spark_tools_none__"

    static func displayName(for toolName: String) -> String {
        L10n.text("ai_settings.tools.\(toolName)")
    }

    static func selectedSet(fromStoredToolNames toolNames: [String]) -> Set<String> {
        if toolNames.contains(noSelectionSentinel) {
            return []
        }
        let normalized = Set(toolNames).intersection(Set(all))
        return normalized.isEmpty ? Set(all) : normalized
    }

    static func storageValues(forSelectedToolNames selectedToolNames: Set<String>) -> [String] {
        let normalized = selectedToolNames.intersection(Set(all))
        return normalized.isEmpty ? [noSelectionSentinel] : normalized.sorted()
    }
}

enum SparkToolGroup: String, CaseIterable {
    case health
    case member
    case location
    case memory
    case knowledge
    case system

    var localizedTitle: String {
        L10n.text("ai_settings.tool_groups.\(rawValue)")
    }

    var localizedDescription: String {
        L10n.text("ai_settings.tool_groups.\(rawValue).description")
    }

    var iconSystemName: String {
        switch self {
        case .health: "heart.text.square"
        case .member: "person.2"
        case .location: "location"
        case .memory: "brain.head.profile"
        case .knowledge: "books.vertical"
        case .system: "calendar.badge.clock"
        }
    }

    var tools: [SparkToolName] {
        switch self {
        case .health:
            return [.fetchStepDetails, .fetchEnergyDetails, .fetchNutritionDetails, .makeNutritionData, .fetchSleepDetails, .fetchWorkoutDetails, .generateStructuredHealthCard, .listMemberHealthSources, .getHealthResourceReference, .getHealthResourceContext]
        case .member:
            return [.getCurrentMember, .requestMemberSelection, .switchMember, .findMember, .queryMemberProfile]
        case .location:
            return [.queryLocation, .getCurrentLocation, .searchNearbyLocations, .getRoute, .queryWeather]
        case .memory:
            return [.saveMemory, .retrieveMemory, .updateMemory, .generateChatTitle]
        case .knowledge:
            return [.searchKnowledgeBag, .createKnowledgeDocument, .searchOnline, .readWebPage, .searchArxivPapers, .extractRemoteFileContent]
        case .system:
            return [.searchCalendarAndReminders, .writeSystemEvent, .showCustomMessageCard, .showMedicalRiskNotice, .createCanvas, .editCanvas, .queryTasksByMember, .generateTask, .askUserQuestion]
        }
    }

    var toolRawValues: [String] {
        tools.map(\.rawValue)
    }
}
