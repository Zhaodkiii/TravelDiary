import SwiftUI

/// A local composer. Adding a chip never submits a model request.
struct DiaryStoryInputSheet: View {
    @Binding var brief: CreationBrief
    var editing: DiaryStoryEntry?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var kind = DiaryStoryKind.content
    @State private var text = ""
    @State private var usage = DiaryStoryUsage.rewrite
    @State private var editingID: UUID?
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("写点故事").font(.headline)
                Spacer()
                Button("完成") { commit(); dismiss() }
                    .accessibilityIdentifier("diary.story.done")
            }
            Picker("内容类型", selection: $kind) {
                ForEach(DiaryStoryKind.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            TextField(kind.placeholder, text: Binding(get: { text }, set: { value in
                    text = value
                    var drafts = brief.storyInputDrafts ?? [:]; drafts[kind.rawValue] = value
                    brief.storyInputDrafts = drafts
                }), axis: .vertical)
                .lineLimit(3...5).focused($focused)
                .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("diary.story.input")
            HStack {
                if kind == .direction {
                    Text("指导制作，优先于默认风格，不印成正文").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("使用方式", selection: $usage) {
                        ForEach(kind.usages, id: \.self) { value in
                            Text(kind == .location && value == .exact ? "显示在作品中" : value.rawValue).tag(value)
                        }
                    }.pickerStyle(.menu)
                }
                Spacer()
                if editingID != nil {
                    Button("删除", role: .destructive) {
                        brief.storyEntries?.removeAll { $0.id == editingID }
                        clearDraft(); dismiss()
                    }
                }
                Button(editingID == nil ? "添加" : "保存修改", systemImage: "arrow.up.circle.fill") {
                    commit(); focused = true
                }.disabled(trimmed.isEmpty).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("diary.story.add")
            }
            Text("已录入的内容会显示为标签，开始制作时交给 AI。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(Color(uiColor: .systemGroupedBackground))
        .presentationDetents([.height(285)])
        .presentationDragIndicator(.visible)
        .task {
            if let editing {
                kind = editing.kind; usage = editing.usage; text = editing.text; editingID = editing.id
            } else { load(kind) }
            focused = true
        }
        .onChange(of: kind) { _, value in load(value) }
    }
    private func load(_ value: DiaryStoryKind) {
        editingID = nil; usage = value.defaultUsage
        if (value == .title || value == .location), let existing = brief.storyEntries?.first(where: { $0.kind == value }) {
            editingID = existing.id; usage = existing.usage
            text = brief.storyInputDrafts?[value.rawValue] ?? existing.text
        } else { text = brief.storyInputDrafts?[value.rawValue] ?? "" }
        focused = true
    }
    private func clearDraft() {
        brief.storyInputDrafts?[kind.rawValue] = nil
        text = ""; editingID = nil
    }
    private func commit() {
        guard !trimmed.isEmpty else { return }
        brief.upsertStoryEntry(.init(id: editingID ?? UUID(), kind: kind, text: trimmed, usage: usage))
        clearDraft()
    }
}
