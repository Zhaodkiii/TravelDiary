import SwiftUI

struct MemoryArchiveSettingsView: View {
    @ObservedObject var viewModel: MemoryArchiveSettingsViewModel
    @State private var editorDraft = MemoryEditorDraft()
    @State private var showEditor = false
    @State private var showClearAllAlert = false

    var body: some View {
        ZStack {
            MemoryArchiveBackground()
            List {
                if viewModel.searchText.isEmpty {
                    archiveIntroCard
                        .memoryListRow()
                }

                if viewModel.preferences.isEnabled {
                    ForEach(viewModel.records) { record in
                        MemoryRecordCard(record: record, searchText: viewModel.searchText)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openEditor(for: record)
                            }
                            .memoryListRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteMemory(record) }
                                } label: {
                                    Label("忘记", systemImage: "heart.slash")
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    openEditor(for: record)
                                } label: {
                                    Label("更新", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .tint(.green)
                            }
                    }
                    .onDelete(perform: viewModel.delete)

                    Button {
                        openEditorForNewMemory()
                    } label: {
                        NewMemoryCard()
                    }
                    .buttonStyle(.plain)
                    .memoryListRow()
                } else {
                    disabledCard
                        .memoryListRow()
                }

                Color.clear
                    .frame(height: 16)
                    .memoryListRow()
            }
            .listStyle(.plain)
            .background(Color.clear)
        }
        .navigationTitle("记忆档案")
        .searchable(text: $viewModel.searchText, prompt: "搜索记忆")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("清空所有") {
                    showClearAllAlert = true
                }
                .disabled(viewModel.records.isEmpty)
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $showEditor) {
            MemoryEditorSheet(draft: $editorDraft) {
                Task {
                    if let record = editorDraft.record {
                        await viewModel.updateMemory(
                            record,
                            title: editorDraft.title,
                            content: editorDraft.content,
                            pinned: editorDraft.pinned
                        )
                    } else {
                        await viewModel.addMemory(
                            title: editorDraft.title,
                            content: editorDraft.content,
                            pinned: editorDraft.pinned
                        )
                    }
                    showEditor = false
                }
            }
        }
        .alert("确定要清除所有记忆吗？", isPresented: $showClearAllAlert) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task { await viewModel.clearAll() }
            }
        } message: {
            Text("清除后，聊天将无法再召回这些长期记忆。")
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if presented == false {
                    viewModel.clearError()
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var archiveIntroCard: some View {
        VStack(alignment: .center, spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.blue)
                .frame(width: 54, height: 54)
                .background(Color.blue.opacity(0.12), in: Circle())

            Text("记忆档案功能用于聊天，受支持的模型会自动在聊天时记住你的偏好，并在需要的时候主动回忆这些偏好。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                MemoryToggleRow(
                    title: "启用记忆功能",
                    icon: "heart.text.square",
                    isOn: Binding(
                        get: { viewModel.preferences.isEnabled },
                        set: {
                            viewModel.preferences.isEnabled = $0
                            viewModel.savePreferences()
                        }
                    )
                )

                MemoryToggleRow(
                    title: "允许聊天工具写入记忆",
                    icon: "square.and.pencil",
                    isOn: Binding(
                        get: { viewModel.preferences.allowToolWrite },
                        set: {
                            viewModel.preferences.allowToolWrite = $0
                            viewModel.savePreferences()
                        }
                    )
                )

                MemoryToggleRow(
                    title: "启用跨聊天记忆",
                    icon: "arrow.left.arrow.right",
                    isOn: Binding(
                        get: { viewModel.preferences.allowCrossThreadRecall },
                        set: {
                            viewModel.preferences.allowCrossThreadRecall = $0
                            viewModel.savePreferences()
                        }
                    )
                )

                Stepper(
                    value: Binding(
                        get: { viewModel.preferences.maxRecallCount },
                        set: {
                            viewModel.preferences.maxRecallCount = $0
                            viewModel.savePreferences()
                        }
                    ),
                    in: 1...20
                ) {
                    Label("最多召回 \(viewModel.preferences.maxRecallCount) 条", systemImage: "number")
                        .font(.subheadline)
                }
            }
        }
        .padding(16)
        .memoryCardStyle()
    }

    private var disabledCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.slash")
                .font(.headline)
            Text("记忆功能已关闭")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    private func openEditorForNewMemory() {
        editorDraft = MemoryEditorDraft()
        showEditor = true
    }

    private func openEditor(for record: MemoryRecord) {
        editorDraft = MemoryEditorDraft(record: record)
        showEditor = true
    }
}

private struct MemoryArchiveBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color.blue.opacity(0.08),
                Color(.systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct MemoryToggleRow: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: icon)
                .font(.subheadline)
        }
        .tint(.blue)
    }
}

private struct MemoryRecordCard: View {
    let record: MemoryRecord
    let searchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(highlighted(record.content))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                if record.pinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 3)
                }
            }

            HStack(spacing: 8) {
                if record.title.isEmpty == false {
                    Label(record.title, systemImage: "tag")
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(record.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .memoryCardStyle()
    }

    private func highlighted(_ content: String) -> AttributedString {
        var attributed = AttributedString(content)
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return attributed }

        let lowerContent = content.lowercased()
        let lowerSearch = trimmed.lowercased()
        var range = lowerContent.startIndex..<lowerContent.endIndex

        while let found = lowerContent.range(of: lowerSearch, options: .caseInsensitive, range: range) {
            let nsRange = NSRange(found, in: content)
            if let attrRange = Range(nsRange, in: attributed) {
                attributed[attrRange].foregroundColor = .blue
                attributed[attrRange].font = .body.bold()
            }
            range = found.upperBound..<lowerContent.endIndex
        }
        return attributed
    }
}

private struct NewMemoryCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.heart")
                .font(.headline)
            Text("灌输新记忆")
                .font(.headline)
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
        }
        .foregroundStyle(.blue)
        .padding(16)
        .memoryCardStyle()
    }
}

private struct MemoryEditorDraft: Equatable {
    var record: MemoryRecord?
    var title: String = ""
    var content: String = ""
    var pinned: Bool = false

    init() {}

    init(record: MemoryRecord) {
        self.record = record
        title = record.title
        content = record.content
        pinned = record.pinned
    }
}

private struct MemoryEditorSheet: View {
    @Binding var draft: MemoryEditorDraft
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                MemoryArchiveBackground()
                VStack(spacing: 12) {
                    TextField("标题，可留空", text: $draft.title)
                        .textFieldStyle(.roundedBorder)

                    TextEditor(text: $draft.content)
                        .frame(minHeight: 240)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )

                    Toggle(isOn: $draft.pinned) {
                        Label("置顶这条记忆", systemImage: "pin")
                    }
                    .tint(.blue)
                    .padding(12)
                    .memoryCardStyle()
                }
                .padding(16)
            }
            .navigationTitle("记忆编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave()
                    } label: {
                        Label("保存", systemImage: "checkmark")
                    }
                    .disabled(draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private extension View {
    func memoryCardStyle() -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }

    func memoryListRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
    }
}

