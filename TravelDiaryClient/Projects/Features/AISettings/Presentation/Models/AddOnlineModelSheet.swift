import SwiftUI

struct AddOnlineModelDraft: Sendable {
    var name: String
    var displayName: String
    var providerID: String
    var company: String
    var priceTier: Int
    var isHidden: Bool
    var supportsText: Bool
    var supportsMultimodal: Bool
    var supportsReasoning: Bool
    var reasoningControllable: Bool
    var supportsToolUse: Bool
    var supportsImageGen: Bool
    var aiScenarios: [String]
    var aiToolScenarios: [String]
}

/// 对齐 Health `AddOnlineModelView`：表单添加云端模型（无 SwiftData）。
struct AddOnlineModelSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let initialCompany: String?
    let initialDraft: AddOnlineModelDraft?

    @State private var name = ""
    @State private var displayName = ""
    @State private var priceTier = 0
    @State private var isHidden = false
    @State private var supportsText = true
    @State private var supportsMultimodal = false
    @State private var supportsReasoning = false
    @State private var reasoningControllable = false
    @State private var supportsToolUse = false
    @State private var supportsImageGen = false
    @State private var selectedProviderID = ""
    @State private var draftModelID = UUID()
    @State private var draftScenarioBindings: [AIScenarioModelBinding] = []
    @State private var selectedToolNames: Set<String> = Set(SparkToolName.all)
    @State private var hasAppliedInitialDraft = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showProbeSheet = false
    @State private var probeItems: [ModelCapabilityProbeProgressItem] = ModelCapabilityProbeStep.allCases.map {
        ModelCapabilityProbeProgressItem(step: $0, status: .pending, message: nil)
    }
    @State private var isProbing = false

    private let probeService = ClientModelCapabilityProbeService()

    init(
        viewModel: AISettingsViewModel,
        initialCompany: String? = nil,
        initialDraft: AddOnlineModelDraft? = nil
    ) {
        self.viewModel = viewModel
        self.initialCompany = initialCompany
        self.initialDraft = initialDraft
    }

    private var apiKeyRows: [APIKeys] {
        viewModel.snapshot.apiKeys.filter {
            AIProviderAdapterRegistry.adapter(for: $0.providerID).isLocal == false
        }
    }

    private var selectedProviderDisplayName: String {
        guard let provider = selectedProviderForProbe else {
            return L10n.text("ai_settings.models.online.field.vendor", comment: "厂商")
        }
        return provider.localizedDisplayName
    }

    private var normalizedInitialProviderID: String? {
        guard let initialCompany else { return nil }
        return AIProviderIdentifier.normalize(initialCompany)
    }

    private var isInitialCompanyAvailable: Bool {
        guard let normalizedInitialProviderID else { return false }
        return apiKeyRows.contains {
            $0.providerID == normalizedInitialProviderID
        }
    }

    private var isCompanyLocked: Bool {
        isInitialCompanyAvailable
    }

    var body: some View {
        CompatibleNavigationContainer {
            Form {

                Section(L10n.text("ai_settings.models.online.section.basic", comment: "基本信息")) {
                    formInputRow(
                        icon: "rectangle.and.text.magnifyingglass", //  API 名称 / 标识 图标
                        title: L10n.text("ai_settings.models.online.field.api_name", comment: "API 模型名"),
                        prompt: L10n.text("ai_settings.models.online.field.api_name_prompt", comment: "API 模型名占位提示"),
                        text: $name
                    )
                    formInputRow(
                        icon: "textformat", // 显示名称 / 标题 图标
                        title: L10n.text("ai_settings.models.online.field.display_name", comment: "显示名称"),
                        prompt: L10n.text("ai_settings.models.online.field.display_name_prompt", comment: "显示名称占位提示"),
                        text: $displayName
                    )
                    formMenuRow(icon: "building.2", title: L10n.text("ai_settings.models.online.field.vendor", comment: "厂商")) {
                        Picker("", selection: $selectedProviderID) {
                            ForEach(apiKeyRows, id: \.id) { key in
                                Text(key.localizedDisplayName)
                                    .tag(key.providerID)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(isCompanyLocked)
                    } label: {
                        Text(selectedProviderDisplayName)
                            .foregroundStyle(selectedProviderForProbe == nil ? .secondary : .primary)
                    }
                }
                Section(L10n.text("ai_settings.models.online.section.price", comment: "价格")) {
                    formMenuRow(icon: "yensign", title: L10n.text("ai_settings.field.price_tier", comment: "价格档位")) {
                        Picker("", selection: $priceTier) {
                            Text(L10n.text("ai_settings.field.price_tier.free", comment: "免费")).tag(0)
                            Text(L10n.text("ai_settings.field.price_tier.economy", comment: "经济")).tag(1)
                            Text(L10n.text("ai_settings.field.price_tier.standard", comment: "标准")).tag(2)
                            Text(L10n.text("ai_settings.field.price_tier.premium", comment: "高级")).tag(3)
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label(
                            ModelsSettingsRowChrome.priceTierLabel(priceTier),
                            systemImage: "circle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(ModelsSettingsRowChrome.priceTierColor(priceTier))
                    }
                }
//                Section(L10n.text("ai_settings.models.online.section.usage", comment: "使用场景与工具")) {
//                    NavigationLink {
//                        ModelScenarioBindingsEditorView(
//                            scenarioBindings: $draftScenarioBindings,
//                            modelID: draftModelID,
//                            identity: .model,
//                            defaultToolScenarios: SparkToolName.storageValues(forSelectedToolNames: selectedToolNames),
//                            smallTasks: viewModel.snapshot.smallTasks
//                        )
//                    } label: {
//                        HStack {
//                            Text(L10n.text("ai_settings.models.online.field.scenarios", comment: "使用场景"))
//                            Spacer()
//                            Text("\(draftScenarioBindings.filter { $0.modelID == draftModelID }.count)")
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//
//                    NavigationLink {
//                        GroupedToolSelectionView(
//                            title: L10n.text("common.tools", comment: "工具"),
//                            selectedValues: $selectedToolNames
//                        )
//                    } label: {
//                        HStack {
//                            Text(L10n.text("common.tools", comment: "工具"))
//                            Spacer()
//                            Text(selectedToolsSummary)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                }
                Section(L10n.text("ai_settings.models.online.section.capabilities", comment: "能力")) {
                    formToggleRow(
                        icon: "eye.slash",
                        title: L10n.text("ai_settings.models.online.toggle.default_hidden", comment: "默认隐藏"),
                        isOn: $isHidden
                    )
                    probeActionRow
                    Text(L10n.text("ai_settings.models.online.probe.cost_note", comment: "能力探测费用提示"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    formToggleRow(
                        icon: "character",
                        title: L10n.text("ai_settings.models.online.toggle.supports_text", comment: "支持文本"),
                        isOn: $supportsText
                    )
                    formToggleRow(
                        icon: "photo.on.rectangle.angled",
                        title: L10n.text("ai_settings.field.supports_multimodal", comment: "支持多模态"),
                        isOn: $supportsMultimodal
                    )
                    formToggleRow(
                        icon: "atom",
                        title: L10n.text("ai_settings.field.supports_reasoning", comment: "支持推理"),
                        isOn: $supportsReasoning
                    )
                    formToggleRow(
                        icon: "lightbulb",
                        title: L10n.text("ai_settings.field.reasoning_controllable", comment: "思考可控"),
                        isOn: $reasoningControllable
                    )
                    formToggleRow(
                        icon: "hammer",
                        title: L10n.text("ai_settings.field.supports_tool_use", comment: "支持工具调用"),
                        isOn: $supportsToolUse
                    )
                    formToggleRow(
                        icon: "camera.aperture",
                        title: L10n.text("ai_settings.models.online.toggle.image_gen", comment: "生图"),
                        isOn: $supportsImageGen
                    )

                    Text(L10n.text("ai_settings.models.online.capabilities.footer", comment: "能力区底部说明"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.accentColor)
            .navigationTitle(L10n.text("ai_settings.models.online.nav_title", comment: "添加在线模型"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", comment: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("ai_settings.models.online.save", comment: "添加")) { save() }
                }
            }
            .alert(L10n.text("ai_settings.models.online.error_title", comment: "无法添加"), isPresented: $showAlert) {
                Button(L10n.text("common.ok", comment: "确定"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showProbeSheet) {
                ModelCapabilityProbeSheet(items: probeItems)
            }
            .onAppear {
                applyInitialDraftIfNeeded()
                if let normalizedInitialProviderID,
                   let initialProvider = apiKeyRows.first(where: {
                       $0.providerID == normalizedInitialProviderID
                   })
                {
                    selectedProviderID = initialProvider.providerID
                }
                if selectedProviderID.isEmpty, let first = apiKeyRows.first {
                    selectedProviderID = first.providerID
                }
            }
        }
    }

    private var probeActionRow: some View {
        Button {
            Task { await startProbe() }
        } label: {
            HStack(spacing: 12) {
                rowIcon("wand.and.stars")
                Text(L10n.text("ai_settings.models.online.probe.button", comment: "自动模型能力探测"))
                    .foregroundStyle(.primary)
                Spacer()
                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isProbing || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProviderForProbe == nil)
    }

    private func formInputRow(
        icon: String? = nil,
        title: String,
        prompt: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            if let icon {
                rowIcon(icon)
            }
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .accessibilityLabel(title)
    }

    private func formToggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Toggle(title, isOn: isOn)
        }
    }

    private func formMenuRow<Control: View, LabelView: View>(
        icon: String,
        title: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder label: () -> LabelView
    ) -> some View {
        HStack(spacing: 12) {
            rowIcon(icon)
            Text(title)
            Spacer(minLength: 12)
            
            control()
//            Menu {
//                control()
//            } label: {
//                HStack(spacing: 6) {
//                    label()
//                    Image(systemName: "chevron.up.chevron.down")
//                        .font(.caption2)
//                        .foregroundStyle(.tertiary)
//                }
//            }
        }
    }

    private func rowIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .foregroundStyle(.tint)
            .frame(width: 20)
    }

    private var selectedProviderForProbe: APIKeys? {
        let providerID = AIProviderIdentifier.normalize(selectedProviderID)
        return viewModel.snapshot.apiKeys.first(where: {
            $0.providerID == providerID
        })
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("common.all", comment: "全部")
        }
        return "\(selectedToolNames.count)/\(total)"
    }

    private func applyInitialDraftIfNeeded() {
        guard hasAppliedInitialDraft == false, let initialDraft else { return }
        hasAppliedInitialDraft = true
        name = initialDraft.name
        displayName = initialDraft.displayName
        selectedProviderID = initialDraft.providerID
        priceTier = min(max(initialDraft.priceTier, 0), 3)
        isHidden = initialDraft.isHidden
        supportsText = initialDraft.supportsText
        supportsMultimodal = initialDraft.supportsMultimodal
        supportsReasoning = initialDraft.supportsReasoning
        reasoningControllable = initialDraft.reasoningControllable
        supportsToolUse = initialDraft.supportsToolUse
        supportsImageGen = initialDraft.supportsImageGen
        draftScenarioBindings = initialDraft.aiScenarios.enumerated().compactMap { index, scenarioRaw in
            guard let scenario = AIScenario(rawValue: scenarioRaw) else { return nil }
            return AIScenarioModelBinding(
                scenario: scenario.rawValue,
                identity: .model,
                modelID: draftModelID,
                temperature: AIScenarioModelBinding.defaultTemperature,
                maxTokens: AIScenarioModelBinding.defaultMaxTokens,
                position: index,
                isDefault: true,
                aiToolScenarios: initialDraft.aiToolScenarios
            )
        }
        selectedToolNames = SparkToolName.selectedSet(fromStoredToolNames: initialDraft.aiToolScenarios)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = AIProviderIdentifier.normalize(selectedProviderID)
        let provider = selectedProviderForProbe
        let company = provider?.company.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !n.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.api_name", comment: "请填写 API 模型名")
            showAlert = true
            return
        }
        guard !d.isEmpty else {
            alertMessage = L10n.text("ai_settings.models.online.err.display_name", comment: "请填写显示名称")
            showAlert = true
            return
        }
        guard !providerID.isEmpty, let provider else {
            alertMessage = L10n.text("ai_settings.models.online.err.vendor", comment: "请选择已配置密钥的厂商")
            showAlert = true
            return
        }
        Task {
            let didSave = await viewModel.appendOnlineModelAndPersist(
                name: n,
                displayName: d,
                providerID: provider.providerID,
                company: company,
                priceTier: priceTier,
                isHidden: isHidden,
                supportsText: supportsText,
                supportsMultimodal: supportsMultimodal,
                supportsReasoning: supportsReasoning,
                reasoningControllable: reasoningControllable,
                supportsToolUse: supportsToolUse,
                supportsImageGen: supportsImageGen,
                aiScenarios: draftScenarioBindings.map(\.scenario).sorted(),
                aiToolScenarios: SparkToolName.storageValues(forSelectedToolNames: selectedToolNames),
                modelID: draftModelID,
                scenarioBindings: draftScenarioBindings
            )
            if didSave {
                await MainActor.run { dismiss() }
            }
        }
    }

    private func startProbe() async {
        guard let provider = selectedProviderForProbe else {
            alertMessage = L10n.text("ai_settings.models.online.err.vendor", comment: "请选择已配置密钥的厂商")
            showAlert = true
            return
        }
        let modelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelName.isEmpty == false else {
            alertMessage = L10n.text("ai_settings.models.online.err.api_name", comment: "请填写 API 模型名")
            showAlert = true
            return
        }

        probeItems = ModelCapabilityProbeStep.allCases.map {
            ModelCapabilityProbeProgressItem(step: $0, status: .pending, message: nil)
        }
        isProbing = true
        showProbeSheet = true
        do {
            let summary = try await probeService.probe(
                modelName: modelName,
                provider: provider
            ) { step, status, message in
                await MainActor.run {
                    guard let idx = probeItems.firstIndex(where: { $0.step == step }) else { return }
                    probeItems[idx].status = status
                    probeItems[idx].message = message
                }
            }
            supportsText = summary.supportsText
            supportsMultimodal = summary.supportsMultimodal
            supportsReasoning = summary.supportsReasoning
            reasoningControllable = summary.reasoningControllable
            supportsToolUse = summary.supportsToolUse
            supportsImageGen = summary.supportsImageGen
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        isProbing = false
    }
}

struct MultiSelectOptionsView: View {
    let title: String
    let options: [(value: String, title: String)]
    @Binding var selectedValues: Set<String>

    var body: some View {
        List {
            ForEach(options, id: \.value) { option in
                Button {
                    if selectedValues.contains(option.value) {
                        selectedValues.remove(option.value)
                    } else {
                        selectedValues.insert(option.value)
                    }
                } label: {
                    HStack {
                        Text(option.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedValues.contains(option.value) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GroupedToolSelectionView: View {
    let title: String
    @Binding var selectedValues: Set<String>

    var body: some View {
        List {
            ForEach(SparkToolGroup.allCases, id: \.self) { group in
                Section {
                    Toggle(isOn: groupBinding(group)) {
                        Label(group.localizedTitle, systemImage: group.iconSystemName)
                    }

                    if isGroupEnabled(group) {
                        ForEach(group.tools, id: \.rawValue) { tool in
                            Button {
                                toggleTool(tool)
                            } label: {
                                HStack {
                                    Text(SparkToolName.displayName(for: tool.rawValue))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedValues.contains(tool.rawValue) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(group.localizedTitle)
                        Spacer()
                        Text(groupSummary(group))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(group.localizedDescription)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func groupBinding(_ group: SparkToolGroup) -> Binding<Bool> {
        Binding(
            get: {
                isGroupEnabled(group)
            },
            set: { isOn in
                if isOn {
                    selectedValues.formUnion(group.toolRawValues)
                } else {
                    selectedValues.subtract(group.toolRawValues)
                }
            }
        )
    }

    private func isGroupEnabled(_ group: SparkToolGroup) -> Bool {
        selectedValues.isDisjoint(with: group.toolRawValues) == false
    }

    private func toggleTool(_ tool: SparkToolName) {
        if selectedValues.contains(tool.rawValue) {
            selectedValues.remove(tool.rawValue)
        } else {
            selectedValues.insert(tool.rawValue)
        }
    }

    private func groupSummary(_ group: SparkToolGroup) -> String {
        let selectedCount = group.toolRawValues.filter { selectedValues.contains($0) }.count
        let total = group.tools.count
        if selectedCount == 0 {
            return L10n.text("ai_settings.models.online.selection.none", comment: "未设置")
        }
        if selectedCount == total {
            return L10n.text("common.all", comment: "全部")
        }
        return "\(selectedCount)/\(total)"
    }
}

private struct ModelCapabilityProbeSheet: View {
    let items: [ModelCapabilityProbeProgressItem]

    var body: some View {
        CompatibleNavigationContainer {
            List(items) { item in
                HStack(spacing: 12) {
                    icon(for: item.status)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text(item.step.titleKey, comment: "能力探测步骤标题"))
                        if let message = item.message, message.isEmpty == false {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle(L10n.text("ai_settings.models.online.probe.sheet_title", comment: "能力探测结果"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func icon(for status: ModelCapabilityProbeStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}
