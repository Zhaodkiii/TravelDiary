import SwiftUI
import PhotosUI

struct DiaryPhotoManagerSheet: View {
    @ObservedObject var session: DiaryEditorSession
    @Environment(\.dismiss) private var dismiss
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var replacementID: UUID?
    @State private var showPicker = false
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        replacementID = nil
                        showPicker = true
                    } label: {
                        Label("添加照片（可多选）", systemImage: "photo.badge.plus")
                    }
                    if session.isRoot && !session.document.replaceablePhotos().isEmpty {
                        NavigationLink {
                            DiaryBatchPhotoSheet(store: session.store, session: session, embedded: true)
                        } label: {
                            Label("一键替换照片", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                }
                Section("当前页面照片（\(session.managedPhotos.count)）") {
                    if session.managedPhotos.isEmpty {
                        ContentUnavailableView("还没有照片", systemImage: "photo.on.rectangle", description: Text("点击上方“添加新照片”将照片加入画布。"))
                    }
                    ForEach(session.managedPhotos) { photo in
                        HStack(spacing: 12) {
                            thumbnail(photo.layer)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(photo.layer.name).lineLimit(2)
                                if photo.locked { Label("已锁定", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                                if !photo.visible { Label("已隐藏", systemImage: "eye.slash").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 4)
                            Button("替换") {
                                replacementID = photo.id
                                showPicker = true
                            }
                            .disabled(photo.locked)
                            Button(role: .destructive) { session.removePhoto(photo.id) } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("删除\(photo.layer.name)")
                            .disabled(photo.locked)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle("照片管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .disabled(importing || session.busy)
            .overlay {
                if importing {
                    ProgressView("正在处理照片…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .photosPicker(isPresented: $showPicker, selection: $photoItems,
                          maxSelectionCount: replacementID == nil ? 30 : 1, matching: .images)
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                let target = replacementID
                importing = true
                Task { @MainActor in
                    defer { photoItems = []; importing = false }
                    do {
                        for item in items {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                            if let target {
                                guard let photo = session.managedPhotos.first(where: { $0.id == target }), !photo.locked else {
                                    errorMessage = "照片已变化，请重新选择。"; return
                                }
                            }
                            if !(await session.importPhoto(data, replacing: target)) {
                                errorMessage = session.errorMessage ?? "照片处理失败，请重试。"
                                session.errorMessage = nil; return
                            }
                        }
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .alert("照片处理失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
            .interactiveDismissDisabled(importing || session.busy)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func thumbnail(_ layer: DiaryLayer) -> some View {
        Group {
            if let id = layer.assetID, let image = session.images[id] {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 72)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
