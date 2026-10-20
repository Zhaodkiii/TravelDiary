import SwiftUI
import PhotosUI
import UIKit

/// Compact background tools leave the artwork visible while trying colors.
struct DiaryBackgroundToolContent: View {
    @ObservedObject var session: DiaryEditorSession
    @State private var customColor: Color
    @State private var photoItem: PhotosPickerItem?
    @State private var libraries: [CloudMaterialLibrary] = []
    @State private var selectedLibraryID: String?
    @State private var items: [CloudMaterial] = []
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var libraryError: String?
    @State private var itemError: String?
    @State private var selectedMaterialID: String?
    @State private var progress: Double = 0
    @State private var addition: Task<Void, Never>?
    @State private var showCustomColor = false
    @State private var importing = false

    private static let swatches: [(String, DiaryColor)] = [
        ("白色", .white), ("奶油", .paper), ("暖黄", .yellow), ("浅粉", .pink), ("薄荷", .mint),
        ("橙色", DiaryColor(red: 1, green: 0.59, blue: 0.30)),
        ("红色", DiaryColor(red: 0.91, green: 0.24, blue: 0.23)),
        ("雾蓝", DiaryColor(red: 0.73, green: 0.83, blue: 0.90)),
        ("薰衣草", DiaryColor(red: 0.83, green: 0.78, blue: 0.91)),
        ("棕色", .brown), ("灰色", DiaryColor(red: 0.60, green: 0.60, blue: 0.60)),
        ("黑色", DiaryColor(red: 0.08, green: 0.08, blue: 0.08))
    ]

    init(session: DiaryEditorSession) {
        self.session = session
        _customColor = State(initialValue: Color(uiColor: DiaryPageRenderer.color(session.content.background ?? .white)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("相册", systemImage: "photo")
                }
                Divider().frame(height: 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        collectionTab("纯色", id: nil)
                        ForEach(libraries) { library in
                            collectionTab(library.title, id: library.id)
                        }
                        if libraryError != nil {
                            Button("重试加载合集") { Task { await loadLibraries() } }
                        }
                    }.padding(.vertical, 8)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline).frame(minHeight: 36)
            .foregroundStyle(DiaryLibraryStyle.secondary)
            .padding(.horizontal, 20)

            if selectedLibraryID == nil {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(68)), GridItem(.fixed(68))], spacing: 12) {
                        customColorTile
                        swatchTile("透明背景", color: nil)
                        ForEach(Self.swatches, id: \.0) { name, color in
                            swatchTile(name, color: color)
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 4)
                }
                .frame(height: 156)
            } else {
                collectionContent
            }
            HStack(spacing: 6) {
                if importing { ProgressView().controlSize(.mini) }
                Text(importing ? "正在更换背景 \(Int(progress * 100))%…" : "点选替换背景 · 返回或完成保留修改")
            }
            .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
            .padding(.horizontal, 20)
        }
        .disabled(importing || session.busy)
        .sheet(isPresented: $showCustomColor) {
            DiaryBackgroundColorPicker(color: Binding(
                get: { customColor },
                set: { customColor = $0; selectedMaterialID = nil; session.previewBackground(DiaryColor($0)) }
            ), isPresented: $showCustomColor)
        }
        .task { await loadLibraries() }
        .task(id: selectedLibraryID) {
            items = []; nextPage = nil; itemError = nil
            if selectedLibraryID != nil { await loadItems(more: false) }
        }
        .task(id: photoItem) {
            guard let item = photoItem else { return }
            importing = true; progress = 0
            defer { importing = false; photoItem = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw DiaryEditorError.invalidImage
                }
                try Task.checkCancellation()
                session.finishInteraction()
                if await session.importMaterialBackground(data, name: "相册背景") { selectedMaterialID = nil }
            } catch is CancellationError { }
            catch { session.errorMessage = error.localizedDescription }
        }
        .onDisappear { addition?.cancel(); session.finishInteraction() }
    }

    private func collectionTab(_ title: String, id: String?) -> some View {
        let selected = selectedLibraryID == id
        return Button { selectedLibraryID = id } label: {
            Text(title).fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                .fixedSize()
                .overlay(alignment: .bottom) {
                    if selected {
                        Capsule().fill(DiaryLibraryStyle.accent).frame(height: 2).offset(y: 7)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var collectionContent: some View {
        Group {
            if let itemError {
                HStack {
                    Text(itemError).font(.caption).lineLimit(2)
                    Button("重试") { Task { await loadItems(more: false) } }
                }.padding(.horizontal, 20)
            } else if loading && items.isEmpty {
                ProgressView("正在加载背景…").frame(maxWidth: .infinity)
            } else if items.isEmpty {
                Text("该合集暂无背景").font(.subheadline)
                    .foregroundStyle(DiaryLibraryStyle.secondary).frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(68)), GridItem(.fixed(68))], spacing: 12) {
                        ForEach(items) { item in
                            Button { addition = Task { await apply(item) } } label: {
                                MaterialThumbnail(item: item)
                                    .frame(width: 68, height: 68)
                                    .background(DiaryLibraryStyle.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                    .overlay {
                                        if selectedMaterialID == item.id {
                                            RoundedRectangle(cornerRadius: 13).strokeBorder(DiaryLibraryStyle.accent, lineWidth: 2.5)
                                            Image(systemName: "checkmark").font(.caption.bold())
                                                .foregroundStyle(.white).padding(6)
                                                .background(DiaryLibraryStyle.accent, in: Circle())
                                        }
                                    }
                            }
                            .buttonStyle(.plain).accessibilityLabel(item.name)
                            .accessibilityAddTraits(selectedMaterialID == item.id ? [.isSelected] : [])
                        }
                        if nextPage != nil {
                            Button("更多") { Task { await loadItems(more: true) } }
                                .frame(width: 68, height: 68).disabled(loading)
                        }
                    }.padding(.horizontal, 20).padding(.vertical, 4)
                }
            }
        }.frame(height: 156)
    }

    private func loadLibraries() async {
        do {
            let result: [CloudMaterialLibrary] = try await MaterialCatalogRepository.shared.request("libraries/?type=background")
            try Task.checkCancellation()
            libraries = result; libraryError = nil
        } catch { if !Task.isCancelled { libraryError = error.localizedDescription } }
    }

    private func loadItems(more: Bool) async {
        guard let library = libraries.first(where: { $0.id == selectedLibraryID }) else { return }
        loading = true
        defer { if selectedLibraryID == library.id { loading = false } }
        do {
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "version", value: String(library.version)),
                                URLQueryItem(name: "after", value: String(more ? nextPage ?? 0 : 0))]
            let page: MaterialPage = try await MaterialCatalogRepository.shared.request(
                "libraries/\(library.id)/items/?" + (query.percentEncodedQuery ?? ""))
            try Task.checkCancellation()
            guard selectedLibraryID == library.id else { return }
            items = more ? items + page.items : page.items; nextPage = page.next; itemError = nil
        } catch {
            if !Task.isCancelled && selectedLibraryID == library.id { itemError = error.localizedDescription }
        }
    }

    private func apply(_ item: CloudMaterial) async {
        guard !importing else { return }
        importing = true; progress = 0
        defer { importing = false }
        let owner = MaterialCatalogRepository.shared.owner
        do {
            let data = try await PresetDownloadManager.shared.materialData(item) { progress = $0 }
            try Task.checkCancellation()
            guard MaterialCatalogRepository.shared.owner == owner else { return }
            session.finishInteraction()
            if await session.importMaterialBackground(data, name: item.name) { selectedMaterialID = item.id }
        } catch { if !Task.isCancelled { itemError = error.localizedDescription } }
    }

    private var hasBackgroundImage: Bool {
        var visited = Set<UUID>()
        func visit(_ id: UUID) -> Bool {
            guard visited.insert(id).inserted, let content = session.document.objects[id] else { return false }
            return content.layers.contains { layer in
                layer.semanticKind == .background || layer.isLibraryBackground == true
                    || layer.contentID.map { visit($0) } == true
            }
        }
        return visit(session.contentID)
    }

    private var customColorTile: some View {
        let selected = !hasBackgroundImage && selectedMaterialID == nil && session.content.background != nil
            && !Self.swatches.contains { $0.1 == session.content.background }
        return Button {
            customColor = Color(uiColor: DiaryPageRenderer.color(session.content.background ?? .white))
            showCustomColor = true
        } label: {
            VStack(spacing: 5) {
                Circle()
                    .strokeBorder(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                                  center: .center), lineWidth: 5)
                    .frame(width: 25, height: 25)
                Text("自定义").font(.caption)
            }
            .foregroundStyle(DiaryLibraryStyle.ink)
            .frame(width: 68, height: 68)
            .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line,
                                  lineWidth: selected ? 2.5 : 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("自定义背景颜色")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func swatchTile(_ name: String, color: DiaryColor?) -> some View {
        let selected = !hasBackgroundImage && selectedMaterialID == nil && session.content.background == color
        return Button {
            selectedMaterialID = nil
            session.previewBackground(color)
        } label: {
            ZStack {
                if let color {
                    Color(uiColor: DiaryPageRenderer.color(color))
                } else {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                        for row in 0..<9 {
                            for column in 0..<9 where (row + column).isMultiple(of: 2) {
                                context.fill(Path(CGRect(x: CGFloat(column) * 8, y: CGFloat(row) * 8,
                                                         width: 8, height: 8)),
                                             with: .color(Color(white: 0.87)))
                            }
                        }
                    }
                }
                if selected {
                    Image(systemName: "checkmark").font(.caption.bold())
                        .foregroundStyle(.white).padding(6)
                        .background(DiaryLibraryStyle.accent, in: Circle())
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line,
                                  lineWidth: selected ? 2.5 : 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Present the system palette itself, without an intermediate settings sheet.
private struct DiaryBackgroundColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.title = "背景颜色"
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(color)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
        let selected = UIColor(color)
        if !picker.selectedColor.isEqual(selected) { picker.selectedColor = selected }
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: DiaryBackgroundColorPicker
        init(_ parent: DiaryBackgroundColorPicker) { self.parent = parent }

        func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
            parent.color = Color(uiColor: viewController.selectedColor)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            parent.isPresented = false
        }
    }
}
