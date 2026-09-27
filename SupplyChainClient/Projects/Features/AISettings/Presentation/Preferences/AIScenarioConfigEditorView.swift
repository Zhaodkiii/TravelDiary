import SwiftUI

/// 各业务场景模型：以本地绑定表为准，默认模型与参数直接写入 binding。
struct AIScenarioConfigEditorView: View {
    @Binding var snapshot: AISettingsSnapshot

    private var localBundles: AIScenarioRemoteBundlesCollection {
        snapshot.localScenarioBundles()
    }

    var body: some View {
        Form {
            ForEach(AIScenario.allCases, id: \.rawValue) { scenario in
                scenarioSection(title: scenario.localizedTitle, scenario: scenario)
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.scenario"))
    }

    @ViewBuilder
    private func scenarioSection(title: String, scenario: AIScenario) -> some View {
        let bundle = localBundles.bundle(for: scenario)
        Section(title) {
            if bundle.models.count > 1 {
                Picker(L10n.text("ai_settings.scenario_model_picker"), selection: scenarioModelSelection(for: scenario)) {
                    ForEach(bundle.models, id: \.model) { row in
                        Text(scenarioModelLabel(row)).tag(row.model)
                    }
                }
            }

            if let row = snapshot.resolveScenarioRow(for: scenario) {
                readOnlyField(title: L10n.text("ai_settings.endpoint"), value: row.endpoint)
                readOnlyField(title: L10n.text("common.model"), value: row.model)
                if let key = row.apiKey, key.isEmpty == false {
                    readOnlyField(
                        title: L10n.text("ai_settings.api_key"),
                        value: String(repeating: "•", count: min(key.count, 8))
                    )
                }
                if let binding = bindingForSelectedRow(row, scenario: scenario) {
                    Stepper(
                        "\(L10n.text("ai_settings.temperature")) \(String(format: "%.2f", binding.temperature))",
                        value: bindingDoubleValue(bindingID: binding.id, keyPath: \.temperature),
                        in: 0...2,
                        step: 0.05
                    )
                    Stepper(
                        "\(L10n.text("ai_settings.max_tokens")) \(binding.maxTokens)",
                        value: bindingIntValue(bindingID: binding.id, keyPath: \.maxTokens),
                        in: 256...32768,
                        step: 256
                    )
                } else {
                    readOnlyField(title: L10n.text("ai_settings.temperature"), value: String(format: "%.2f", row.temperature))
                    readOnlyField(title: L10n.text("ai_settings.max_tokens"), value: "\(row.maxTokens)")
                }
            } else {
                Text(L10n.text("ai_settings.scenario_model_picker"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func readOnlyField(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func scenarioModelLabel(_ row: AIScenarioRemoteModelRow) -> String {
        let suffix = row.isDefault ? " (\(L10n.text("ai_settings.scenario_default_hint")))" : ""
        return row.model + suffix
    }

    private func scenarioModelSelection(for scenario: AIScenario) -> Binding<String> {
        Binding(
            get: {
                snapshot.scenarioDefaultModelName(for: scenario)
                    ?? snapshot.resolveScenarioRow(for: scenario)?.model
                    ?? ""
            },
            set: { newValue in
                var next = snapshot
                next.setScenarioDefaultModelName(newValue, for: scenario)
                snapshot = next
            }
        )
    }

    private func bindingForSelectedRow(_ row: AIScenarioRemoteModelRow, scenario: AIScenario) -> AIScenarioModelBinding? {
        guard let model = snapshot.allModels.first(where: { $0.name == row.name }) else { return nil }
        return snapshot.scenarioBindings.first {
            $0.scenario == scenario.rawValue && $0.modelID == model.id && $0.isActive
        }
    }

    private func bindingDoubleValue(
        bindingID: UUID,
        keyPath: WritableKeyPath<AIScenarioModelBinding, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                snapshot.scenarioBindings.first(where: { $0.id == bindingID })?[keyPath: keyPath] ?? 0.2
            },
            set: { newValue in
                guard let index = snapshot.scenarioBindings.firstIndex(where: { $0.id == bindingID }) else { return }
                snapshot.scenarioBindings[index][keyPath: keyPath] = newValue
                snapshot.scenarioBindings[index].updatedAt = Date()
            }
        )
    }

    private func bindingIntValue(
        bindingID: UUID,
        keyPath: WritableKeyPath<AIScenarioModelBinding, Int>
    ) -> Binding<Int> {
        Binding(
            get: {
                snapshot.scenarioBindings.first(where: { $0.id == bindingID })?[keyPath: keyPath] ?? 2048
            },
            set: { newValue in
                guard let index = snapshot.scenarioBindings.firstIndex(where: { $0.id == bindingID }) else { return }
                snapshot.scenarioBindings[index][keyPath: keyPath] = newValue
                snapshot.scenarioBindings[index].updatedAt = Date()
            }
        )
    }
}

@MainActor
private struct AIScenarioConfigEditorViewPreviewHost: View {
    @State private var snapshot = AISettingsSnapshot.default

    var body: some View {
        CompatibleNavigationContainer {
            AIScenarioConfigEditorView(snapshot: $snapshot)
        }
    }
}

@MainActor
struct AIScenarioConfigEditorView_Previews: PreviewProvider {
    static var previews: some View {
        AIScenarioConfigEditorViewPreviewHost()
    }
}
