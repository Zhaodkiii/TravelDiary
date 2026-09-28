import SwiftUI

struct SmallTaskEditorView: View {
    let task: SmallTask?
    let nextID: Int
    var promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling()
    var promptTemplates: [PromptRepo] = []
    let onSave: (SmallTask) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brief = ""
    @State private var prompt = ""
    @State private var icon = "checklist"
    @State private var selectedToolNames: Set<String> = []
    @State private var showIconPicker = false
    @State private var showTextInputDrawer = false
    @State private var showVoiceInput = false

    init(
        task: SmallTask?,
        nextID: Int,
        promptTooling: any AISettingsPromptToolingProviding = UnavailableAISettingsPromptTooling(),
        promptTemplates: [PromptRepo] = [],
        onSave: @escaping (SmallTask) -> Void
    ) {
        self.task = task
        self.nextID = nextID
        self.promptTooling = promptTooling
        self.promptTemplates = promptTemplates
        self.onSave = onSave

        _name = State(initialValue: task?.name ?? "")
        _brief = State(initialValue: task?.brief ?? "")
        _prompt = State(initialValue: task?.prompt ?? "")
        _icon = State(initialValue: {
            let icon = task?.icon ?? ""
            return icon.isEmpty ? "checklist" : icon
        }())
        _selectedToolNames = State(initialValue: Set(task?.toolList ?? []).intersection(Set(SparkToolName.all)))
    }

    var body: some View {
        Form {
            Section(L10n.text("ai_settings.small_tasks.section.icon", fallback: "Icon", comment: "Small task icon section")) {
                HStack {
                    Spacer()
                    Button {
                        showIconPicker = true
                    } label: {
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section(L10n.text("ai_settings.small_tasks.section.basic", fallback: "Basic info", comment: "Small task basic section")) {
                TextField(L10n.text("common.name", fallback: "Name", comment: "Small task name field"), text: $name)
                TextField(L10n.text("ai_settings.small_tasks.field.brief", fallback: "Brief", comment: "Small task brief field"), text: $brief)
            }

            Section(L10n.text("ai_settings.small_tasks.section.prompt", fallback: "Prompt", comment: "Small task prompt section")) {
                PromptInputEditorView(
                    text: $prompt,
                    promptTemplates: promptTemplates,
                    onVoiceInput: { showVoiceInput = true },
                    onTextInput: { showTextInputDrawer = true }
                )
            }

            Section(L10n.text("common.tools", fallback: "Tools", comment: "Small task tools section")) {
                MainNavigationLink {
                    GroupedToolSelectionView(
                        title: L10n.text("common.tools", fallback: "Tools", comment: "Tool selection title"),
                        selectedValues: $selectedToolNames
                    )
                } label: {
                    HStack {
                        Text(L10n.text("common.tools", fallback: "Tools", comment: "Tool selection label"))
                        Spacer()
                        Text(selectedToolsSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(task == nil ? L10n.text("ai_settings.small_tasks.nav.new_title", fallback: "New small task", comment: "New small task title") : L10n.text("ai_settings.small_tasks.nav.edit_title", fallback: "Edit small task", comment: "Edit small task title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("common.save", fallback: "Save", comment: "Save action")) {
                    save()
                }
                .disabled(canSave == false)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            ModelIconPickerSheet(selectedIcon: $icon)
        }
        .sheet(isPresented: $showTextInputDrawer) {
            SparkPromptInputDrawerSheet(
                text: $prompt,
                isPresented: $showTextInputDrawer,
                onTranslate: {
                    try await promptTooling.translate(text: prompt)
                },
                onOCRImage: { image in
                    try await promptTooling.ocrImage(image)
                }
            )
            .sparkInputPresentationChromeIfAvailable()
        }
        .sheet(isPresented: $showVoiceInput) {
            SparkVoiceInputSheet(
                text: $prompt,
                isPresented: $showVoiceInput
            )
            .sparkInputPresentationChromeIfAvailable()
        }
    }

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var selectedToolsSummary: String {
        let total = SparkToolName.all.count
        if selectedToolNames.count == total {
            return L10n.text("common.all", fallback: "All", comment: "All tools selected")
        }
        if selectedToolNames.isEmpty {
            return L10n.text("ai_settings.models.online.selection.none", fallback: "None", comment: "No tools selected")
        }
        return "\(selectedToolNames.count)/\(total)"
    }

    private func save() {
        let id = task?.id ?? nextID
        let saved = SmallTask.createLocalTask(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brief: brief.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            toolList: selectedToolNames.sorted()
        )
        onSave(saved)
        dismiss()
    }
}
