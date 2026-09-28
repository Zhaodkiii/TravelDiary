import SwiftUI

/// 对齐 Health `EditModelSheetView` 子集：显示名、SF 图标、非 LOCAL 且非系统时的能力开关。
struct EditSparkModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    let modelID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var iconSymbol = ModelIconCatalog.fallbackSymbol
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var selectedTaskCodes: Set<String> = []
    @State private var showIconPicker = false
    @State private var hasSyncedFromModel = false

    private var model: AllModels? {
        viewModel.snapshot.allModels.first(where: { $0.id == modelID })
    }

    private var canEditCapabilities: Bool {
        guard let m = model else { return false }
        return AIProviderAdapterRegistry.adapter(for: m.providerID).isLocal == false
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                Section(L10n.text("common.name", comment: "名称")) {
                    TextField(L10n.text("ai_settings.models.edit.field.display_name", comment: "显示名称"), text: $displayName)
                }
                Section(L10n.text("ai_settings.models.edit.section.icon", comment: "图标")) {
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
                if canEditCapabilities {
                    Section(L10n.text("ai_settings.models.online.section.usage", comment: "使用场景与工具")) {
                        MainNavigationLink {
                            if let model {
                                ModelScenarioBindingsEditorView(
                                    scenarioBindings: $viewModel.snapshot.scenarioBindings,
                                    modelID: model.id,
                                    identity: model.identity,
                                    defaultSystemProvision: model.systemProvision,
                                    defaultBriefDescription: model.briefDescription,
                                    defaultToolScenarios: model.aiToolScenarios,
                                    defaultRelatedTaskCodes: model.relatedTaskCodes,
                                    smallTasks: viewModel.effectiveSmallTasks,
                                    promptTooling: viewModel.promptTooling,
                                    promptTemplates: viewModel.snapshot.promptRepo,
                                    onPersist: { change in
                                        Task { await viewModel.persistScenarioBindingChange(change) }
                                    }
                                )
                            }
                        } label: {
                            HStack {
                                Text(L10n.text("ai_settings.models.online.field.scenarios", comment: "使用场景"))
                                Spacer()
                                Text("\(scenarioBindingCount)")
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

                        MainNavigationLink {
                            
                            MultiSelectOptionsView(
                                title: L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务选择页标题"),
                                options: viewModel.effectiveSmallTasks.map { ($0.code, L10n.format("ai_settings.models.agent.related_tasks.option_format", fallback: "%@ (%@)", comment: "关联小任务选项格式", $0.name, $0.code)) },
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

                    Section(L10n.text("ai_settings.models.edit.section.capabilities", comment: "能力")) {
                        Toggle(L10n.text("ai_settings.models.online.toggle.supports_text", comment: "支持文本"), isOn: $supportsText)
                        Toggle(L10n.text("ai_settings.field.supports_multimodal", comment: "支持多模态"), isOn: $supportsMultimodal)
                        Toggle(L10n.text("ai_settings.field.supports_reasoning", comment: "支持推理"), isOn: $supportsReasoning)
                        Toggle(L10n.text("ai_settings.field.reasoning_controllable", comment: "思考可控"), isOn: $reasoningControllable)
                        Toggle(L10n.text("ai_settings.field.supports_tool_use", comment: "支持工具调用"), isOn: $supportsToolUse)
                        Toggle(L10n.text("ai_settings.models.online.toggle.image_gen", comment: "生图"), isOn: $supportsImageGen)
                    }
                }
            }
            .navigationTitle(L10n.text("ai_settings.models.edit.nav_title", comment: "编辑模型"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", comment: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save", comment: "保存")) { save() }
                }
            }
            .sheet(isPresented: $showIconPicker) {
                ModelIconPickerSheet(selectedIcon: $iconSymbol)
            }
            .onAppear {
                guard hasSyncedFromModel == false else { return }
                syncFromModel()
                hasSyncedFromModel = true
            }
        }
    }

    private func syncFromModel() {
        guard let m = model else { return }
        displayName = m.displayName
        iconSymbol = m.iconSymbol ?? ModelIconCatalog.fallbackSymbol
        supportsText = m.supportsText
        supportsMultimodal = m.supportsMultimodal
        supportsReasoning = m.supportsReasoning
        reasoningControllable = m.reasoningControllable
        supportsToolUse = m.supportsToolUse
        supportsImageGen = m.supportsImageGen
        selectedToolNames = m.selectedToolNames
        selectedTaskCodes = Set(m.relatedTaskCodes)
    }

    private func save() {
        guard var m = viewModel.snapshot.allModels.first(where: { $0.id == modelID }) else {
            dismiss()
            return
        }
        m.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        m.iconSymbol = iconSymbol
        if canEditCapabilities {
            m.supportsText = supportsText
            m.supportsMultimodal = supportsMultimodal
            m.supportsReasoning = supportsReasoning
            m.reasoningControllable = reasoningControllable
            m.supportsToolUse = supportsToolUse
            m.supportsImageGen = supportsImageGen
            m.aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: selectedToolNames)
            m.relatedTaskCodes = selectedTaskCodes.sorted()
        }
        Task {
            let didSave = await viewModel.replaceModelAndPersist(m)
            if didSave {
                await MainActor.run { dismiss() }
            }
        }
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("common.all", comment: "全部")
        }
        return "\(selectedToolNames.count)/\(total)"
    }

    private var scenarioBindingCount: Int {
        guard let identity = model?.identity else { return 0 }
        return viewModel.snapshot.scenarioBindings.filter {
            $0.modelID == modelID && $0.identity == identity
        }.count
    }
}
