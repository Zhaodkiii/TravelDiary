import SwiftUI

struct DiaryBlankBookSheet: View {
    let ownerID: String
    let completed: (DiaryBook) -> Void
    var paletteID: String = "0"
    @Environment(\.dismiss) private var dismiss
    @State private var title = "我的手帐"
    @State private var preset = DiaryPagePreset.b5
    @State private var count = 1
    @State private var busy = false
    @State private var message: String?
    @State private var operationID = UUID()
    var body: some View {
        Group {
            Form {
                Section("手帐名称") { TextField("我的手帐", text: $title) }
                Section("页面规格") { Picker("尺寸", selection: $preset) { ForEach(DiaryPagePreset.allCases) { Text($0.albumTitle).tag($0) } } }
                Section {
                    Stepper("\(count) 张空白页", value: $count, in: 1...20)
                    Text("创建后可随时增删页面、添加照片和文字。第一页会作为书架封面。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message { Section { Text(message).foregroundStyle(.red) } }
            }
            .navigationTitle("空白创建").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await create() } } label: {
                    Text(busy ? "正在创建…" : "创建手帐").frame(maxWidth: .infinity).padding()
                }.buttonStyle(.borderedProminent).padding()
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).count > 60)
            }
            .disabled(busy)
        }.interactiveDismissDisabled(busy).tint(DiaryLibraryStyle.accent)
    }
    private func create() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        var draft = DiaryAlbumDraft(); draft.id = operationID; draft.title = title; draft.size = preset.rawValue
        draft.pages = (0..<count).map { _ in DiaryAlbumPage(role: .blank, theme: paletteID == "2" ? .film : .minimal, paletteID: paletteID == "2" ? "1" : paletteID) }
        do {
            let book = try await DiaryDocumentStore(ownerID: ownerID).createAlbum(draft, photoDirectory: StoragePaths.system.temporaryRoot)
            completed(book)
        } catch { message = error.localizedDescription }
    }
}

extension DiaryPagePreset {
    var albumTitle: String { switch self { case .a5: "A5 竖版 · 148 × 210 mm"; case .b5: "B5 竖版 · 176 × 250 mm"; case .portrait: "竖版 · 5:7"; case .square: "正方形 · 1:1" } }
}
