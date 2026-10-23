import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@Suite(.serialized)
@MainActor struct DiaryAlbumTests {
    private func draft(count: Int = 50) -> DiaryAlbumDraft {
        var value = DiaryAlbumDraft()
        value.photos = (0..<count).map { index in
            DiaryAlbumPhoto(filename: "photo.image", pixelSize: CGSize(width: index.isMultiple(of: 2) ? 1200 : 800, height: 900),
                date: Date(timeIntervalSince1970: Double(1_700_000_000 + (index / 8) * 86400)), selectionOrder: index, fingerprint: "\(index)")
        }
        return value
    }
    @Test func fiftyPhotosProduceOnlyUsefulPagesWithoutLoss() {
        for theme in DiaryAlbumTheme.allCases {
            for density in DiaryAlbumDensity.allCases {
                var value = draft(); value.theme = theme; value.density = density; value.generate()
                #expect(value.size == DiaryPagePreset.b5.rawValue)
                #expect(!value.pages.contains { $0.role == .chapter || $0.role == .ending })
                let body = value.pages.filter { $0.role != .cover }
                #expect(body.allSatisfy { !$0.placements.isEmpty && $0.placements.count <= density.capacity })
                #expect(body.flatMap { $0.placements.map(\.photoID) }.count == 50)
                #expect(Set(body.flatMap { $0.placements.map(\.photoID) }) == Set(value.photos.map(\.id)))
                #expect(value.unassigned.isEmpty)
                #expect(body.contains { $0.dateLabel != nil })
            }
        }
    }
    @Test func lockedPagesAndEditedContentSurviveThemeAndDensity() {
        var value = draft(); value.generate()
        value.pages[1].locked = true
        value.pages[2].caption = "这是我的旅行故事"
        value.pages[2].placements[0].zoom = 1.5
        let locked = value.pages[1], editedID = value.pages[2].id, placement = value.pages[2].placements[0]
        value.applyTheme(.zine); value.applyPalette("2"); value.repaginate(.compact)
        #expect(value.pages.first { $0.id == locked.id } == locked)
        #expect(value.pages.first { $0.id == editedID }?.caption == "这是我的旅行故事")
        #expect(value.pages.first { $0.id == editedID }?.placements.first == placement)
        #expect(value.unassigned.isEmpty)
    }
    @Test func moveSwapDeleteAndUndoPreservePhotoOwnership() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let composer = DiaryAlbumComposer(ownerID: "test", baseDirectory: directory)
        composer.draft = draft(); composer.change { $0.generate() }
        let before = composer.draft
        let source = before.pages[1], destination = before.pages[2]
        let a = try #require(source.placements.first?.photoID), b = try #require(destination.placements.first?.photoID)
        composer.change { $0.movePhoto(a, to: destination.id, replacing: b, sourcePageID: source.id) }
        #expect(composer.draft.pages[1].placements[0].photoID == b)
        #expect(composer.draft.pages[2].placements[0].photoID == a)
        composer.undo(); #expect(composer.draft == before)
        composer.redo(); #expect(composer.draft.pages[2].placements[0].photoID == a)
        composer.change { $0.pages.removeAll { $0.id == source.id } }
        #expect(!composer.draft.unassigned.isEmpty)
        let restored = DiaryAlbumComposer(ownerID: "test", baseDirectory: directory)
        #expect(restored.draft == composer.draft)
    }
    @Test func cropFramesStayInsideCanvasAndSpreadIsContinuous() throws {
        var value = draft(count: 8)
        for theme in DiaryAlbumTheme.allCases {
            for count in 1...6 {
                for layout in DiaryAlbumLayout.allCases {
                    let page = DiaryAlbumPage(theme: theme, layout: layout, placements: value.photos.prefix(count).map { DiaryAlbumPlacement(photoID: $0.id) })
                    let frames = DiaryAlbumGeometry.frames(page: page, photos: value.photos)
                    #expect(frames.count == count)
                    #expect(frames.allSatisfy { $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1.001 && $0.maxY <= 1.001 && $0.width > 0 && $0.height > 0 })
                }
            }
        }
        value.generate(); let photo = value.photos[0]; value.makeSpread(photoID: photo.id)
        let pair = value.pages.filter { $0.spreadID != nil }
        #expect(pair.count == 2)
        let asset = DiaryAsset(id: photo.id, path: "photo.image", pixelSize: photo.pixelSize)
        let docs = pair.map { DiaryAlbumDocumentBuilder.document(page: $0, draft: value, assets: [photo.id: asset]) }
        let layers = try docs.map { doc in try #require(doc.objects.values.flatMap(\.layers).first { $0.kind == .photo }) }
        let a = layers[0].crop.imageRect(source: photo.pixelSize, frame: layers[0].size)
        let b = layers[1].crop.imageRect(source: photo.pixelSize, frame: layers[1].size)
        #expect(abs(a.minX - b.minX - value.pageSize.width) < 0.001)
    }
    @Test func publishIsAtomicAndRetryDoesNotDuplicateBook() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiaryDocumentStore(ownerID: "album", baseDirectory: directory)
        var value = draft(count: 3); value.generate()
        await #expect(throws: (any Error).self) { try await store.createAlbum(value, photoDirectory: directory) }
        #expect(try await store.listBooks().isEmpty)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90)).image { ctx in UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 90)) }
        try #require(image.pngData()).write(to: directory.appendingPathComponent("photo.image"))
        let cancelled = DiaryPresetCancellation(); cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await store.createAlbum(value, photoDirectory: directory, cancellation: cancelled) }
        #expect(try await store.listBooks().isEmpty)
        let result = try await store.createAlbum(value, photoDirectory: directory)
        let again = try await store.createAlbum(value, photoDirectory: directory)
        #expect(result.id == again.id)
        #expect(try await store.listBooks().count == 1)
        let reader = DiaryDocumentStore(ownerID: "album", baseDirectory: directory, bookID: result.id)
        for entry in result.pages {
            let loaded = try await reader.load(entry.id)
            #expect(loaded.document.root.referenceSize == DiaryPagePreset.b5.size)
            #expect(!loaded.images.isEmpty)
            try DiaryDocumentStore.validate(loaded.document)
        }
    }
    @Test func blankBookHasEditableFirstPageAndSelectedPaper() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryDocumentStore(ownerID: "blank", baseDirectory: folder)
        var value = DiaryAlbumDraft(); value.pages = [DiaryAlbumPage(role: .blank, theme: .film, paletteID: "1")]
        let book = try await store.createAlbum(value, photoDirectory: folder)
        let page = try #require(book.pages.first)
        let reader = DiaryDocumentStore(ownerID: "blank", baseDirectory: folder, bookID: book.id)
        let loaded = try await reader.load(page.id)
        #expect(loaded.document.root.background == DiaryAlbumTheme.film.palette("1").paper)
        #expect(loaded.document.root.layers.isEmpty)
        #expect(book.coverPageID == page.id)
    }
    @Test func renderThemeContactSheet() throws {
        let themes = DiaryAlbumTheme.allCases
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let sheet = UIGraphicsImageRenderer(size: CGSize(width: 1500, height: 1100), format: format).image { ctx in
            UIColor(white: 0.85, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1500, height: 1100))
            for (i, theme) in themes.enumerated() {
                let images = DiaryAlbumSampleRenderer.render(theme: theme, paletteID: theme == .zine ? "2" : nil)
                let x = CGFloat(i % 3) * 500, y = CGFloat(i / 3) * 550
                (theme.title as NSString).draw(at: CGPoint(x: x + 20, y: y + 15), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 23), .foregroundColor: UIColor.black])
                images[0].draw(in: CGRect(x: x + 20, y: y + 60, width: 200, height: 284))
                for n in 1...4 { images[n].draw(in: CGRect(x: x + 235 + CGFloat((n - 1) % 2) * 120, y: y + 60 + CGFloat((n - 1) / 2) * 184, width: 118, height: 168)) }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("album-theme-contact-sheet.png")
        try #require(sheet.pngData()).write(to: url)
        Attachment.record(Array(try #require(sheet.pngData())), named: "album-theme-contact-sheet.png")
    }
    @Test func captureCreationScreens() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = DiaryAlbumComposer(ownerID: "screen-test", baseDirectory: folder)
        try await capture(AnyView(NavigationStack {
            DiaryAlbumDesignPicker(model: model).padding(20).navigationTitle("选择相册设计").navigationBarTitleDisplayMode(.inline)
        }), name: "album-design-picker.png")
        try await capture(AnyView(NavigationStack { DiaryAlbumComposerScreen(model: model) { _ in } }), name: "album-add-photos.png")
        model.draft = draft(count: 12)
        try FileManager.default.createDirectory(at: model.directory, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200)).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
            UIColor.systemOrange.setFill(); ctx.fill(CGRect(x: 100, y: 40, width: 70, height: 70))
        }
        try #require(image.pngData()).write(to: model.directory.appendingPathComponent("photo.image"))
        model.draft.generate()
        try await capture(AnyView(NavigationStack { DiaryAlbumComposerScreen(model: model) { _ in } }), name: "album-overview.png")
    }
    @Test func everyThemePaletteAndLayoutProducesValidEditableDocuments() throws {
        var value = draft(count: 6)
        let assets = Dictionary(uniqueKeysWithValues: value.photos.map { photo in
            (photo.id, DiaryAsset(id: photo.id, path: "assets/\(photo.id).image", pixelSize: photo.pixelSize))
        })
        for theme in DiaryAlbumTheme.allCases {
            for palette in theme.palettes {
                for count in 1...6 {
                    for layout in DiaryAlbumLayout.allCases {
                        let page = DiaryAlbumPage(title: "旅行故事", caption: "把照片留在这里", theme: theme, layout: layout,
                            paletteID: palette.id, placements: value.photos.prefix(count).map { DiaryAlbumPlacement(photoID: $0.id) })
                        // 第三页触发 Zine 强调色装饰，封面触发杂志分隔线。
                        value.pages = [DiaryAlbumPage(role: .blank), DiaryAlbumPage(role: .blank), page]
                        let document = DiaryAlbumDocumentBuilder.document(page: page, draft: value, assets: assets)
                        try DiaryDocumentStore.validate(document)
                    }
                }
                let cover = DiaryAlbumPage(role: .cover, title: "山海之间", theme: theme, paletteID: palette.id,
                    placements: [DiaryAlbumPlacement(photoID: value.photos[0].id)])
                try DiaryDocumentStore.validate(DiaryAlbumDocumentBuilder.document(page: cover, draft: value, assets: assets))
            }
        }
    }
    @Test func allDecoratedThemesCanPublishAndReopenWithoutLosingDraftPhotos() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 90)).image { ctx in
            UIColor.systemGreen.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 90))
        }
        try #require(image.pngData()).write(to: folder.appendingPathComponent("photo.image"))
        let store = DiaryDocumentStore(ownerID: "theme-save", baseDirectory: folder)
        for theme in DiaryAlbumTheme.allCases {
            var value = draft(count: 12); value.theme = theme; value.paletteID = "2"; value.generate()
            let book = try await store.createAlbum(value, photoDirectory: folder)
            let reader = DiaryDocumentStore(ownerID: "theme-save", baseDirectory: folder, bookID: book.id)
            #expect(book.pages.count == value.pages.count)
            for page in book.pages {
                let loaded = try await reader.load(page.id)
                try DiaryDocumentStore.validate(loaded.document)
                #expect(!loaded.images.isEmpty)
            }
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("photo.image").path))
        }
    }
    @Test func captureCompactCreationPanel() async throws {
        try await capture(AnyView(Color.gray.opacity(0.15).sheet(isPresented: .constant(true)) {
            DiaryCreateBookSheet(ownerID: "album-panel-preview") { _ in }
        }), name: "album-creation-panel.png", selectPhotos: true)
    }
    private func capture(_ view: AnyView, name: String, selectPhotos: Bool = false) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(900))
        if selectPhotos {
            func find(_ view: UIView) -> UISegmentedControl? {
                if let control = view as? UISegmentedControl, control.numberOfSegments == 3 { return control }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let picker = try #require(find(window))
            picker.selectedSegmentIndex = 1
            picker.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(700))
        }
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        Attachment.record(Array(try #require(image.pngData())), named: name)
    }

}
