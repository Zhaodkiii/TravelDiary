import SwiftUI
import PhotosUI

/// Per-leaf photo shortcuts, separate from both the paper and the page navigation rail.
struct DiaryReaderPhotoStrip: View {
    let page: DiaryPageEntry
    let store: DiaryDocumentStore
    let title: String
    @Binding var readerBusy: Bool
    let onSaved: () async -> Void
    @State private var session: DiaryEditorSession?
    @State private var loading = false
    @State private var error: String?
    @State private var showPicker = false
    @State private var items: [PhotosPickerItem] = []
    @State private var replacementID: UUID?
    @State private var pendingSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                if loading { ProgressView().controlSize(.mini) }
                if pendingSave {
                    Button("重新保存") { Task { await retrySave() } }.font(.caption2)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let session {
                        ForEach(session.managedPhotos.filter(\.visible)) { photo in
                            Menu {
                                Button("替换照片", systemImage: "photo") {
                                    replacementID = photo.id; showPicker = true
                                }
                                Button("删除照片", systemImage: "trash", role: .destructive) {
                                    Task { await delete(photo.id) }
                                }
                            } label: {
                                Group {
                                    if let id = photo.layer.assetID, let image = session.images[id] {
                                        Image(uiImage: image).resizable().scaledToFill()
                                    } else { Image(systemName: "photo") }
                                }
                                .frame(width: 44, height: 48).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(alignment: .bottomTrailing) {
                                    if photo.locked { Image(systemName: "lock.fill").font(.caption2).background(.regularMaterial) }
                                }
                            }
                            .disabled(photo.locked || pendingSave)
                            .accessibilityLabel("\(title)，\(photo.layer.name)，替换或删除")
                        }
                    }
                    Button {
                        replacementID = nil; showPicker = true
                    } label: {
                        Image(systemName: "plus").font(.title3)
                            .frame(width: 44, height: 48)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(session == nil || pendingSave)
                    .accessibilityLabel("为\(title)添加照片")
                }.padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 72, alignment: .top)
        .disabled(readerBusy || loading)
        .task(id: page.revisionID) { await load() }
        .photosPicker(isPresented: $showPicker, selection: $items,
                      maxSelectionCount: replacementID == nil ? 30 : 1, matching: .images)
        .onChange(of: items) { _, selected in
            guard !selected.isEmpty else { return }
            let target = replacementID
            Task { await importItems(selected, replacing: target) }
        }
        .alert("照片操作失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("确定") { error = nil }
        } message: { Text(error ?? "") }
    }

    @MainActor private func load() async {
        loading = true
        defer { loading = false }
        do {
            let loaded = try await store.load(page.id)
            try Task.checkCancellation()
            session = DiaryEditorSession(document: loaded.document, images: loaded.images, store: store)
            pendingSave = false
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }

    @MainActor private func importItems(_ selected: [PhotosPickerItem], replacing id: UUID?) async {
        guard !readerBusy, let session else { return }
        readerBusy = true
        defer { readerBusy = false; items = [] }
        do {
            var data: [Data] = []
            for item in selected {
                guard let bytes = try await item.loadTransferable(type: Data.self) else { throw DiaryEditorError.invalidImage }
                data.append(bytes)
            }
            let success: Bool
            if let id { success = await session.importPhoto(data[0], replacing: id) }
            else { success = await session.importPhotos(data) }
            guard success else { error = session.errorMessage ?? "照片处理失败，请重试。"; return }
            await save(session)
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func delete(_ id: UUID) async {
        guard !readerBusy, let session else { return }
        readerBusy = true
        defer { readerBusy = false }
        session.removePhoto(id)
        await save(session)
    }

    @MainActor private func retrySave() async {
        guard !readerBusy, let session else { return }
        readerBusy = true
        defer { readerBusy = false }
        await save(session)
    }

    @MainActor private func save(_ session: DiaryEditorSession) async {
        // Close drains the debounced save and publishes one complete page revision.
        if await session.close() {
            pendingSave = false
            await onSaved()
        } else {
            pendingSave = true
            error = session.errorMessage ?? "保存失败，请点击重新保存。"
        }
    }
}
