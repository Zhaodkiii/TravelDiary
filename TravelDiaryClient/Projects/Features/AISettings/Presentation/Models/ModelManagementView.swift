import SwiftUI

private enum ModelManagementSheet: Identifiable {
    case manualAdd(draft: AddOnlineModelDraft?)

    var id: String {
        switch self {
        case .manualAdd(let draft):
            return "manualAdd:\(draft?.name ?? "empty")"
        }
    }
}

struct ModelManagementView: View {
    let provider: APIKeys
    @ObservedObject var viewModel: AISettingsViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var remoteModels: [ProviderRemoteModel] = []
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var presentedSheet: ModelManagementSheet?

    private var companyModels: [AllModels] {
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model }
            .filter { $0.providerID == provider.providerID }
            .sorted { $0.position < $1.position }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredCompanyModels: [AllModels] {
        guard normalizedSearchText.isEmpty == false else { return companyModels }
        return companyModels.filter { model in
            let values = [
                model.displayName,
                model.name,
                model.briefDescription,
            ]
            return values.contains {
                $0.lowercased().contains(normalizedSearchText)
            }
        }
    }

    private var filteredRemoteModels: [ProviderRemoteModel] {
        guard normalizedSearchText.isEmpty == false else { return remoteModels }
        return remoteModels.filter { model in
            [model.displayName, model.name, model.ownedBy].contains {
                $0.lowercased().contains(normalizedSearchText)
            }
        }
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                providerStatusSection
                addedModelsSection
                availableModelsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.format("ai_settings.models.management.nav_title", provider.displayName))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: L10n.text("ai_settings.models.management.search_prompt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("ai_settings.models.management.action.close")) { dismiss() }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button {
                        presentedSheet = .manualAdd(draft: nil)
                    } label: {
                        Image(systemName: "plus")
                    }

                    Button {
                        Task { await refreshModels() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing || provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .refreshable {
                await refreshModels()
            }
            .task {
                if remoteModels.isEmpty {
                    await refreshModels()
                }
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .manualAdd(let draft):
                AddOnlineModelSheet(
                    viewModel: viewModel,
                    initialCompany: provider.providerID,
                    initialDraft: draft
                )
            }
        }
        .alert(L10n.text("ai_settings.models.management.alert_title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { presented in
                if presented == false {
                    errorMessage = nil
                }
            }
        )) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var providerStatusSection: some View {
        Section(L10n.text("ai_settings.models.management.section.auto_refresh")) {
            if provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.text("ai_settings.models.management.auto_refresh.empty_key"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.text("ai_settings.models.management.auto_refresh.enabled"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var addedModelsSection: some View {
        Section {
            if filteredCompanyModels.isEmpty {
                Text(
                    normalizedSearchText.isEmpty
                    ? L10n.text("ai_settings.models.management.added.empty")
                    : L10n.text("ai_settings.models.management.added.empty_search")
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(filteredCompanyModels.enumerated()), id: \.element.id) { _, model in
                    ModelsSettingsMainRow(
                        model: model,
                        viewModel: viewModel,
                        isEditing: false,
                        priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                        priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                        onDelete: { deleteModel(model) },
                        showsInfoButton: false,
                        showsLeadingSwipeAction: true
                    )
                }
            }
        } header: {
            Text(L10n.format("ai_settings.models.management.section.added", filteredCompanyModels.count))
        }
    }

    @ViewBuilder
    private var availableModelsSection: some View {
        Section {
            if provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyView()
            } else if isRefreshing && remoteModels.isEmpty {
                HStack {
                    Spacer()
                    ProgressView(L10n.text("ai_settings.models.management.loading"))
                    Spacer()
                }
            } else if filteredRemoteModels.isEmpty {
                Text(
                    normalizedSearchText.isEmpty
                    ? L10n.text("ai_settings.models.management.remote.empty")
                    : L10n.text("ai_settings.models.management.remote.empty_search")
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredRemoteModels) { model in
                    ModelsSettingsMainRow(
                        model: remoteCardModel(for: model),
                        viewModel: viewModel,
                        isEditing: false,
                        priceLabel: ModelsSettingsRowChrome.priceTierLabel(remotePriceTier(for: model)),
                        priceColor: ModelsSettingsRowChrome.priceTierColor(remotePriceTier(for: model)),
                        onDelete: {},
                        trailingAccessory: AnyView(remoteTrailingAccessory(for: model)),
                        showsInfoButton: false,
                        showsVisibilityToggle: false,
                        showsLeadingSwipeAction: false,
                        showsTrailingSwipeAction: false
                    )
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text(L10n.format("ai_settings.models.management.section.remote", filteredRemoteModels.count))
        } footer: {
            Text(L10n.text("ai_settings.models.management.remote.footer"))
        }
    }

    private func refreshModels() async {
        guard provider.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            remoteModels = try await viewModel.fetchRemoteModels(for: provider)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isModelAdded(_ remoteModel: ProviderRemoteModel) -> Bool {
        let remoteName = normalizedModelName(remoteModel.name)
        return companyModels.contains {
            normalizedModelName($0.name) == remoteName
        }
    }

    private func addModel(_ remoteModel: ProviderRemoteModel) {
        presentedSheet = .manualAdd(
            draft: AddOnlineModelDraft(
                name: remoteModel.name,
                displayName: remoteModel.displayName,
                providerID: provider.providerID,
                company: provider.company,
                priceTier: remotePriceTier(for: remoteModel),
                isHidden: false,
                supportsText: remoteModel.supportsText,
                supportsMultimodal: remoteModel.supportsMultimodal,
                supportsReasoning: remoteModel.supportsReasoning,
                reasoningControllable: remoteModel.supportsReasoning,
                supportsToolUse: remoteModel.supportsToolUse,
                supportsImageGen: remoteModel.supportsImageGen,
                aiScenarios: [],
                aiToolScenarios: SparkToolName.all
            )
        )
    }

    private func deleteModel(_ model: AllModels) {
        Task {
            let ok = await viewModel.deleteModelAndPersist(id: model.id)
            if ok == false {
                errorMessage = viewModel.errorMessage
            }
        }
    }

    private func remoteCardModel(for remoteModel: ProviderRemoteModel) -> AllModels {
        AllModels(
            name: remoteModel.name,
            displayName: remoteModel.displayName,
            identity: .model,
            position: 0,
            providerID: provider.providerID,
            company: provider.company,
            price: remotePriceTier(for: remoteModel),
            isEnabled: true,
            supportsSearch: true,
            supportsTextGen: remoteModel.supportsText,
            supportsMultimodal: remoteModel.supportsMultimodal,
            supportsReasoning: remoteModel.supportsReasoning,
            supportReasoningChange: remoteModel.supportsReasoning,
            supportsImageGen: remoteModel.supportsImageGen,
            supportsVoiceGen: false,
            supportsToolUse: remoteModel.supportsToolUse,
            briefDescription: remoteModel.ownedBy,
            source: .custom
        )
    }

    @ViewBuilder
    private func remoteTrailingAccessory(for remoteModel: ProviderRemoteModel) -> some View {
        if isModelAdded(remoteModel) {
            Label(L10n.text("ai_settings.models.management.remote.added"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            // 可添加状态
            Button {
                addModel(remoteModel)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text(L10n.text("ai_settings.models.management.action.add"))
                }
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func remotePriceTier(for remoteModel: ProviderRemoteModel) -> Int {
        let name = remoteModel.name.lowercased()
        if remoteModel.supportsImageGen {
            return 3
        }
        if name.contains("nano") || name.contains("mini") || name.contains("flash") || name.contains("lite") {
            return 1
        }
        if name.contains("reasoner") || name.contains("max") || name.contains("opus") || name.contains("pro") {
            return 3
        }
        return 2
    }

    private func normalizedModelName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "models/", with: "")
            .lowercased()
    }
}
