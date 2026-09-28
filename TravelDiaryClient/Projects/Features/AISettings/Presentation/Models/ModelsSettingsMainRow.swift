import SwiftUI

/// 与 Health `ModelRowView` 对齐的主列表行：图标、标题、能力/价格胶囊、info、显隐 Toggle、侧滑编辑/删除。
struct ModelsSettingsMainRow: View {
    let model: AllModels
    let viewModel: AISettingsViewModel
    let isEditing: Bool
    let priceLabel: String
    let priceColor: Color
    let onDelete: () -> Void
    var trailingAccessory: AnyView? = nil
    var showsInfoButton: Bool = true
    var showsVisibilityToggle: Bool = true
    var showsLeadingSwipeAction: Bool = true
    var showsTrailingSwipeAction: Bool = true
    @State private var showEditSheet = false
    @State private var showAgentEditSheet = false
    @State private var showToggleKeyError = false

    private var resolvedDisplayName: String {
        let trimmed = model.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? model.name : trimmed
    }

    private var isLocal: Bool {
        AIProviderAdapterRegistry.adapter(for: model.providerID).isLocal
    }

    private var isAgent: Bool {
        model.identity == .agent
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            rowLeadingIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName.isEmpty ? model.name : model.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    if isLocal {
                        Text(L10n.text("ai_settings.models.badge.local"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isAgent, let base = model.baseModelName, base.isEmpty == false {
                        Text(L10n.format("ai_settings.models.row.based_on_format", base))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if model.supportsToolUse {
                        Text(L10n.text("common.tools"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsMultimodal {
                        Text(L10n.text("ai_settings.models.capability.visual_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.supportsText {
                        Text(L10n.text("ai_settings.field.supports_text"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsImageGen {
                        Text(L10n.text("ai_settings.models.capability.image_gen_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsVoiceGen {
                        Text(L10n.text("ai_settings.models.capability.voice_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsReasoning {
                        Text(L10n.text("ai_settings.models.capability.reasoning_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(priceLabel)
                        .font(.caption)
                        .foregroundStyle(priceColor)
                }
            }

            Spacer(minLength: 4)

            if let trailingAccessory {
                trailingAccessory
            } else if isEditing == false {
                if showsInfoButton {
                    Button(action: openEditor) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if showsVisibilityToggle {
                    Toggle("", isOn: Binding(
                        get: { model.isHidden == false },
                        set: { newValue in
                            if newValue {
                                if viewModel.hasValidAPIKey(for: model) {
                                    Task { _ = await viewModel.setModelVisibilityAndPersist(modelID: model.id, visible: true) }
                                } else {
                                    showToggleKeyError = true
                                }
                            } else {
                                Task { _ = await viewModel.setModelVisibilityAndPersist(modelID: model.id, visible: false) }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if showsTrailingSwipeAction {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(L10n.text("ai_settings.models.action.delete"), systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if showsLeadingSwipeAction {
                Button(action: openEditor) {
                    Label(L10n.text("common.edit"), systemImage: "square.and.pencil")
                }
                .tint(.blue)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditSparkModelSheet(viewModel: viewModel, modelID: model.id)
        }
        .sheet(isPresented: $showAgentEditSheet) {
            CompatibleNavigationContainer {
                ModelsSettingsAgentSheet(
                    baseModels: viewModel.snapshot.allModels.filter { $0.identity == .model && $0.isHidden == false },
                    editingAgent: model,
                    scenarioBindings: viewModel.snapshot.scenarioBindings,
                    smallTasks: viewModel.effectiveSmallTasks,
                    promptTooling: viewModel.promptTooling,
                    promptTemplates: viewModel.snapshot.promptRepo,
                    onCreate: { _, _, _, _, _, _, _, _ in },
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
                        Task {
                            await viewModel.persistScenarioBindingChange(change)
                        }
                    }
                )
            }
        }
        .alert(L10n.text("ai_settings.models.alert.need_api_key_title"), isPresented: $showToggleKeyError) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(L10n.text("ai_settings.models.alert.need_api_key_message"))
        }
    }

    @ViewBuilder
    private var rowLeadingIcon: some View {
        if isAgent, let sym = model.iconSymbol, sym.isEmpty == false {
            Image(systemName: sym)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        } else {
            Image(companyIconName(for: model.company))
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
        }
    }

    private func openEditor() {
        if isAgent {
            showAgentEditSheet = true
        } else {
            showEditSheet = true
        }
    }
}

enum ModelsSettingsRowChrome {
    static func priceTierLabel(_ tier: Int) -> String {
        switch min(max(tier, 0), 3) {
        case 0: return L10n.text("ai_settings.field.price_tier.free")
        case 1: return L10n.text("ai_settings.field.price_tier.economy")
        case 2: return L10n.text("ai_settings.field.price_tier.standard")
        default: return L10n.text("ai_settings.field.price_tier.premium")
        }
    }

    static func priceTierColor(_ tier: Int) -> Color {
        switch min(max(tier, 0), 3) {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
