import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct APIKeysSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var showAddCustomProvider = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    private var sortedProviders: [APIKeys] {
        let filtered = viewModel.snapshot.apiKeys.filter { AIProviderAdapterRegistry.adapter(for: $0.providerID).isLocal == false }
        let grouped = Dictionary(grouping: filtered, by: \.providerID)
        return grouped.values
            .compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        List {
            if viewModel.shouldShowTrialEntry {
                AITrialSettingsView(viewModel: viewModel)
            }

            Section(L10n.text("ai_settings.providers.section.providers")) {
                ForEach(sortedProviders) { provider in
                    providerRow(provider)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    showAddCustomProvider = true
                } label: {
                  Image(systemName: "plus.circle.fill")
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.providers.nav_title"))
        .listStyle(.insetGrouped)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refreshProviderRuntimeConfiguration()
        }
        .sheet(isPresented: $showAddCustomProvider) {
            AddCustomProviderSheet { newProvider in
                Task {
                    let ok = await viewModel.addProviderAndPersist(newProvider)
                    if ok {
                        impact(.medium)
                    } else if let message = viewModel.errorMessage {
                        showError(message)
                    }
                }
            }
        }
        .alert(L10n.text("ai_settings.providers.editor.alert.notice_title"), isPresented: $showErrorAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.snapshot.apiKeys)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.snapshot.trial)
    }

    private func providerRow(_ provider: APIKeys) -> some View {
        HStack(spacing: 12) {
            MainNavigationLink {
                ProviderSettingsEditorView(
                    provider: provider,
                    viewModel: viewModel
                )
            } label: {
                HStack(spacing: 12) {
                    Image(companyIconName(for: provider.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                    Text(provider.localizedDisplayName)
                        .font(.body)
                    Spacer()
                    if provider.source == .custom {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle("", isOn: Binding(
                get: { provider.isHidden == false },
                set: { newValue in
                    setProviderEnabled(providerID: provider.id, enabled: newValue)
                }
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
    }

    private func setProviderEnabled(providerID: UUID, enabled: Bool) {
        Task {
            let ok = await viewModel.setProviderEnabledAndPersist(providerID: providerID, enabled: enabled)
            if ok {
                impact(.light)
            } else if let message = viewModel.errorMessage {
                showError(message)
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

private struct AddCustomProviderSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var key = ""
    @State private var requestURL = ""
    @State private var errorMessage: String?

    let onSave: (APIKeys) -> Void

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                Section {
                    TextField(L10n.text("ai_settings.providers.add.field.name"), text: $name)
                    SecureField(L10n.text("ai_settings.providers.editor.field.api_key"), text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(L10n.text("ai_settings.providers.editor.field.request_url"), text: $requestURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    if requestURL.isEmpty == false, requestURL.hasSuffix("/v1/chat/completions") == false {
                        Button(L10n.text("ai_settings.providers.add.action.append_completion_path")) {
                            var base = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            while base.hasSuffix("/") { base.removeLast() }
                            requestURL = "\(base)/v1/chat/completions"
                        }
                        .font(.footnote)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(L10n.text("ai_settings.providers.add.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save")) {
                        guard validate() else { return }
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let normalizedCompany = "CUSTOM_\(UUID().uuidString.prefix(8).uppercased())"
                        let provider = APIKeys(
                            providerID: normalizedCompany,
                            name: trimmedName,
                            company: normalizedCompany,
                            key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                            requestURL: requestURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            isHidden: false,
                            help: L10n.text("ai_settings.providers.add.help"),
                            source: .custom,
                            timestamp: Date()
                        )
                        onSave(provider)
                        dismiss()
                    }
                    .disabled(!isBasicInputFilled)
                }
            }
        }
    }

    private var isBasicInputFilled: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func validate() -> Bool {
        let url = requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else {
            errorMessage = L10n.text("ai_settings.providers.add.error.invalid_url_prefix")
            return false
        }
        errorMessage = nil
        return true
    }
}
