import SwiftUI
import UniformTypeIdentifiers

/// 对齐 Health「添加本地模型」Sheet：目录下载 + 导入 .gguf（第一阶段）。
struct LocalModelDownloadSheet: View {
    @ObservedObject var viewModel: AISettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var busyCatalogItemID: String?
    @State private var importing = false
    @State private var inlineError: String?

    private var catalog: [LocalModelCatalogItem] {
        viewModel.localModelCatalog()
    }

    var body: some View {
        CompatibleNavigationContainer {
            List {
                Section {
                    Text(L10n.text("ai_settings.models.local_download.explain"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section(L10n.text("ai_settings.models.section.catalog_download")) {
                    ForEach(catalog) { item in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName)
                                    .font(.headline)
                                Text(item.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    busyCatalogItemID = item.id
                                    defer { busyCatalogItemID = nil }
                                    do {
                                        try await viewModel.installLocalModel(item: item)
                                    } catch {
                                        inlineError = error.localizedDescription
                                    }
                                }
                            } label: {
                                if busyCatalogItemID == item.id {
                                    ProgressView()
                                } else {
                                    Text(L10n.text("ai_settings.models.action.download"))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busyCatalogItemID != nil)
                        }
                    }
                    Button {
                        importing = true
                    } label: {
                        Label(L10n.text("ai_settings.models.action.import_gguf"), systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle(L10n.text("ai_settings.models.local_download.nav_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.ok")) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        do {
                            try await viewModel.importLocalModel(from: url)
                        } catch {
                            inlineError = error.localizedDescription
                        }
                    }
                case .failure(let error):
                    inlineError = error.localizedDescription
                }
            }
            .alert(L10n.text("common.operation_failed"), isPresented: Binding(
                get: { inlineError != nil },
                set: { if $0 == false { inlineError = nil } }
            )) {
                Button(L10n.text("common.ok")) {}
            } message: {
                Text(inlineError ?? "")
            }
        }
    }
}
