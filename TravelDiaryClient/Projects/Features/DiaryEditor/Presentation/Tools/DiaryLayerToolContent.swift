import SwiftUI
import PhotosUI

struct DiaryLayerToolContent: View {
    @ObservedObject var session: DiaryEditorSession
    @State private var showPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("透明度").font(.subheadline).foregroundStyle(.secondary)
                Slider(value: Binding(get: { session.selected?.effectiveOpacity ?? 1 },
                                      set: { session.previewOpacity($0) }), in: 0...1,
                       onEditingChanged: { if !$0 { session.finishInteraction() } })
                    .disabled(session.selected == nil || session.selected?.locked == true)
                    .accessibilityLabel("图层透明度")
                Text(session.selected == nil ? "—" : "\(Int((session.selected?.effectiveOpacity ?? 1) * 100))")
                    .monospacedDigit().font(.caption).frame(width: 30)
            }.padding(.horizontal, 20)
            HStack(spacing: 0) {
                action("添加照片", "plus", enabled: true) { session.finishInteraction(); showPicker = true }
                action("删除", "trash", enabled: session.canDeleteSelected) { session.removeSelected() }
                action("前移一层", "arrow.up.to.line", enabled: session.canMoveSelected(forward: true)) { session.reorderSelected(forward: true) }
                action("后移一层", "arrow.down.to.line", enabled: session.canMoveSelected(forward: false)) { session.reorderSelected(forward: false) }
                action(session.selected?.visible == false ? "显示" : "隐藏", session.selected?.visible == false ? "eye.slash" : "eye", enabled: session.selected != nil) {
                    if let id = session.selectedID { session.toggleVisibility(id) }
                }
                action(session.selected?.locked == true ? "解锁" : "锁定", session.selected?.locked == true ? "lock.fill" : "lock.open", enabled: session.selected != nil) {
                    if let id = session.selectedID { session.toggleLock(id) }
                }
            }.padding(.horizontal, 8)
            if session.scopeLayers.isEmpty {
                Text("暂无图层，点击 ＋ 添加照片").font(.subheadline).foregroundStyle(.secondary).frame(height: 90)
            } else {
                DiaryLayerThumbnailRail(session: session).frame(height: 90)
            }
            HStack {
                Text("底层 → 顶层 · 长按拖动排序").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 36, height: 32) }
                    .disabled(session.undoStack.isEmpty).accessibilityLabel("撤销")
                Button { session.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 36, height: 32) }
                    .disabled(session.redoStack.isEmpty).accessibilityLabel("重做")
            }.padding(.horizontal, 20)
        }
        .disabled(importing || session.busy)
        .overlay { if importing { ProgressView("正在添加照片…").padding().background(.regularMaterial, in: Capsule()) } }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            importing = true
            Task { @MainActor in
                defer { photoItem = nil; importing = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                    _ = await session.importPhoto(data)
                } catch { session.errorMessage = error.localizedDescription }
            }
        }
        .onDisappear { session.finishInteraction() }
    }

    private func action(_ title: String, _ symbol: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).font(.title3).frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Rectangle())
        }.disabled(!enabled).accessibilityLabel(title)
    }
}
