import SwiftUI

struct CreationDraftListView: View {
    let owner: String
    @State private var drafts: [CreationDraft] = []
    @State private var selected: CreationDraft?
    @State private var deleting: CreationDraft?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(drafts) { draft in
                    Button { if !draft.published { selected = draft } } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(draft.published ? "已保存的制作资料" : draft.handoffID == nil ? "准备草稿" : "未完成制作")
                            Text("\(draft.photos.count) 张照片 · \(draft.brief.theme)").font(.subheadline)
                            Text(draft.updatedAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("删除", role: .destructive) { deleting = draft } }
                }
            } footer: { Text("删除会移除本地草稿、原图及尚未保存的制作进度。已经保存到手帐的作品不受影响。") }
        }.navigationTitle("制作草稿")
            .overlay { if drafts.isEmpty { ContentUnavailableView("暂无制作草稿", systemImage: "tray") } }
            .task { await reload() }
            .fullScreenCover(item: $selected, onDismiss: { Task { await reload() } }) { draft in CreationFlowView(owner: owner, draft: draft) }
            .confirmationDialog("删除这份制作草稿？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除草稿", role: .destructive) {
                    guard let id = deleting?.id else { return }; deleting = nil
                    Task { do { try await CreationDraftStore(owner: owner).remove(id); await reload() } catch { self.error = error.localizedDescription } }
                }
            }
            .alert("制作草稿", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好") { error = nil } } message: { Text(error ?? "") }
    }
    private func reload() async { do { drafts = try await CreationDraftStore(owner: owner).list() } catch { self.error = error.localizedDescription } }
}
