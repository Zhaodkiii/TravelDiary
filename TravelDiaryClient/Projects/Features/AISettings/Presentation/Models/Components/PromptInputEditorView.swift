import SwiftUI

struct PromptInputEditorView: View {
    @Binding var text: String
    var promptTemplates: [PromptRepo] = []
    var isAutoFillInProgress = false
    var isAutoFilled = false
    var isAutoFillDisabled = false
    var showsCurrentDateToggle = true
    var onAutoFill: (() -> Void)?
    var onVoiceInput: () -> Void
    var onTextInput: () -> Void

    @State private var showsTemplatePicker = false

    private var availableTemplates: [PromptRepo] {
        promptTemplates
            .filter { $0.localizedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { lhs, rhs in
                if lhs.isSystem != rhs.isSystem {
                    return lhs.isSystem && rhs.isSystem == false
                }
                return lhs.localizedTitle.localizedCaseInsensitiveCompare(rhs.localizedTitle) == .orderedAscending
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $text)
                .scrollContentBackgroundIfAvailable(.hidden)
                .frame(minHeight: 150)

            HStack(spacing: 10) {
                if onAutoFill != nil {
                    autoFillButton
                }

                Spacer()
                Text(L10n.text("prompt_input.tools", fallback: "Input tools", comment: "Prompt input toolbar label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: onVoiceInput) {
                    Image(systemName: "microphone.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("prompt_input.voice.title", fallback: "Voice input", comment: "Voice input sheet title"))

                Button(action: onTextInput) {
                    Image(systemName: "chevron.up.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("prompt_input.drawer.title", fallback: "Multiline input", comment: "Prompt drawer title"))
            }
            .foregroundStyle(.tint)

            if showsCurrentDateToggle {
                currentDateToggle
            }

            if availableTemplates.isEmpty == false {
                promptTemplateSelector
            }
        }
        .sheet(isPresented: $showsTemplatePicker) {
            PromptTemplatePickerSheet(
                templates: availableTemplates,
                hasCurrentText: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                onReplace: { template in
                    text = template.localizedContent
                },
                onAppend: { template in
                    appendTemplate(template)
                }
            )
        }
        .sparkKeyboardDoneToolbar {
            SparkKeyboardDismiss.endEditing()
        }
    }

    private var autoFillButton: some View {
        Button {
            onAutoFill?()
        } label: {
            HStack(spacing: 5) {
                if isAutoFillInProgress {
                    ProgressView()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofilling", fallback: "Filling", comment: "Prompt autofill progress"))
                        .font(.caption)
                } else if isAutoFilled {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.undo_autofill", fallback: "Undo fill", comment: "Undo prompt autofill"))
                        .font(.caption)
                } else {
                    Image(systemName: "pencil.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 25, height: 25)
                    Text(L10n.text("prompt_input.toolbar.autofill", fallback: "Auto fill", comment: "Prompt autofill action"))
                        .font(.caption)
                }
            }
            .foregroundStyle(isAutoFillDisabled ? Color(.systemGray) : Color.accentColor)
        }
        .buttonStyle(.plain)
        .disabled(isAutoFillInProgress || isAutoFillDisabled)
    }

    private var promptTemplateSelector: some View {
        Button {
            showsTemplatePicker = true
        } label: {
            HStack(spacing: 12) {
                Image("prompt")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("prompt_input.prompt_repo.bottom_title", fallback: "Choose preset prompt", comment: "Prompt preset selector bottom row title"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text(L10n.format("prompt_input.prompt_repo.bottom_subtitle_format", fallback: "%d templates available", comment: "Prompt preset selector bottom row subtitle", availableTemplates.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text("prompt_input.prompt_repo", fallback: "Prompt library", comment: "Prompt library accessibility label"))
    }

    private var currentDateToggle: some View {
        Toggle(
            L10n.text(
                "ai_settings.small_tasks.field.use_current_date",
                fallback: "Append current date to system prompt",
                comment: "Small task use current date toggle"
            ),
            isOn: Binding(
                get: { AIPromptKeywords.contains(AIPromptKeywords.currentDate, in: text) },
                set: { enabled in
                    text = AIPromptKeywords.setting(AIPromptKeywords.currentDate, enabled: enabled, in: text)
                }
            )
        )
    }

    private func appendTemplate(_ template: PromptRepo) {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = current.isEmpty ? template.localizedContent : [text, template.localizedContent].joined(separator: "\n\n")
    }
}

private struct PromptTemplatePickerSheet: View {
    let templates: [PromptRepo]
    let hasCurrentText: Bool
    let onReplace: (PromptRepo) -> Void
    let onAppend: (PromptRepo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredTemplates: [PromptRepo] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return templates }
        let lowercased = trimmed.lowercased()
        return templates.filter { template in
            template.localizedTitle.lowercased().contains(lowercased)
            || template.localizedContent.lowercased().contains(lowercased)
            || template.localizedTitle.toPinyinForSearch().lowercased().contains(lowercased)
        }
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            List {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image("prompt")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text("prompt_input.prompt_repo", fallback: "Prompt library", comment: "Prompt library title"))
                                .font(.headline)
                            Text(L10n.text("prompt_input.prompt_repo.picker_hint", fallback: "Choose a reusable prompt template and apply it to the current system prompt.", comment: "Prompt library picker hint"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if filteredTemplates.isEmpty {
                    Section {
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
                        .padding(.vertical, 20)
                    }
                } else {
                    ForEach(filteredTemplates) { template in
                        Section(displayTitle(for: template)) {
                            PromptTemplatePickerRow(
                                template: template,
                                hasCurrentText: hasCurrentText,
                                onReplace: {
                                    onReplace(template)
                                    dismiss()
                                },
                                onAppend: {
                                    onAppend(template)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: L10n.text("ai_settings.prompt_repo.search", fallback: "Search prompt templates", comment: "Prompt template search placeholder"))
            .navigationTitle(L10n.text("ai_settings.row.prompt_repo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PromptTemplatePickerRow: View {
    let template: PromptRepo
    let hasCurrentText: Bool
    let onReplace: () -> Void
    let onAppend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("prompt")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.tint)

                Text(displayTitle(for: template))
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                if template.isSystem {
                    Label(L10n.text("ai_settings.field.system_preset", fallback: "System preset", comment: "System preset badge"), systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.iconOnly)
                        .accessibilityLabel(L10n.text("ai_settings.field.system_preset", fallback: "System preset", comment: "System preset accessibility label"))
                }
            }

            Text(template.localizedContent)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button {
                    onReplace()
                } label: {
                    Label(
                        hasCurrentText
                            ? L10n.text("prompt_input.prompt_repo.replace", fallback: "Replace", comment: "Replace prompt action")
                            : L10n.text("common.use", fallback: "Use", comment: "Use action"),
                        systemImage: hasCurrentText ? "arrow.triangle.2.circlepath" : "checkmark.circle"
                    )
                }

                if hasCurrentText {
                    Button {
                        onAppend()
                    } label: {
                        Label(L10n.text("prompt_input.prompt_repo.append", fallback: "Append", comment: "Append prompt action"), systemImage: "text.badge.plus")
                    }
                }
            }
            .buttonStyle(.borderless)
            .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

private func displayTitle(for template: PromptRepo) -> String {
    let trimmed = template.localizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? L10n.text("ai_settings.prompt_item", fallback: "Prompt", comment: "Prompt item fallback title") : trimmed
}
