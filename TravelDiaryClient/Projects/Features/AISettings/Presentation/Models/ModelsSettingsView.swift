import SwiftUI

/// AI 设置「模型」子页：对齐 Health `ModelsView` — 试用区 + 单一主列表（`unifiedModels`）、菜单添加在线/本地/智能体、高级子页、行内编辑 Sheet。

struct ModelsSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var searchText = ""
    @State private var selectedIdentity: ModelsSettingsIdentityFilter = .all
    @State private var isEditing = false

    @State private var showAddOnline = false
    @State private var showLocalDownload = false
    @State private var showAgentSheet = false
    @State private var editingAgent: AllModels?

    @State private var inlineError: String?

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 未隐藏且已配置密钥的 provider，按稳定 `providerID` 参与模型可见性。
    private var visibleProviderIDs: Set<String> {
        Set(
            viewModel.snapshot.apiKeys
                .filter {
                    $0.isHidden == false &&
                    $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
                .map(\.providerID)
                .filter { !$0.isEmpty }
        )
    }

    /// 供智能体表单选择基座：本地 GGUF + 已配置密钥的服务模型。
    private var baseModelsForAgent: [AllModels] {
        viewModel.snapshot.allModels
            .filter { $0.identity == .model && $0.supportsTextGen && $0.isEnabled }
            .filter { $0.isLocalModel || viewModel.hasValidAPIKey(for: $0) }
            .sorted { $0.position < $1.position }
    }

    /// 主列表：身份 + API Key 可见性 + 仅 `displayName` 搜索（含拼音），按 `position` 排序。
    private var unifiedModels: [AllModels] {
        viewModel.snapshot.allModels
            .filter(matchesIdentity)
            .filter(matchesApiKeyVisibility)
            .filter(matchesSearchUnified)
            .sorted { $0.position < $1.position }
    }

    private var searchPrompt: String {
        selectedIdentity == .agent
            ? L10n.text("ai_settings.models.search.agents")
            : L10n.text("ai_settings.models.search.models")
    }

    /// 与 Health 一致：`all` / `model` 下标题均为「模型」，仅 `agent` 分段为智能体标题。
    private var titleText: String {
        selectedIdentity == .agent
            ? L10n.text("ai_settings.models.nav_title.agents")
            : L10n.text("ai_settings.models.nav_title.models")
    }

    var body: some View {
        VStack {
            List {
                mainModelsSection
            }
        }
        .navigationTitle(titleText)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 75)
        }
        .searchable(text: $searchText, prompt: searchPrompt)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isEditing.toggle() }) {
                    Image(systemName: isEditing ? "checkmark.circle" : "line.3.horizontal")
                }
            }

            ToolbarItem(placement: .principal) {
                if !isEditing {
                    Picker("", selection: $selectedIdentity) {
                        ForEach(ModelsSettingsIdentityFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedTitle).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            ToolbarItem(placement: .navigationBarLeading) {
                if isEditing {
                    Button {
                        resetModelPositionToDefault()
                    } label: {
                        Label(L10n.text("ai_settings.toolbar.reset_sort"), systemImage: "arrow.up.arrow.down")
                    }
                } else {
                    Menu {
                        Button {
                            showAddOnline = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_online_model"), systemImage: "cloud")
                        }

                        Button {
                            showLocalDownload = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_local_model"), systemImage: "externaldrive")
                        }

                        Button {
                            editingAgent = nil
                            showAgentSheet = true
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.add_agent"), systemImage: "person.crop.circle.badge.plus")
                        }

                        MainNavigationLink {
                            ModelsAdvancedEditorView(
                                models: Binding(
                                    get: { viewModel.snapshot.allModels },
                                    set: { viewModel.replaceAllModels($0) }
                                ),
                                selectedIdentity: $selectedIdentity,
                                searchText: $searchText
                            )
                        } label: {
                            Label(L10n.text("ai_settings.models.menu.advanced"), systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .environment(\.editMode, .constant(isEditing ? .active : .inactive))
        .onAppear {
            Task {
                await viewModel.initializeModelVisibilityAndPersistIfNeeded()
            }
        }
        .sheet(isPresented: $showAddOnline) {
            AddOnlineModelSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showLocalDownload) {
            LocalModelDownloadSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAgentSheet) {
            CompatibleNavigationContainer {
                ModelsSettingsAgentSheet(
                    baseModels: baseModelsForAgent,
                    editingAgent: editingAgent,
                    scenarioBindings: viewModel.snapshot.scenarioBindings,
                    smallTasks: viewModel.effectiveSmallTasks,
                    promptTooling: viewModel.promptTooling,
                    promptTemplates: viewModel.snapshot.promptRepo,
                    onCreate: { displayName, iconSymbol, baseModelName, systemPrompt, aiScenarios, aiToolScenarios, relatedTaskCodes, scenarioBindings in
                        Task {
                            await viewModel.createLocalAgentAndPersist(
                                displayName: displayName,
                                iconSymbol: iconSymbol,
                                baseModelName: baseModelName,
                                systemPrompt: systemPrompt,
                                aiScenarios: aiScenarios,
                                aiToolScenarios: aiToolScenarios,
                                relatedTaskCodes: relatedTaskCodes,
                                scenarioBindings: scenarioBindings
                            )
                        }
                    },
                    onUpdate: { id, displayName, iconSymbol, baseModelName, systemPrompt, aiScenarios, aiToolScenarios, relatedTaskCodes, scenarioBindings in
                        Task {
                            await viewModel.updateLocalAgentAndPersist(
                                id: id,
                                displayName: displayName,
                                iconSymbol: iconSymbol,
                                baseModelName: baseModelName,
                                systemPrompt: systemPrompt,
                                aiScenarios: aiScenarios,
                                aiToolScenarios: aiToolScenarios,
                                relatedTaskCodes: relatedTaskCodes,
                                scenarioBindings: scenarioBindings
                            )
                        }
                    },
                    onPersistScenarioBindings: { change in
                        guard editingAgent != nil else { return }
                        Task {
                            await viewModel.persistScenarioBindingChange(change)
                        }
                    }
                )
            }
            .onDisappear {
                editingAgent = nil
            }
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { inlineError != nil },
            set: { presented in
                if presented == false {
                    inlineError = nil
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(inlineError ?? "")
        }
        .task {
            await viewModel.refreshTrialStatus()
        }
    }

    // MARK: - Sections

    private var mainModelsSection: some View {
        Section {
            if unifiedModels.isEmpty {
                Text(
                    normalizedSearch.isEmpty
                        ? L10n.text("ai_settings.models.empty.list_none")
                        : L10n.text("ai_settings.models.empty.advanced_no_match")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(unifiedModels) { model in
                    ModelsSettingsMainRow(
                        model: model,
                        viewModel: viewModel,
                        isEditing: isEditing,
                        priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                        priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                        onDelete: { performDelete(model) }
                    )
                }
                .onMove(perform: moveUnifiedModels)
            }
        }
    }

    // MARK: - Filtering & keys

    private func matchesIdentity(_ model: AllModels) -> Bool {
        switch selectedIdentity {
        case .all:
            return true
        case .model:
            return model.identity == .model
        case .agent:
            return model.identity == .agent
        }
    }

    /// 非本地目录行时，模型 provider 须在可见密钥集合中。
    private func matchesApiKeyVisibility(_ model: AllModels) -> Bool {
        if AIProviderAdapterRegistry.adapter(for: model.providerID).isLocal {
            return true
        }
        guard model.providerID.isEmpty == false else { return false }
        return visibleProviderIDs.contains(model.providerID)
    }

    /// 有搜索词时仅匹配非空 `displayName`（原文 + 拼音）。
    private func matchesSearchUnified(_ model: AllModels) -> Bool {
        guard normalizedSearch.isEmpty == false else { return true }
        let dn = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard dn.isEmpty == false else { return false }
        if dn.lowercased().contains(normalizedSearch) { return true }
        return dn.toPinyinForSearch().lowercased().contains(normalizedSearch)
    }

    private func performDelete(_ model: AllModels) {
        Task {
            let ok: Bool
            if model.isLocalModel {
                ok = await viewModel.removeLocalModelAndPersist(model)
            } else {
                ok = await viewModel.deleteModelAndPersist(id: model.id)
            }
            if ok == false {
                inlineError = viewModel.errorMessage
            }
        }
    }

    /// 与 Health `moveModel`：列表索引为模型 `position`；智能体为 `index + 1000`。
    private func moveUnifiedModels(from source: IndexSet, to destination: Int) {
        var reordered = unifiedModels
        reordered.move(fromOffsets: source, toOffset: destination)
        var positions: [UUID: Int] = [:]
        for (index, model) in reordered.enumerated() {
            var positionIndex = index
            if model.identity == .agent {
                positionIndex = index + 1000
            }
            positions[model.id] = positionIndex
        }
        viewModel.updateModelPositions(positions)
    }

    private func resetModelPositionToDefault() {
        let sortedByName = viewModel.snapshot.allModels.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        var positions: [UUID: Int] = [:]
        for (index, model) in sortedByName.enumerated() {
            positions[model.id] = model.identity == .agent ? index + 1000 : index
        }
        viewModel.updateModelPositions(positions)
    }
}

/// SwiftUI 预览：使用内存 Core Data 仓储，嵌入 `NavigationView` 以展示导航栏与工具栏。
@MainActor
private struct ModelsSettingsPreviewHost: View {
    @StateObject private var viewModel: AISettingsViewModel

    init() {
        let repository = DefaultAISettingsRepository(
            coreDataStack: CoreDataStack(inMemory: true)
        )
        let vm = AISettingsViewModel(
            loadUseCase: LoadAISettingsUseCase(repository: repository),
            saveUseCase: SaveAISettingsUseCase(repository: repository)
        )
        vm.snapshot = AISettingsSnapshot.default
        vm.snapshot.allModels = Self.sampleModels
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        CompatibleNavigationContainer {
            ModelsSettingsView(
                viewModel: viewModel
            )
        }
    }

    private static var sampleModels: [AllModels] {
        [
            AllModels(
                name: "local-qwen25-15b",
                displayName: "Qwen2.5 1.5B",
                identity: .model,
                position: 1,
                providerID: LocalModelService.localProviderID,
                company: LocalModelService.localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "cpu",
                baseModelName: nil,
                localFilename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
                systemPrompt: nil,
                source: .custom,
                timestamp: Date()
            ),
            AllModels(
                name: "local-agent-demo",
                displayName: "健康问答助手",
                identity: .agent,
                position: 1000,
                providerID: LocalModelService.localProviderID,
                company: LocalModelService.localCompany,
                isHidden: false,
                supportsSearch: true,
                supportsMultimodal: false,
                supportsReasoning: true,
                supportsToolUse: true,
                supportsVoiceGen: false,
                supportsImageGen: false,
                iconSymbol: "heart.text.square",
                baseModelName: "local-qwen25-15b",
                localFilename: nil,
                systemPrompt: "你是一个专业且友好的健康问答助手。",
                source: .custom,
                timestamp: Date()
            )
        ]
    }
}

@MainActor
struct ModelsSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ModelsSettingsPreviewHost()
                .preferredColorScheme(.light)

            ModelsSettingsPreviewHost()
                .preferredColorScheme(.dark)
        }
    }
}
