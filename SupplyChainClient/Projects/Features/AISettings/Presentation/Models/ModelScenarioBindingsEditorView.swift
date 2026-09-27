import SwiftUI

struct ModelScenarioBindingPersistenceChange {
    var upserted: AIScenarioModelBinding?
    var deletedID: UUID?
}

struct ModelScenarioBindingsEditorView: View {
    @Binding var scenarioBindings: [AIScenarioModelBinding]
    let modelID: UUID
    let identity: AIModelIdentity
    var defaultSystemProvision: String = ""
    var defaultBriefDescription: String = ""
    var defaultToolScenarios: [String] = []
    var defaultRelatedTaskCodes: [String] = []
    var smallTasks: [SmallTask] = []
    var promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling()
    var promptTemplates: [PromptRepo] = []
    var onPersist: ((ModelScenarioBindingPersistenceChange) -> Void)?

    @State private var presentedMode: ModelScenarioBindingEditorMode?

    private var bindings: [AIScenarioModelBinding] {
        scenarioBindings
            .filter { $0.modelID == modelID && $0.identity == identity }
            .sorted {
                if $0.scenario != $1.scenario { return $0.scenario < $1.scenario }
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.createdAt < $1.createdAt
            }
    }

    private var availableScenarios: [AIScenario] {
        let existing = Set(bindings.map(\.scenario))
        return AIScenario.allCases.filter { existing.contains($0.rawValue) == false }
    }

    var body: some View {
        List {
            if bindings.isEmpty {
                Text(L10n.text("ai_settings.models.online.selection.none", comment: "未设置"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bindings) { binding in
                    Button {
                        presentedMode = .edit(binding.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AIScenario(rawValue: binding.scenario)?.localizedTitle ?? binding.scenario)
                            HStack(spacing: 8) {
                                if binding.isDefault {
                                    Text(L10n.text("ai_settings.scenario_default_hint", comment: "默认"))
                                }
                                Text(String(format: "%.2f", binding.temperature))
                                Text("\(binding.maxTokens)")
                                if binding.isActive == false {
                                    Text(L10n.text("ai_settings.scenario_binding.inactive", comment: "未启用"))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteBindings)
            }
        }
        .navigationTitle(L10n.text("ai_settings.models.online.field.scenarios", comment: "使用场景"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    presentedMode = .add
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(availableScenarios.isEmpty)
            }
        }
        .sheet(item: $presentedMode) { mode in
            CompatibleNavigationContainer {
                ModelScenarioBindingAddView(
                    mode: mode,
                    availableScenarios: availableScenarios,
                    makeBinding: makeBinding(for:),
                    existingBinding: existingBinding(for: mode),
                    smallTasks: smallTasks,
                    promptTooling: promptTooling,
                    promptTemplates: promptTemplates,
                    onCancel: { presentedMode = nil },
                    onSave: { binding in
                        saveBinding(binding, mode: mode)
                        presentedMode = nil
                    }
                )
            }
        }
    }

    private func makeBinding(for scenario: AIScenario) -> AIScenarioModelBinding {
        let bindingsInScenario = scenarioBindings.filter { $0.scenario == scenario.rawValue }
        return AIScenarioModelBinding(
            scenario: scenario.rawValue,
            identity: identity,
            modelID: modelID,
            temperature: AIScenarioModelBinding.defaultTemperature,
            maxTokens: AIScenarioModelBinding.defaultMaxTokens,
            position: (bindingsInScenario.map(\.position).max() ?? -1) + 1,
            isDefault: bindingsInScenario.contains(where: { $0.isDefault }) == false,
            isActive: true,
            systemProvision: defaultSystemProvision,
            briefDescription: defaultBriefDescription,
            aiToolScenarios: defaultToolScenarios,
            relatedTaskCodes: defaultRelatedTaskCodes
        )
    }

    private func existingBinding(for mode: ModelScenarioBindingEditorMode) -> AIScenarioModelBinding? {
        switch mode {
        case .add:
            return nil
        case .edit(let id):
            return scenarioBindings.first(where: { $0.id == id })
        }
    }

    private func saveBinding(_ binding: AIScenarioModelBinding, mode: ModelScenarioBindingEditorMode) {
        var binding = binding
        binding.updatedAt = Date()
        if binding.isDefault {
            for index in scenarioBindings.indices where scenarioBindings[index].scenario == binding.scenario {
                guard scenarioBindings[index].id != binding.id, scenarioBindings[index].isDefault else { continue }
                scenarioBindings[index].isDefault = false
                scenarioBindings[index].updatedAt = Date()
            }
        }

        switch mode {
        case .add:
            scenarioBindings.append(binding)
        case .edit(let id):
            guard let index = scenarioBindings.firstIndex(where: { $0.id == id }) else { return }
            scenarioBindings[index] = binding
        }

        onPersist?(ModelScenarioBindingPersistenceChange(upserted: binding))
    }

    private func deleteBindings(at offsets: IndexSet) {
        let ids = offsets.map { bindings[$0].id }
        scenarioBindings.removeAll { ids.contains($0.id) }
        for id in ids {
            onPersist?(ModelScenarioBindingPersistenceChange(deletedID: id))
        }
    }
}

private enum ModelScenarioBindingEditorMode: Identifiable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let id):
            return "edit-\(id.uuidString)"
        }
    }
}


/// 模型 - 场景绑定 添加/编辑页面
/// 用于给模型绑定使用场景（如聊天、总结、写作等），支持新增和编辑两种模式
private struct ModelScenarioBindingAddView: View {
    // MARK: - 入参属性
    /// 编辑模式：新增 / 编辑
    let mode: ModelScenarioBindingEditorMode
    /// 可供选择的所有场景列表
    let availableScenarios: [AIScenario]
    /// 根据选中场景创建绑定关系的工厂方法
    let makeBinding: (AIScenario) -> AIScenarioModelBinding
    /// 已存在的绑定数据（编辑模式传入，新增模式为nil）
    let existingBinding: AIScenarioModelBinding?
    /// 可关联的子任务列表
    var smallTasks: [SmallTask]
    var promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling()
    var promptTemplates: [PromptRepo] = []
    /// 取消操作回调
    let onCancel: () -> Void
    /// 保存操作回调
    let onSave: (AIScenarioModelBinding) -> Void

    // MARK: - 状态属性
    /// 当前选中的场景（仅新增模式使用）
    @State private var selectedScenario: AIScenario
    /// 表单编辑的草稿数据
    @State private var draft: AIScenarioModelBinding

    // MARK: - 初始化
    init(
        mode: ModelScenarioBindingEditorMode,
        availableScenarios: [AIScenario],
        makeBinding: @escaping (AIScenario) -> AIScenarioModelBinding,
        existingBinding: AIScenarioModelBinding?,
        smallTasks: [SmallTask],
        promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling(),
        promptTemplates: [PromptRepo] = [],
        onCancel: @escaping () -> Void,
        onSave: @escaping (AIScenarioModelBinding) -> Void
    ) {
        // 初始化草稿数据：编辑模式使用已有数据，新增模式创建新数据
        let initialBinding: AIScenarioModelBinding = {
            if let existingBinding {
                return existingBinding
            }
            // 无数据时默认选中第一个场景，无场景则使用聊天场景
            let initialScenario = availableScenarios.first ?? .chat
            return makeBinding(initialScenario)
        }()
        
        self.mode = mode
        self.availableScenarios = availableScenarios
        self.makeBinding = makeBinding
        self.existingBinding = existingBinding
        self.smallTasks = smallTasks
        self.promptTooling = promptTooling
        self.promptTemplates = promptTemplates
        self.onCancel = onCancel
        self.onSave = onSave
        
        // 初始化状态：从草稿数据中读取当前场景
        _selectedScenario = State(initialValue: AIScenario(rawValue: initialBinding.scenario) ?? .chat)
        _draft = State(initialValue: initialBinding)
    }

    // MARK: - 页面主体
    var body: some View {
        // 场景绑定表单视图
        ModelScenarioBindingForm(
            binding: $draft,
            smallTasks: smallTasks,
            promptTooling: promptTooling,
            promptTemplates: promptTemplates,
            scenarioPicker: scenarioPicker
        )
        // 导航栏标题
        .navigationTitle(title)
        // 工具栏：取消 + 保存/添加
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel", comment: "取消")) { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { onSave(draft) }
                    .disabled(isSaveDisabled)
            }
        }
        // 监听场景变化：新增模式下切换场景时重建绑定数据
        .onChange(of: selectedScenario, perform: { newScenario in
            guard case .add = mode else { return }
            let previousID = draft.id
            // 用新场景创建绑定数据，保留原有ID
            draft = makeBinding(newScenario)
            draft.id = previousID
        })
    }

    // MARK: - 子视图
    /// 场景选择器（仅新增模式显示）
    private var scenarioPicker: AnyView {
        guard case .add = mode else { return AnyView(EmptyView()) }
        return AnyView(
            Picker(L10n.text("ai_settings.models.online.field.scenarios", comment: "使用场景"), selection: $selectedScenario) {
                ForEach(availableScenarios, id: \.rawValue) { scenario in
                    Text(scenario.localizedTitle).tag(scenario)
                }
            }
        )
    }

    // MARK: - 计算属性
    /// 导航栏标题
    private var title: String {
        switch mode {
        case .add:
            return L10n.text("ai_settings.scenario_binding.nav.add_title", comment: "添加场景")
        case .edit:
            return AIScenario(rawValue: draft.scenario)?.localizedTitle ?? draft.scenario
        }
    }

    /// 确认按钮文字
    private var confirmTitle: String {
        switch mode {
        case .add:
            return L10n.text("common.add", comment: "添加")
        case .edit:
            return L10n.text("common.done", comment: "完成")
        }
    }

    /// 是否禁用保存按钮
    private var isSaveDisabled: Bool {
        switch mode {
        case .add:
            // 新增模式：无可用场景时禁用
            return availableScenarios.isEmpty
        case .edit:
            // 编辑模式：始终可用
            return false
        }
    }
}

/// 模型场景绑定表单
/// 统一用于配置模型与场景的绑定参数：开关、温度、最大 Token、系统提示、工具、关联任务等
private struct ModelScenarioBindingForm: View {
    // MARK: - 参数
    /// 双向绑定：场景配置模型
    @Binding var binding: AIScenarioModelBinding
    /// 可关联的小型任务列表
    var smallTasks: [SmallTask]
    var promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling()
    var promptTemplates: [PromptRepo] = []
    /// 场景选择器（外部传入，新增模式显示，编辑模式隐藏）
    var scenarioPicker: AnyView = AnyView(EmptyView())

    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false

    // MARK: - 表单主体
    var body: some View {
        Form {
            // MARK: 基础开关区（激活/默认场景）
            Section {
                // 场景选择器（仅添加时显示）
                scenarioPicker
                // 是否激活当前场景绑定
                Toggle(L10n.text("ai_settings.scenario_binding.active", comment: "启用"), isOn: $binding.isActive)
                // 是否设为默认场景
                Toggle(L10n.text("ai_settings.scenario_default_hint", comment: "默认"), isOn: $binding.isDefault)
            }

            // MARK: 模型参数调节区（温度/最大Token）
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.text("ai_settings.temperature", comment: "温度"))
                        Spacer()
                        Text(String(format: "%.2f", binding.temperature))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $binding.temperature, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.text("ai_settings.max_tokens", comment: "最大 Tokens"))
                        Spacer()
                        Text("\(binding.maxTokens)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(binding.maxTokens) },
                            set: { binding.maxTokens = Int($0) }
                        ),
                        in: 256...32768,
                        step: 256
                    )
                }
            }

            // MARK: 文本配置区（系统提示/描述）
            Section(L10n.text("ai_settings.scenario_binding.system_provision", comment: "系统指令")) {
                PromptInputEditorView(
                    text: $binding.systemProvision,
                    promptTemplates: promptTemplates,
                    onVoiceInput: { showVoiceInput = true },
                    onTextInput: { showTextInputDrawer = true }
                )
            }

            Section(L10n.text("common.description", comment: "描述")) {
                TextField(L10n.text("common.description", comment: "描述"), text: $binding.briefDescription)
            }

            // MARK: 工具选择区
            Section(L10n.text("common.tools", comment: "工具")) {
                // 跳转到工具多选页面
                MainNavigationLink {
                    GroupedToolSelectionView(
                        title: L10n.text("common.tools", comment: "工具"),
                        selectedValues: toolSelection
                    )
                } label: {
                    HStack {
                        Text(L10n.text("common.tools", comment: "工具"))
                        Spacer()
                        // 显示已选工具数量
                        Text(toolSelectionSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: 关联任务选择区（有任务时才显示）
            if smallTasks.isEmpty == false {
                Section(L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务")) {
                    // 跳转到关联任务多选页面
                    MainNavigationLink {
                        MultiSelectOptionsView(
                            title: L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务选择页标题"),
                            options: smallTasks.map { ($0.code, L10n.format("ai_settings.models.agent.related_tasks.option_format", fallback: "%@ (%@)", comment: "关联小任务选项格式", $0.name, $0.code)) },
                            selectedValues: relatedTaskSelection
                        )
                    } label: {
                        HStack {
                            Text(L10n.text("ai_settings.models.agent.related_tasks.title", fallback: "Related small tasks", comment: "关联小任务"))
                            Spacer()
                            // 显示已关联任务数量
                            Text("\(binding.relatedTaskCodes.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $binding.systemProvision,
                isPresented: $showTextInputDrawer,
                onTranslate: {
                    try await promptTooling.translate(text: binding.systemProvision)
                },
                onOCRImage: { image in
                    try await promptTooling.ocrImage(image)
                }
            )
            .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $binding.systemProvision,
                isPresented: $showVoiceInput
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }

    // MARK: - 工具选择双向绑定
    /// 工具选择的绑定（转换为 Set 供多选页面使用）
    private var toolSelection: Binding<Set<String>> {
        Binding(
            get: { SparkToolName.selectedSet(fromStoredToolNames: binding.aiToolScenarios) },
            set: { binding.aiToolScenarios = SparkToolName.storageValues(forSelectedToolNames: $0) }
        )
    }

    /// 关联任务选择的绑定（数组 ↔ Set 转换）
    private var relatedTaskSelection: Binding<Set<String>> {
        Binding(
            get: { Set(binding.relatedTaskCodes) },
            set: { binding.relatedTaskCodes = $0.sorted() }
        )
    }

    // MARK: - 工具选择摘要文本（已选/总数）
    /// 工具选择显示文案：全选 = 全部，否则 = 数量/总数
    private var toolSelectionSummary: String {
        let selected = SparkToolName.selectedSet(fromStoredToolNames: binding.aiToolScenarios)
        let total = SparkToolName.all.count
        if selected.count == total {
            return L10n.text("common.all", comment: "全部")
        }
        return "\(selected.count)/\(total)"
    }
}
