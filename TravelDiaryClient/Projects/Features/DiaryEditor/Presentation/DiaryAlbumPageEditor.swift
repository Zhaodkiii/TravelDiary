import SwiftUI

struct DiaryAlbumPageEditor: View {
    let model: DiaryAlbumComposer
    let pageID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var page = DiaryAlbumPage()
    @State private var original = DiaryAlbumPage()
    @State private var selectingPhoto = false
    @State private var selectedSlot: UUID?
    @State private var initialized = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DiaryAlbumPagePreview(page: page, draft: model.draft, directory: model.directory)
                        .frame(maxHeight: 350).frame(maxWidth: .infinity)
                }
                Section {
                    Toggle("锁定页面", isOn: $page.locked)
                    Text("锁定后，换主题、重新排版和照片移动均跳过此页。需要调整时可随时解锁。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Group {
                    if page.spreadID != nil {
                        Section {
                            Text("这是连续跨页大图。使用整本页面菜单可成组移动、删除和锁定，保持左右画面连续。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("页面文字") {
                        TextField("标题（可留空）", text: $page.title, axis: .vertical)
                            .onChange(of: page.title) { _, text in if text.count > 60 { page.title = String(text.prefix(60)) } }
                        TextField("写下这一页的故事（最多 160 字）", text: $page.caption, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: page.caption) { _, text in if text.count > 160 { page.caption = String(text.prefix(160)) } }
                    }.disabled(page.spreadID != nil)
                    if (page.role == .photos || page.role == .blank) && page.spreadID == nil {
                        Section("页面版式") {
                            Picker("版式", selection: $page.layout) {
                                ForEach(DiaryAlbumLayout.allCases.filter { $0 != .fullBleed || (page.placements.count == 1 && page.title.isEmpty && page.caption.isEmpty) }) {
                                    Text($0.title).tag($0)
                                }
                            }
                            Text("版式只调整照片位置，保留文字和照片。单图满版适用于没有文字的单照片页。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if (page.role == .photos || page.role == .blank || page.role == .cover) && page.spreadID == nil {
                        Section("照片与取景") {
                            ForEach(page.placements) { slot in
                                if let photo = model.draft.photos.first(where: { $0.id == slot.photoID }) {
                                    HStack {
                                        DiaryAlbumPhotoThumbnail(photo: photo, directory: model.directory).frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 6))
                                        Button(selectedSlot == slot.id ? "收起取景调整" : "调整取景") { selectedSlot = selectedSlot == slot.id ? nil : slot.id }
                                        Spacer()
                                        Button("移除", systemImage: "minus.circle") { page.placements.removeAll { $0.id == slot.id } }.labelStyle(.iconOnly)
                                    }
                                    if selectedSlot == slot.id {
                                        cropSlider("放大", slot: slot.id, key: \.zoom, range: 1...3)
                                        cropSlider("左右取景", slot: slot.id, key: \.offsetX, range: -1...1)
                                        cropSlider("上下取景", slot: slot.id, key: \.offsetY, range: -1...1)
                                        Button("重置取景") {
                                            if let i = page.placements.firstIndex(where: { $0.id == slot.id }) {
                                                page.placements[i].zoom = 1; page.placements[i].offsetX = 0; page.placements[i].offsetY = 0
                                            }
                                        }
                                    }
                                }
                            }
                            if page.placements.count < (page.role == .cover ? 1 : 6) {
                                Button("从已选照片中添加", systemImage: "plus") { selectingPhoto = true }
                            }
                            Text("移除后照片回到待分配区。添加正文中已有的照片会将它移到本页；封面可以复用。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.disabled(page.locked)
            }
            .navigationTitle(page.role.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { save(); dismiss() } }
            }
            .sheet(isPresented: $selectingPhoto) {
                NavigationStack {
                    List(model.draft.photos.filter { photo in
                        !page.placements.contains { $0.photoID == photo.id }
                            && !model.draft.pages.contains { ($0.locked || $0.spreadID != nil) && page.role != .cover && $0.placements.contains { $0.photoID == photo.id } }
                    }) { photo in
                        Button {
                            page.placements.append(DiaryAlbumPlacement(photoID: photo.id))
                            selectingPhoto = false
                        } label: {
                            HStack {
                                DiaryAlbumPhotoThumbnail(photo: photo, directory: model.directory).frame(width: 56, height: 56)
                                Text(photo.date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "无拍摄时间")
                                Spacer()
                                if model.draft.unassigned.contains(where: { $0.id == photo.id }) { Text("待分配").font(.caption) }
                                else { Text(page.role == .cover ? "复用" : "移到本页").font(.caption) }
                            }
                        }
                    }
                    .navigationTitle("选择照片")
                    .toolbar { Button("取消") { selectingPhoto = false } }
                }
            }
            .onChange(of: page.title) { _, _ in normalizeLayout() }
            .onChange(of: page.caption) { _, _ in normalizeLayout() }
            .onChange(of: page.placements.count) { _, _ in normalizeLayout() }
            .onAppear {
                guard !initialized, let current = model.draft.pages.first(where: { $0.id == pageID }) else { return }
                page = current; original = current; initialized = true
            }
        }
        .interactiveDismissDisabled(page != original)
        .tint(DiaryLibraryStyle.accent)
    }
    private func normalizeLayout() {
        if page.layout == .fullBleed && (page.placements.count != 1 || !page.title.isEmpty || !page.caption.isEmpty) { page.layout = .adaptive }
    }
    private func save() {
        model.change { value in
            if let i = value.pages.firstIndex(where: { $0.id == pageID }) {
                let added = Set(page.placements.map(\.photoID)).subtracting(original.placements.map(\.photoID))
                if page.role != .cover {
                    for index in value.pages.indices where index != i && value.pages[index].role != .cover && !value.pages[index].locked {
                        value.pages[index].placements.removeAll { added.contains($0.photoID) }
                    }
                }
                value.pages[i] = page
                if let pair = page.spreadID {
                    for index in value.pages.indices where value.pages[index].spreadID == pair { value.pages[index].locked = page.locked }
                }
            }
        }
        original = page
    }
    private func cropSlider(_ title: String, slot: UUID, key: WritableKeyPath<DiaryAlbumPlacement, Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            Slider(value: Binding(get: { page.placements.first(where: { $0.id == slot })?[keyPath: key] ?? range.lowerBound },
                                  set: { value in if let i = page.placements.firstIndex(where: { $0.id == slot }) { page.placements[i][keyPath: key] = value } }), in: range)
                .accessibilityLabel(title)
        }
    }
}
