import SwiftUI

struct PromptRepoSettingsView: View {
    @Binding var promptRepo: [PromptRepo]
    var onPersistRequested: () -> Void = {}

    @State private var searchText = ""
    @State private var editingTitleID: UUID?
    @State private var editingDetailID: UUID?

    private var filteredIDs: [UUID] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return promptRepo.map(\.id)
        }
        let lowercased = trimmed.lowercased()
        return promptRepo
            .filter { item in
                item.localizedTitle.lowercased().contains(lowercased)
                || item.localizedContent.lowercased().contains(lowercased)
                || item.localizedTitle.toPinyinForSearch().lowercased().contains(lowercased)
            }
            .map(\.id)
    }

    private var editablePromptTemplates: [PromptRepo] {
        promptRepo.filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
    }

    var body: some View {
        ZStack {
            backgroundView
            promptListView
        }
        .navigationTitle(L10n.text("ai_settings.row.prompt_repo"))
        .searchable(text: $searchText, prompt: L10n.text("ai_settings.prompt_repo.search", fallback: "Search prompts", comment: "Prompt repo search placeholder"))
        .toolbar { toolbarContent }
        .sheet(isPresented: Binding(
            get: { editingTitleID != nil },
            set: { if $0 == false { editingTitleID = nil } }
        )) {
            if let binding = bindingForPrompt(id: editingTitleID) {
                PromptRepoTitleEditSheet(prompt: binding)
                    .onDisappear {
                        persistPromptRepo()
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingDetailID != nil },
            set: { if $0 == false { editingDetailID = nil } }
        )) {
            if let binding = bindingForPrompt(id: editingDetailID) {
                PromptRepoDetailEditSheet(
                    prompt: binding,
                    promptTemplates: editablePromptTemplates.filter { $0.id != editingDetailID }
                )
                .onDisappear {
                    persistPromptRepo()
                }
            }
        }
    }

    private var backgroundView: some View {
        LinearGradient(
            colors: [
                Color.accentColor.opacity(0.12),
                Color(.systemPurple).opacity(0.08),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var promptListView: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                introCard
            }

            if filteredIDs.isEmpty {
                emptyState
            } else {
                ForEach(filteredIDs, id: \.self) { id in
                    if let prompt = prompt(for: id) {
                        promptCard(prompt)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deletePrompt(id: id)
                                } label: {
                                    Label(L10n.text("common.delete", fallback: "Delete", comment: "Delete action"), systemImage: "trash")
                                }
                            }
                    }
                }
                .onMove(perform: move)
            }
        }
        .listStyle(.plain)
        .scrollContentBackgroundIfAvailable(.hidden)
    }

    private var introCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.full")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.tint)
            Text(L10n.text("ai_settings.prompt_repo.intro", fallback: "Create reusable prompt templates here. You can apply them directly from prompt editors for conversations, agents, and small tasks.", comment: "Prompt repo intro"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(L10n.text("ai_settings.prompt_repo.empty", fallback: "No prompt templates", comment: "Empty prompt template list title"))
                .font(.headline)
            Text(L10n.text("ai_settings.prompt_repo.empty.search", fallback: "Try another keyword.", comment: "Prompt template empty search description"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EditButton()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                addPrompt()
            } label: {
                Text(L10n.text("ai_settings.action.add_prompt", fallback: "Add Prompt", comment: "Add prompt action"))
            }
        }
    }

    private func promptCard(_ item: PromptRepo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("prompt")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.tint)

                Text(highlightedTitle(for: item))
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .onTapGesture {
                        editingTitleID = item.id
                    }

                Spacer()

                if item.isSystem {
                    Image(systemName: "checkmark.seal")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.text("ai_settings.field.system_preset", fallback: "System preset", comment: "System preset accessibility label"))
                }
            }

            Text(item.localizedContent.isEmpty ? L10n.text("ai_settings.prompt_repo.no_content", fallback: "No content", comment: "Empty prompt content fallback") : item.localizedContent)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 44, alignment: .topLeading)

            HStack {
                Text(formattedDate(item.timestamp))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    editingDetailID = item.id
                } label: {
                    Text(L10n.text("ai_settings.prompt_repo.edit_content", fallback: "Edit content", comment: "Edit prompt content action"))
                        .font(.footnote.weight(.bold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: Color.accentColor.opacity(0.12), radius: 2, x: 0, y: 1)
        .padding(.vertical, 4)
    }

    private func highlightedTitle(for item: PromptRepo) -> AttributedString {
        let title = item.localizedTitle.isEmpty ? L10n.text("ai_settings.prompt_item", fallback: "Prompt Item", comment: "Prompt item fallback title") : item.localizedTitle
        var attributed = AttributedString(title)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return attributed }

        let lowerTitle = title.lowercased()
        if let range = lowerTitle.range(of: trimmed.lowercased(), options: .caseInsensitive),
           let attributedRange = Range(NSRange(range, in: title), in: attributed) {
            attributed[attributedRange].foregroundColor = .accentColor
        }
        return attributed
    }

    private func addPrompt() {
        promptRepo.insert(
            PromptRepo(
                title: L10n.text("ai_settings.prompt_repo.new_title", fallback: "New Prompt", comment: "New prompt default title"),
                content: L10n.text("ai_settings.prompt_repo.new_content", fallback: "New prompt content", comment: "New prompt default content"),
                isSystem: false,
                timestamp: Date()
            ),
            at: 0
        )
        persistPromptRepo()
    }

    private func deletePrompt(id: UUID) {
        promptRepo.removeAll { $0.id == id }
        persistPromptRepo()
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        promptRepo.move(fromOffsets: source, toOffset: destination)
        persistPromptRepo()
    }

    private func persistPromptRepo() {
        onPersistRequested()
    }

    private func prompt(for id: UUID) -> PromptRepo? {
        promptRepo.first { $0.id == id }
    }

    private func bindingForPrompt(id: UUID?) -> Binding<PromptRepo>? {
        guard let id, let index = promptRepo.firstIndex(where: { $0.id == id }) else { return nil }
        return $promptRepo[index]
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct PromptRepoTitleEditSheet: View {
    @Binding var prompt: PromptRepo
    @Environment(\.dismiss) private var dismiss

    private var titleBinding: Binding<String> {
        Binding(
            get: { prompt.localizedTitle },
            set: { value in
                prompt.title = value
                prompt.localizationKey = nil
                prompt.timestamp = Date()
            }
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            Form {
                Section(L10n.text("common.title", fallback: "Title", comment: "Prompt title field")) {
                    TextField(L10n.text("ai_settings.prompt_repo.title_placeholder", fallback: "Enter title", comment: "Prompt title placeholder"), text: titleBinding)
                        .textInputAutocapitalizationIfAvailable(.never)
                        .autocorrectionDisabledIfAvailable()
                }
            }
            .navigationTitle(L10n.text("ai_settings.prompt_repo.edit_title", fallback: "Edit title", comment: "Edit prompt title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save", fallback: "Save", comment: "Save action")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PromptRepoDetailEditSheet: View {
    @Binding var prompt: PromptRepo
    let promptTemplates: [PromptRepo]

    @Environment(\.dismiss) private var dismiss
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false

    private var contentBinding: Binding<String> {
        Binding(
            get: { prompt.localizedContent },
            set: { value in
                prompt.content = value
                prompt.localizationKey = nil
                prompt.timestamp = Date()
            }
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            Form {
                Section(L10n.text("ai_settings.field.content", fallback: "Content", comment: "Prompt content field")) {
                    PromptInputEditorView(
                        text: contentBinding,
                        promptTemplates: promptTemplates,
                        showsCurrentDateToggle: false,
                        onVoiceInput: { showVoiceInput = true },
                        onTextInput: { showTextInputDrawer = true }
                    )
                }

                Section {
                    Toggle(L10n.text("ai_settings.field.system_preset", fallback: "System preset", comment: "System preset toggle"), isOn: $prompt.isSystem)
                }
            }
            .navigationTitle(L10n.text("ai_settings.prompt_repo.edit_content", fallback: "Edit content", comment: "Edit prompt content action"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save", fallback: "Save", comment: "Save action")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: contentBinding,
                isPresented: $showTextInputDrawer
            )
            .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: contentBinding,
                isPresented: $showVoiceInput
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }
}
