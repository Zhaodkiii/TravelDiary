import SwiftUI

/// 默认模型配置页：按场景统一展示，支持本地模型与 Pro 模型切换。
struct AIModelPreferencesView: View {
    @StateObject private var viewModel: ScenarioModelPreferencesViewModel
    @State private var searchText = ""

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredScenarios: [AIScenario] {
        AIScenario.allCases.filter { scenario in
            scenario.matchesLocalizedSearch(normalizedSearchText)
        }
    }

    init(viewModel: ScenarioModelPreferencesViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            if filteredScenarios.isEmpty {
                emptySearchState
            } else {
                ForEach(filteredScenarios, id: \.rawValue) { scenario in
                    scenarioSection(scenario)
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.default_model_config"))
        .searchable(text: $searchText, prompt: L10n.text("ai_settings.prefs.search_prompt", fallback: "Search scenarios", comment: "Scenario model preference search placeholder"))
        .task {
            await viewModel.reloadBundles()
        }
    }

    private var emptySearchState: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(L10n.text("ai_settings.prefs.empty_search", fallback: "No matching scenarios", comment: "Scenario model preference empty search title"))
                    .font(.headline)
                Text(L10n.text("ai_settings.prefs.empty_search_hint", fallback: "Try another keyword.", comment: "Scenario model preference empty search hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func scenarioSection(_ scenario: AIScenario) -> some View {
        let source = sourceBinding(for: scenario).wrappedValue
        let proBundle = viewModel.proBundles?.bundle(for: scenario)
        let hasProModels = (proBundle?.models.isEmpty == false)
        let activeBundle = bundle(for: scenario, source: source)

        Section(header: Text(scenario.localizedTitle)) {
            scenarioIntro(for: scenario)

            if hasProModels {
                Picker(L10n.text("ai_settings.prefs.source_config"), selection: sourceBinding(for: scenario)) {
                    Text(L10n.text("ai_settings.prefs.source_local_key")).tag(AIModelSelectionSource.localKey)
                    Text(L10n.text("ai_settings.prefs.source_trial")).tag(AIModelSelectionSource.trial)
                }
                .pickerStyle(.segmented)
            }

            if let activeBundle, activeBundle.models.isEmpty == false {
                let selected = modelSelectionBinding(for: scenario, sourceBundle: activeBundle)
                Picker(L10n.text("ai_settings.scenario_model_picker"), selection: selected) {
                    Text(L10n.text("ai_settings.prefs.model_unselected")).tag("")
                    ForEach(activeBundle.models, id: \.model) { row in
                        Text(bundleRowDisplayName(row)).tag(row.model)
                    }
                }

                if let picked = activeBundle.models.first(where: { $0.model == selected.wrappedValue }) {
                    modelSummaryRow(
                        company: companyLabelForBundleRow(picked),
                        displayName: bundleRowDisplayName(picked),
                        subtitle: picked.model
                    )
                }
            } else {
                Text(L10n.text("ai_settings.no_models_configure_key"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func bundle(for scenario: AIScenario, source: AIModelSelectionSource) -> AIScenarioRemoteBundle? {
        viewModel.bundle(for: scenario, source: source)
    }

    private func sourceBinding(for scenario: AIScenario) -> Binding<AIModelSelectionSource> {
        Binding(
            get: { viewModel.source(for: scenario) },
            set: { newValue in
                viewModel.setSource(newValue, for: scenario)
            }
        )
    }

    private func modelSelectionBinding(for scenario: AIScenario, sourceBundle: AIScenarioRemoteBundle) -> Binding<String> {
        Binding(
            get: { viewModel.selectedModel(for: scenario, sourceBundle: sourceBundle) },
            set: { newValue in
                viewModel.setSelectedModel(newValue, for: scenario)
            }
        )
    }

    private func bundleRowDisplayName(_ row: AIScenarioRemoteModelRow) -> String {
        row.displayName.isEmpty ? row.model : row.displayName
    }

    private func companyLabelForBundleRow(_ row: AIScenarioRemoteModelRow) -> String {
        if let company = row.providerCompany, company.isEmpty == false {
            return company
        }
        return ""
    }

    @ViewBuilder
    private func scenarioIntro(for scenario: AIScenario) -> some View {
        VStack(alignment: .center) {
            Image(systemName: scenario.introIconSystemName)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.blue)
                .padding(.top, 4)

            Text(scenario.localizedIntro)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func modelSummaryRow(company: String, displayName: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(companyIconName(for: company))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private struct AIModelPreferencesViewPreviewHost: View {
    var body: some View {
        CompatibleNavigationContainer {
            AIModelPreferencesView(viewModel: ScenarioModelPreferencesViewModel(aiConfigCenter: nil))
        }
    }
}

@MainActor
struct AIModelPreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.light)

            AIModelPreferencesViewPreviewHost()
                .preferredColorScheme(.dark)
        }
    }
}
