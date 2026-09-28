import SwiftUI

/// Health 页中「全部模型（高级）」独立子页：DisclosureGroup 编辑全部字段。
struct ModelsAdvancedEditorView: View {
    @Binding var models: [AllModels]
    @Binding var selectedIdentity: ModelsSettingsIdentityFilter
    @Binding var searchText: String

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredIDs: [UUID] {
        models
            .filter(matchesIdentity)
            .filter(matchesSearch)
            .sorted { $0.position < $1.position }
            .map(\.id)
    }

    var body: some View {
        List {
            Section {
                if filteredIDs.isEmpty {
                    Text(L10n.text("ai_settings.models.empty.advanced_no_match"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredIDs, id: \.self) { id in
                        if let binding = bindingForModel(id: id) {
                            DisclosureGroup {
                                TextField(L10n.text("ai_settings.field.display_name"), text: binding.displayName)
                                TextField(L10n.text("common.model"), text: binding.name)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                TextField(L10n.text("ai_settings.field.company"), text: binding.company)
                                Picker(L10n.text("ai_settings.field.identity"), selection: binding.identity) {
                                    ForEach(AIModelIdentity.allCases, id: \.self) { identity in
                                        Text(identitySparkLabel(identity)).tag(identity)
                                    }
                                }
                                Toggle(L10n.text("ai_settings.field.visible"), isOn: Binding(
                                    get: { binding.wrappedValue.isHidden == false },
                                    set: { binding.wrappedValue.isHidden = !$0 }
                                ))
                                Toggle(L10n.text("ai_settings.field.supports_search"), isOn: binding.supportsSearch)
                                Toggle(L10n.text("ai_settings.field.supports_multimodal"), isOn: binding.supportsMultimodal)
                                Toggle(L10n.text("ai_settings.field.supports_reasoning"), isOn: binding.supportsReasoning)
                                Toggle(L10n.text("ai_settings.field.reasoning_controllable"), isOn: binding.reasoningControllable)
                                Picker(L10n.text("ai_settings.field.price_tier"), selection: binding.priceTier) {
                                    Text(L10n.text("ai_settings.field.price_tier.free")).tag(0)
                                    Text(L10n.text("ai_settings.field.price_tier.economy")).tag(1)
                                    Text(L10n.text("ai_settings.field.price_tier.standard")).tag(2)
                                    Text(L10n.text("ai_settings.field.price_tier.premium")).tag(3)
                                }
                                Toggle(L10n.text("ai_settings.field.supports_text"), isOn: binding.supportsText)
                                Toggle(L10n.text("ai_settings.field.supports_tool_use"), isOn: binding.supportsToolUse)
                            } label: {
                                Text(binding.wrappedValue.displayName.isEmpty ? L10n.text("ai_settings.model_item") : binding.wrappedValue.displayName)
                            }
                        }
                    }
                    .onDelete(perform: deleteAt)
                    .onMove(perform: move)
                }
            } header: {
                Text(L10n.text("ai_settings.models.section.advanced_all"))
            }
        }
        .navigationTitle(L10n.text("ai_settings.models.advanced.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func identitySparkLabel(_ identity: AIModelIdentity) -> String {
        switch identity {
        case .model:
            return L10n.text("common.model")
        case .agent:
            return L10n.text("ai_settings.identity.agent")
        }
    }

    private func bindingForModel(id: UUID) -> Binding<AllModels>? {
        guard let index = models.firstIndex(where: { $0.id == id }) else { return nil }
        return $models[index]
    }

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

    private func matchesSearch(_ model: AllModels) -> Bool {
        guard normalizedSearch.isEmpty == false else { return true }
        let searchable = [
            model.displayName,
            model.name,
            model.company,
            model.baseModelName ?? ""
        ]
        .joined(separator: " ")
        .lowercased()
        if searchable.contains(normalizedSearch) { return true }
        return model.displayName.toPinyinForSearch().lowercased().contains(normalizedSearch)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = filteredIDs
        ids.move(fromOffsets: source, toOffset: destination)
        for (index, id) in ids.enumerated() {
            guard let modelIndex = models.firstIndex(where: { $0.id == id }) else { continue }
            let isAgent = models[modelIndex].identity == .agent
            models[modelIndex].position = isAgent ? index + 1000 : index
        }
    }

    private func deleteAt(_ offsets: IndexSet) {
        let removing = offsets.compactMap { filteredIDs[safe: $0] }
        models.removeAll { removing.contains($0.id) }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
