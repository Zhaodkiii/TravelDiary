import SwiftUI

struct SmallTasksSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    /// 当前正在编辑的任务（nil = 不展示 sheet）
    @State private var editingTask: SmallTask?

    /// 删除确认
    @State private var pendingDelete: SmallTask?

    /// 本地任务列表
    private var localTasks: [SmallTask] {
        viewModel.snapshot.smallTasks
            .filter { $0.source == .local }
            .sorted { $0.code < $1.code }
    }

    var body: some View {
        List {
            Section {
                if localTasks.isEmpty {
                    Text(
                        L10n.text(
                            "ai_settings.small_tasks.empty",
                            fallback: "No small tasks",
                            comment: "Empty small tasks list"
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(localTasks) { task in
                        Button {
                            /// ✅ 直接赋值，驱动 sheet
                            editingTask = task
                        } label: {
                            SmallTaskRow(task: task)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                pendingDelete = task
                            } label: {
                                Label(
                                    L10n.text("common.delete", fallback: "Delete", comment: "Delete action"),
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(
            L10n.text(
                "ai_settings.small_tasks.nav.title",
                fallback: "Small tasks",
                comment: "Small tasks settings title"
            )
        )
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    /// ✅ 新建任务（传 nil 表示创建）
                    editingTask = nil
                    /// ⚠️ 这里不能触发 sheet，所以需要一个“占位对象”
                    /// 推荐方式：用一个 dummy task
                    editingTask = SmallTask.newDraft(id: viewModel.nextLocalSmallTaskID())
                } label: {
                    Image(systemName: "plus")
                }
            }
        }

        /// ✅ 核心：用 item sheet（彻底解决 nil 问题）
        .sheet(item: $editingTask) { task in
            CompatibleNavigationContainer {
                SmallTaskEditorView(
                    task: task,
                    nextID: viewModel.nextLocalSmallTaskID(),
                    promptTooling: viewModel.promptTooling,
                    promptTemplates: viewModel.snapshot.promptRepo
                ) { updatedTask in
                    Task {
                        await viewModel.upsertLocalSmallTaskAndPersist(updatedTask)
                    }
                    /// 关闭 sheet
                    editingTask = nil
                }
            }
        }

        /// 删除确认
        .alert(
            L10n.text(
                "ai_settings.small_tasks.delete.title",
                fallback: "Delete small task?",
                comment: "Delete small task alert title"
            ),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if $0 == false { pendingDelete = nil } }
            )
        ) {
            Button(
                L10n.text("common.cancel", fallback: "Cancel", comment: "Cancel action"),
                role: .cancel
            ) {
                pendingDelete = nil
            }

            Button(
                L10n.text("common.delete", fallback: "Delete", comment: "Delete action"),
                role: .destructive
            ) {
                if let task = pendingDelete {
                    Task {
                        await viewModel.deleteLocalSmallTaskAndPersist(code: task.code)
                    }
                }
                pendingDelete = nil
            }
        }
    }
}

private struct SmallTaskRow: View {
    let task: SmallTask

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.icon.isEmpty ? "checklist" : task.icon)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)

                Text(task.brief.isEmpty ? task.code : task.brief)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
extension SmallTask {

    /// 创建一个“草稿任务”（用于 UI 编辑）
    static func newDraft(id: Int) -> SmallTask {
        SmallTask(
            id: id,
            name: "",
            code: "Local_\(id)",   // ⚠️ 提前生成 code，保证 id 稳定
            brief: "",
            prompt: "",
            icon: "checklist",
            toolList: [],
            source: .local
        )
    }
}
