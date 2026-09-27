import SwiftUI

/// 新建或编辑智能体（对齐 Health `AddAgentView` 的基础字段）。
struct ModelsSettingsAgentSheet: View {
    let baseModels: [AllModels]
    var editingAgent: AllModels?
    var scenarioBindings: [AIScenarioModelBinding] = []
    var smallTasks: [SmallTask] = []
    var promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling()
    var promptTemplates: [PromptRepo] = []
    let onCreate: (String, String, String, String, [String], [String], [String], [AIScenarioModelBinding]) -> Void
    let onUpdate: ((UUID, String, String, String, String, [String], [String], [String], [AIScenarioModelBinding]) -> Void)?
    var onPersistScenarioBindings: ((ModelScenarioBindingPersistenceChange) -> Void)?

    @State private var displayName = ""
    @State private var iconSymbol = "stethoscope"
    @State private var selectedBaseModelName = ""
    @State private var systemPrompt = ""
    @State private var draftAgentID = UUID()
    @State private var draftScenarioBindings: [AIScenarioModelBinding] = []
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var selectedTaskCodes: Set<String> = []
    @State private var showIconPicker = false
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false
    @State private var autoFillInProgress = false
    @State private var autoFilled = false
    @State private var autoFillOriginalText = ""
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss
    @State private var hasSyncedFromModel = false

    private var isEditing: Bool { editingAgent != nil }

    var body: some View {
        List {
            Section(L10n.text("ai_settings.models.agent.section.icons", comment: "图标选择")) {
                HStack {
                    Spacer()
                    Button {
                        showIconPicker = true
                    } label: {
                        Image(systemName: iconSymbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section(L10n.text("ai_settings.models.agent.section.basic", comment: "基础信息")) {
                TextField(L10n.text("ai_settings.models.agent.field.name", comment: "智能体名称"), text: $displayName)
            }

            Section(L10n.text("ai_settings.models.agent.section.system_prompt", comment: "智能体设定")) {
                PromptInputEditorView(
                    text: $systemPrompt,
                    promptTemplates: promptTemplates,
                    isAutoFillInProgress: autoFillInProgress,
                    isAutoFilled: autoFilled,
                    isAutoFillDisabled: displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    onAutoFill: runAutoFill,
                    onVoiceInput: { showVoiceInput = true },
                    onTextInput: { showTextInputDrawer = true }
                )

                MainNavigationLink {
                    MultiSelectOptionsView(
                        title: L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务选择页标题"),
                        options: smallTasks.map { ($0.code, L10n.format("ai_settings.models.agent.related_tasks.option_format", fallback: "%@ (%@)", comment: "关联小任务选项格式", $0.name, $0.code)) },
                        selectedValues: $selectedTaskCodes
                    )
                } label: {
                    HStack {
                        Text(L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务"))
                        Spacer()
                        Text("\(selectedTaskCodes.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L10n.text("ai_settings.models.agent.section.base_model", comment: "基础模型")) {
                Picker(L10n.text("ai_settings.models.agent.field.base_model", comment: "基座模型"), selection: $selectedBaseModelName) {
                    ForEach(baseModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                if let selectedModel = baseModels.first(where: { $0.name == selectedBaseModelName }) {
                    AgentBaseModelPreview(model: selectedModel)
                } else if baseModels.isEmpty {
                    Text(L10n.text("ai_settings.models.agent.empty.base_models", comment: "暂无可用基础模型提示"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L10n.text("ai_settings.models.online.section.usage", comment: "使用场景与工具")) {
                MainNavigationLink {
                    ModelScenarioBindingsEditorView(
                        scenarioBindings: $draftScenarioBindings,
                        modelID: editingAgent?.id ?? draftAgentID,
                        identity: .agent,
                        defaultSystemProvision: systemPrompt,
                        defaultToolScenarios: SparkToolName.storageValues(forSelectedToolNames: selectedToolNames),
                        defaultRelatedTaskCodes: selectedTaskCodes.sorted(),
                        smallTasks: smallTasks,
                        promptTooling: promptTooling,
                        promptTemplates: promptTemplates,
                        onPersist: { change in
                            guard editingAgent != nil else { return }
                            onPersistScenarioBindings?(change)
                        }
                    )
                } label: {
                    HStack {
                        Text(L10n.text("ai_settings.models.online.field.scenarios", comment: "使用场景"))
                        Spacer()
                        Text("\(draftScenarioBindings.filter { $0.modelID == (editingAgent?.id ?? draftAgentID) }.count)")
                            .foregroundStyle(.secondary)
                    }
                }

                MainNavigationLink {
                    GroupedToolSelectionView(
                        title: L10n.text("common.tools", comment: "工具"),
                        selectedValues: $selectedToolNames
                    )
                } label: {
                    HStack {
                        Text(L10n.text("common.tools", comment: "工具"))
                        Spacer()
                        Text(selectedToolsSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(isEditing ? L10n.text("ai_settings.models.agent.nav.edit_title", comment: "编辑智能体") : L10n.text("ai_settings.models.agent.nav.new_title", comment: "新建智能体"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel", comment: "取消")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? L10n.text("common.save", comment: "保存") : L10n.text("ai_settings.models.agent.action.create", comment: "创建")) {
                    if isEditing, let agent = editingAgent {
                        onUpdate?(
                            agent.id,
                            displayName,
                            iconSymbol,
                            selectedBaseModelName,
                            systemPrompt,
                            scenarioRawValues,
                            SparkToolName.storageValues(forSelectedToolNames: selectedToolNames),
                            selectedTaskCodes.sorted(),
                            draftScenarioBindings
                        )
                    } else {
                        onCreate(
                            displayName,
                            iconSymbol,
                            selectedBaseModelName,
                        systemPrompt,
                        scenarioRawValues,
                        SparkToolName.storageValues(forSelectedToolNames: selectedToolNames),
                        selectedTaskCodes.sorted(),
                        draftScenarioBindings
                    )
                    }
                    dismiss()
                }
                .disabled(canSave == false)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ModelIconPickerSheet(selectedIcon: $iconSymbol)
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $systemPrompt,
                isPresented: $showTextInputDrawer,
                onAutoFill: {
                    try await promptTooling.autoFillAgentPrompt(displayName: displayName, baseModelName: selectedBaseModelName)
                },
                onTranslate: {
                    try await promptTooling.translate(text: systemPrompt)
                },
                onOCRImage: { image in
                    try await promptTooling.ocrImage(image)
                }
            )
                .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $systemPrompt,
                isPresented: $showVoiceInput,
                onPolish: {
                    try await promptTooling.autoFillAgentPrompt(displayName: displayName, baseModelName: selectedBaseModelName)
                }
            )
                .sparkInputPresentationChromeIfAvailable()
        }
        .alert(L10n.text("common.operation_failed", comment: "操作失败"), isPresented: Binding(
            get: { actionError != nil },
            set: { if $0 == false { actionError = nil } }
        )) {
            Button(L10n.text("common.ok", comment: "确定")) {}
        } message: {
            Text(actionError ?? "")
        }
        .onAppear {
            guard hasSyncedFromModel == false else { return }

            if let agent = editingAgent {
                displayName = agent.displayName
                iconSymbol = agent.iconSymbol ?? "stethoscope"
                selectedBaseModelName = agent.baseModelName ?? ""
                systemPrompt = agent.systemPrompt ?? ""
                draftScenarioBindings = scenarioBindings.filter { $0.modelID == agent.id }
                selectedToolNames = agent.selectedToolNames
                selectedTaskCodes = Set(agent.relatedTaskCodes)
            } else if selectedBaseModelName.isEmpty, let first = baseModels.first {
                selectedBaseModelName = first.name
            }
            hasSyncedFromModel = true
        }
    }

    private func runAutoFill() {
        if autoFilled {
            systemPrompt = autoFillOriginalText
            autoFilled = false
            autoFillOriginalText = ""
            return
        }
        autoFillOriginalText = systemPrompt
        autoFillInProgress = true
        Task {
            do {
                let raw = try await promptTooling.autoFillAgentPrompt(displayName: displayName, baseModelName: selectedBaseModelName)
                let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if result.isEmpty == false {
                    systemPrompt = result
                    autoFilled = true
                }
            } catch {
                actionError = error.localizedDescription
            }
            autoFillInProgress = false
        }
    }

    private var canSave: Bool {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        selectedBaseModelName.isEmpty == false &&
        systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var scenarioRawValues: [String] {
        draftScenarioBindings
            .filter { $0.modelID == (editingAgent?.id ?? draftAgentID) && $0.isActive }
            .map(\.scenario)
            .sorted()
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("common.all", comment: "全部")
        }
        return "\(selectedToolNames.count)/\(total)"
    }
}

/// 与 `ModelsSettingsView` 内原 `BaseModelCard` 一致，供智能体 Sheet 预览基座模型。
private struct AgentBaseModelPreview: View {
    let model: AllModels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.displayName)
                .font(.headline)
            Text(model.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                capabilityChip(model.isLocalModel ? L10n.text("ai_settings.models.badge.local", comment: "本地") : L10n.text("ai_settings.models.badge.service", comment: "服务"), enabled: true)
                capabilityChip(L10n.text("ai_settings.models.capability.reasoning", comment: "推理"), enabled: model.supportsReasoning)
                capabilityChip(L10n.text("common.tools", comment: "工具"), enabled: model.supportsToolUse)
                capabilityChip(L10n.text("ai_settings.models.capability.multimodal", comment: "多模态"), enabled: model.supportsMultimodal)
            }
        }
        .padding(.vertical, 4)
    }

    private func capabilityChip(_ title: String, enabled: Bool) -> some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(enabled ? Color.green.opacity(0.2) : Color.gray.opacity(0.12))
            .clipShape(Capsule())
    }
}
