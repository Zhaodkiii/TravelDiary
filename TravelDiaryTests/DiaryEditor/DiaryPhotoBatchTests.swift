import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPhotoBatchTests {
    private func input(_ size: CGSize) -> DiaryPhotoBatchLayout.Input {
        DiaryPhotoBatchLayout.Input(photoSize: size,
            bounds: CGRect(x: -size.width * 0.08, y: -size.height * 0.10,
                           width: size.width * 1.2, height: size.height * 1.24))
    }
    private func data(_ size: CGSize, color: UIColor = .blue) throws -> Data {
        try #require(UIGraphicsImageRenderer(size: size).image { context in
            color.setFill(); context.fill(CGRect(origin: .zero, size: size))
        }.pngData())
    }
    private func session(_ document: DiaryDocument = DiaryDocument()) -> DiaryEditorSession {
        DiaryEditorSession(document: document, images: [:], store: DiaryDocumentStore(ownerID: "photo-batch-tests",
            baseDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
    }

    @Test func templateLayoutRegionIsOptionalAndExplicit() throws {
        let legacy = Data(#"{"id":"root","role":"canvas","referenceSize":{"width":1000,"height":1400},"layers":[]}"#.utf8)
        #expect(try JSONDecoder().decode(PresetContent.self, from: legacy).photoLayoutRegion == nil)
        let authored = Data(#"{"id":"root","role":"canvas","referenceSize":{"width":1000,"height":1400},"layers":[],"photoLayoutRegion":{"x":100,"y":300,"width":800,"height":900}}"#.utf8)
        let parsed = try JSONDecoder().decode(PresetContent.self, from: authored)
        #expect(parsed.photoLayoutRegion?.cg == CGRect(x: 100, y: 300, width: 800, height: 900))
    }

    @Test func renderedMixedPhotoBatchPreview() async throws {
        var document = DiaryDocument()
        let size = document.root.referenceSize
        document.objects[document.rootContentID]?.background = .paper
        document.objects[document.rootContentID]?.photoLayoutRegion = CGRect(x: size.width * 0.05, y: size.height * 0.21,
            width: size.width * 0.9, height: size.height * 0.69)
        let title = DiaryLayer(name: "标题", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: size.width * 0.09, y: size.height * 0.05), pivot: .zero),
            size: CGSize(width: size.width * 0.82, height: 120), text: "TRAVEL MEMORIES", fontSize: 80)
        document.objects[document.rootContentID]?.layers = [title]
        let session = session(document)
        func photo(_ size: CGSize, color: UIColor) throws -> Data {
            try #require(UIGraphicsImageRenderer(size: size).image { ctx in
                color.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
                UIColor.white.withAlphaComponent(0.6).setFill()
                ctx.fill(CGRect(x: 0, y: size.height * 0.65, width: size.width, height: size.height * 0.35))
                UIColor.systemYellow.setFill()
                UIBezierPath(ovalIn: CGRect(x: size.width * 0.15, y: size.height * 0.12, width: 45, height: 45)).fill()
            }.pngData())
        }
        #expect(await session.importPhotos(try [photo(CGSize(width: 200, height: 300), color: .systemTeal),
            photo(CGSize(width: 200, height: 300), color: .systemBlue), photo(CGSize(width: 360, height: 210), color: .systemOrange)]))
        let outputSize = CGSize(width: 800, height: 800 * size.height / size.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: outputSize, format: format).image { ctx in
            ctx.cgContext.scaleBy(x: outputSize.width / size.width, y: outputSize.height / size.height)
            DiaryPageRenderer.draw(session.document, images: session.images, in: ctx.cgContext, cacheObjects: false)
        }
        let bytes = try #require(image.pngData())
        Attachment.record(Array(bytes), named: "diary-photo-batch-qa.png")
        var doubleDocument = document
        doubleDocument.id = UUID()
        doubleDocument.objects[doubleDocument.rootContentID]?.photoLayoutRegion = nil
        let doubleSession = self.session(doubleDocument)
        #expect(await doubleSession.importPhotos(try [photo(CGSize(width: 360, height: 210), color: .systemTeal),
            photo(CGSize(width: 360, height: 210), color: .systemOrange)]))
        let preview = UIGraphicsImageRenderer(size: outputSize, format: format).image { ctx in
            ctx.cgContext.scaleBy(x: outputSize.width / size.width, y: outputSize.height / size.height)
            DiaryPageRenderer.draw(doubleSession.document, images: doubleSession.images, in: ctx.cgContext, cacheObjects: false)
        }
        Attachment.record(Array(try #require(preview.pngData())), named: "double-landscape-optimized.png")
        #expect(await doubleSession.close())
        #expect(await session.close())
    }

    @Test func doubleLandscapesUseEqualLargePhotoWidthsAndRealFrameGap() throws {
        let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let inputs = [input(CGSize(width: 800, height: 600)),
            DiaryPhotoBatchLayout.Input(photoSize: CGSize(width: 800, height: 600),
                bounds: CGRect(x: -30, y: -60, width: 880, height: 720))]
        let plan = try #require(DiaryPhotoBatchLayout.plan(inputs, canvas: canvas))
        let widths = zip(inputs, plan).map { $0.photoSize.width * $1.transform.scale }
        #expect(widths.allSatisfy { $0 >= 650 && $0 <= 750 })
        #expect(abs(widths[0] - widths[1]) < 0.001)
        #expect(abs(plan[1].bounds.minY - plan[0].bounds.maxY - 35) < 0.001)
        #expect(plan[0].bounds.minY < canvas.height * 0.2)
    }

    @Test func foregroundCanOverlapOnlyTheEdgeAndNeverThePhotoCenter() {
        let photo = CGRect(x: 100, y: 100, width: 600, height: 500)
        #expect(DiaryPhotoBatchLayout.allowsForeground(photo,
            foreground: [CGRect(x: 650, y: 150, width: 100, height: 100)]))
        #expect(!DiaryPhotoBatchLayout.allowsForeground(photo,
            foreground: [CGRect(x: 350, y: 300, width: 100, height: 50)]))
        #expect(!DiaryPhotoBatchLayout.allowsForeground(photo,
            foreground: [CGRect(x: 100, y: 100, width: 600, height: 69),
                         CGRect(x: 100, y: 531, width: 600, height: 69)]))
    }

    @Test func sceneryDoesNotShrinkPhotosAndSmallAccentsStayAboveThem() async throws {
        var document = DiaryDocument()
        let canvas = document.root.referenceSize
        let background = DiaryLayer(name: "纸张", kind: .sticker,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: canvas,
            semanticKind: .background)
        let scene = DiaryLayer(name: "整页树木插画", kind: .sticker,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: canvas,
            semanticKind: .illustration)
        let label = DiaryLayer(name: "小标签", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 30, y: 40), pivot: .zero),
            size: CGSize(width: 160, height: 60), text: "旅行")
        // A normal imported asset makes the preexisting images valid without adding library dependencies.
        let session = session()
        let assetData = try data(CGSize(width: 60, height: 60))
        let (asset, image) = try await session.store.importImage(assetData, documentID: document.id)
        document.assets[asset.id] = asset
        var paper = background, scenery = scene
        paper.assetID = asset.id; scenery.assetID = asset.id
        document.objects[document.rootContentID]?.layers = [paper, scenery, label]
        let editor = DiaryEditorSession(document: document, images: [asset.id: image], store: session.store)
        #expect(await editor.importPhotos(try [data(CGSize(width: 240, height: 180)), data(CGSize(width: 240, height: 180), color: .red)]))
        let added = editor.scopeLayers.filter { $0.photoBatchID != nil }
        #expect(added.count == 2)
        #expect(added.allSatisfy { $0.size.width * $0.transform.scale >= canvas.width * 0.50 })
        #expect(editor.scopeLayers.last?.id == label.id)
        #expect(editor.document.layer(scene.id) == scenery)
        try await editor.save()
        let reopened = try await editor.store.load(editor.document.id)
        #expect(reopened.document == editor.document)
        #expect(await editor.close())
        await session.cancelEditor()
    }

    @Test func frameSelectionMatchesOrientationAndStyleWithoutRepeatingAvailableChoices() throws {
        let sizes = [CGSize(width: 120, height: 180), CGSize(width: 120, height: 180), CGSize(width: 240, height: 140)]
        let chosen = DiaryPhotoFrameCatalog.select(for: sizes)
        #expect(Set(chosen.map(\.id)).count == 3)
        #expect(Set(chosen.compactMap { DiaryPhotoFrameCatalog.profiles[$0.id]?.accent }).count >= 2)
        #expect(chosen.map(\.id) == DiaryPhotoFrameCatalog.select(for: sizes).map(\.id))
        for (size, frame) in zip(sizes, chosen) {
            let profile = try #require(DiaryPhotoFrameCatalog.profiles[frame.id])
            #expect(profile.style == .lightPaper)
            #expect(size.width < size.height ? profile.aspectRatio < 0.9 : profile.aspectRatio > 1.1)
        }
        let squareFrames = DiaryPhotoFrameCatalog.select(for: Array(repeating: CGSize(width: 200, height: 200), count: 4))
        #expect(Set(squareFrames.map(\.id)).count == 4)
        let repeated = DiaryPhotoFrameCatalog.select(for: Array(repeating: sizes[0], count: 30))
        let count = DiaryPhotoFrameCatalog.items.filter {
            DiaryPhotoFrameCatalog.profiles[$0.id]?.style == .lightPaper && DiaryPhotoFrameCatalog.profiles[$0.id]!.aspectRatio < 0.9
        }.count
        #expect(Set(repeated.prefix(count).map(\.id)).count == count)
        #expect(repeated.dropFirst(count).allSatisfy { DiaryPhotoFrameCatalog.profiles[$0.id]?.decoration == 0 })
    }

    @Test func layoutsRespectMarginsGapsRotationAndPhotoRatios() throws {
        for canvas in [CGRect(x: 0, y: 0, width: 1000, height: 1400), CGRect(x: 0, y: 0, width: 1400, height: 1000)] {
            for count in 1...12 {
                let inputs = (0..<count).map { input($0 % 3 == 2 ? CGSize(width: 800, height: 500) : CGSize(width: 500, height: 800)) }
                let plan = try #require(DiaryPhotoBatchLayout.plan(inputs, canvas: canvas))
                let safe = canvas.insetBy(dx: canvas.width * 0.05, dy: canvas.height * 0.05)
                for (index, placement) in plan.enumerated() {
                    #expect(safe.contains(placement.bounds))
                    #expect(abs(placement.transform.rotationDegrees) <= 2)
                    #expect(placement.transform.stretch == nil)
                    let actual = inputs[index].bounds.applying(placement.transform.matrix)
                    #expect(abs(actual.minX - placement.bounds.minX) < 0.001)
                    #expect(abs(actual.minY - placement.bounds.minY) < 0.001)
                    for other in plan.dropFirst(index + 1) {
                        #expect(!placement.bounds.insetBy(dx: -min(canvas.width, canvas.height) * 0.034,
                                                        dy: -min(canvas.width, canvas.height) * 0.034).intersects(other.bounds))
                    }
                }
            }
        }
        let portraits = [input(CGSize(width: 500, height: 800)), input(CGSize(width: 500, height: 800))]
        let mixed = try #require(DiaryPhotoBatchLayout.plan(portraits + [input(CGSize(width: 800, height: 500))],
            canvas: CGRect(x: 0, y: 0, width: 1000, height: 1400)))
        #expect(mixed[0].bounds.maxY < mixed[2].bounds.minY)
        #expect(mixed[1].bounds.maxY < mixed[2].bounds.minY)
        #expect(mixed[0].bounds.maxX < mixed[1].bounds.minX)
    }

    @Test func avoidsObstaclesAndUsesTemplateRegionOrRefusesWithoutCropping() throws {
        let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let region = CGRect(x: 80, y: 300, width: 840, height: 900)
        let obstacle = CGRect(x: 80, y: 300, width: 320, height: 400)
        let inputs = [input(CGSize(width: 500, height: 800)), input(CGSize(width: 500, height: 800))]
        let plan = try #require(DiaryPhotoBatchLayout.plan(inputs, canvas: canvas, region: region, obstacles: [obstacle]))
        #expect(plan.allSatisfy { region.contains($0.bounds) && !$0.bounds.intersects(obstacle) })
        #expect(DiaryPhotoBatchLayout.plan(inputs, canvas: canvas, obstacles: [canvas]) == nil)
    }

    @Test func batchIsOneUndoAndPersistsExactFramesAndTransforms() async throws {
        let session = session()
        let bytes = try [data(CGSize(width: 120, height: 180)), data(CGSize(width: 120, height: 180), color: .red), data(CGSize(width: 240, height: 140))]
        #expect(await session.importPhotos(bytes))
        #expect(session.scopeLayers.count == 3)
        #expect(session.undoStack.count == 1)
        let batch = try #require(session.photoBatches.first)
        #expect(batch.count == 3)
        let inserted = session.scopeLayers
        #expect(Set(inserted.compactMap(\.photoBatchID)).count == 1)
        let frames = inserted.compactMap { layer in layer.contentID.flatMap { session.document.objects[$0]?.layers.first(where: \.isPhotoFrame) } }
        #expect(Set(frames.compactMap(\.photoFrameCatalogID)).count == 3)
        try await session.save()
        let loaded = try await session.store.load(session.document.id)
        #expect(loaded.document == session.document)
        session.undo()
        #expect(session.scopeLayers.isEmpty)
        session.redo()
        #expect(session.scopeLayers == inserted)
        #expect(await session.close())
    }

    @Test func fullPageStacksNewBatchesWithinMargins() throws {
        let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1400)
        let safe = canvas.insetBy(dx: 50, dy: 70)
        for count in [1, 3, 6, 7, 30] {
            let inputs = (0..<count).map { input($0 % 2 == 0 ? CGSize(width: 500, height: 800) : CGSize(width: 800, height: 500)) }
            let placements = try #require(DiaryPhotoBatchLayout.plan(inputs, canvas: canvas,
                obstacles: [canvas], foreground: [canvas], allowOverlap: true))
            #expect(placements.count == count)
            for (index, placement) in placements.enumerated() {
                #expect(placement.overlaysExistingContent)
                #expect(safe.contains(placement.bounds))
                #expect(placement.transform.scale >= 0.05)
                #expect(placement.bounds == inputs[index].bounds.applying(placement.transform.matrix))
            }
        }
    }

    @Test func chosenFramesAndNoFrameCommitAsOneBatch() async throws {
        let editor = session()
        let frame = try #require(DiaryPhotoFrameCatalog.items.first)
        #expect(await editor.importPhotos(try [data(CGSize(width: 120, height: 180)),
            data(CGSize(width: 180, height: 120), color: .red)], frames: [frame, nil]))
        #expect(editor.managedPhotos.count == 2)
        #expect(editor.undoStack.count == 1)
        let photos = editor.managedPhotos
        let first = try #require(editor.document.objects[photos[0].ownerID])
        let second = try #require(editor.document.objects[photos[1].ownerID])
        #expect(first.layers.first(where: \.isPhotoFrame)?.photoFrameCatalogID == frame.id)
        #expect(!second.layers.contains { $0.isPhotoFrame })
        #expect(photos.allSatisfy { $0.layer.photoFrameIsManual == true })
        try await editor.save()
        #expect(try await editor.store.load(editor.document.id).document == editor.document)
        editor.undo()
        #expect(editor.managedPhotos.isEmpty)
        editor.redo()
        #expect(editor.managedPhotos.count == 2)
        #expect(await editor.close())
    }

    @Test func fullPageImportKeepsExistingContentAndAddsOnTop() async throws {
        let editor = session()
        let (asset, image) = try await editor.store.importImage(try data(CGSize(width: 120, height: 180)), documentID: editor.document.id)
        var original = editor.document
        original.assets[asset.id] = asset
        var photo = DiaryLayer.photo(asset: asset, center: .zero)
        photo.size = original.root.referenceSize
        photo.transform = DiaryTransform(position: .zero, pivot: .zero)
        original.objects[original.rootContentID]?.layers = [photo]
        let crowded = DiaryEditorSession(document: original, images: [asset.id: image], store: editor.store)
        #expect(await crowded.importPhotos(try [data(CGSize(width: 120, height: 180), color: .red)]))
        #expect(crowded.document.layer(photo.id) == photo)
        #expect(crowded.scopeLayers.first?.id == photo.id)
        #expect(crowded.scopeLayers.last?.photoBatchID != nil)
        try await crowded.save()
        #expect(try await crowded.store.load(crowded.document.id).document == crowded.document)
        crowded.undo()
        #expect(crowded.document.root.layers == original.root.layers)
        #expect(crowded.document.assets == original.assets)
        #expect(crowded.document.objects.count == original.objects.count)
        await crowded.cancelEditor()
        await editor.cancelEditor()
    }

    @Test func manualFramesAndRemovalSurviveRearrangementAndExistingLayersStayFixed() async throws {
        var document = DiaryDocument()
        let text = DiaryLayer(name: "标题", kind: .text,
            transform: DiaryTransform(position: CGPoint(x: 100, y: 50), pivot: .zero),
            size: CGSize(width: 400, height: 80), text: "旅行日记", locked: true)
        document.objects[document.rootContentID]?.layers.append(text)
        let session = session(document)
        #expect(await session.importPhotos(try [data(CGSize(width: 120, height: 180)), data(CGSize(width: 120, height: 180), color: .red)]))
        let photos = session.managedPhotos
        let batch = try #require(session.photoBatches.first)
        #expect(await session.applyPhotoFrame(DiaryPhotoFrameCatalog.items[1], to: photos[0].id))
        #expect(await session.applyPhotoFrame(nil, to: photos[1].id))
        let children = session.scopeLayers.compactMap(\.contentID).compactMap { session.document.objects[$0] }
        #expect(session.rearrangePhotoBatch(batch.id))
        #expect(session.document.layer(text.id) == text)
        #expect(session.scopeLayers.compactMap(\.contentID).compactMap { session.document.objects[$0] } == children)
        #expect(session.document.layer(photos[0].id)?.photoFrameIsManual == true)
        #expect(session.document.layer(photos[1].id)?.photoFrameIsManual == true)
        try await session.save()
        let loaded = try await session.store.load(session.document.id)
        #expect(loaded.document == session.document)
        #expect(await session.close())
    }

    @Test func failedBatchDoesNotPartiallyInsertOrChangeUndoHistory() async throws {
        let session = session()
        let initial = session.document
        #expect(!(await session.importPhotos(try [data(CGSize(width: 120, height: 180)), Data([0, 1, 2])])))
        #expect(session.document == initial)
        #expect(session.undoStack.isEmpty)
        #expect(session.images.isEmpty)
        await session.cancelEditor()
        var blocked = DiaryDocument()
        blocked.objects[blocked.rootContentID]?.photoLayoutRegion = CGRect(x: 100, y: 100, width: 10, height: 10)
        let crowded = self.session(blocked)
        #expect(await crowded.importPhotos(try [data(CGSize(width: 120, height: 180))]))
        #expect(crowded.managedPhotos.count == 1)
        #expect(crowded.document.root.photoLayoutRegion == blocked.root.photoLayoutRegion)
        #expect(crowded.errorMessage == nil)
        #expect(crowded.undoStack.count == 1)
        crowded.undo()
        #expect(crowded.document.root.layers == blocked.root.layers)
        #expect(crowded.document.assets == blocked.assets)
        #expect(crowded.document.root.photoLayoutRegion == blocked.root.photoLayoutRegion)
        await crowded.cancelEditor()
    }
}
