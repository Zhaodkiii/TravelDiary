import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryPhotoSlotTests {
    private let full = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
    private func image(_ size: CGSize = CGSize(width: 200, height: 240), draw: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: size, format: f).image { draw($0.cgContext) }
    }
    private func pixels(_ image: UIImage) throws -> [UInt8] {
        let cg = try #require(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: cg.width*cg.height*4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)); return true
        }
        #expect(success)
        return bytes
    }
    private func original() throws -> UIImage {
        let package = try #require(BundleDiaryPresetProvider(root: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DiaryPresets.bundle")).catalog().books.first { $0.id == "food-new-year-wishes-with-you" })
        let key = "019856fbedca858123ccefc87a5117153b8f4f425188a01c9e8565c715f04de7"
        let asset = try #require(package.manifest.assetTable[key])
        return try #require(UIImage(data: Data(contentsOf: package.url(asset.path))))
    }

    @Test func suppliedWebPBlackReplacementPreservesAlphaAndDoesNotLeak() throws {
        let source = try original(), maskID = UUID()
        let slot = try #require(DiaryPhotoSlotDetector.detect(source, maskAssetID: maskID))
        #expect(slot.isValid)
        #expect(slot.corners[0].y != slot.corners[1].y)
        let black = image(source.size) { ctx in ctx.setFillColor(UIColor.black.cgColor); ctx.fill(CGRect(origin: .zero, size: source.size)) }
        let result = try #require(DiaryPhotoSlotRenderer.image(black, mask: source, slot: slot, size: source.size, crop: DiaryCrop()))
        let before = try pixels(source), after = try pixels(result)
        var missing = 0, opaque = 0, leaked = 0
        for i in stride(from: 3, to: before.count, by: 4) {
            if before[i] > 240 { opaque += 1; if after[i] < 220 { missing += 1 } }
            if before[i] == 0 && after[i] > 5 { leaked += 1 }
        }
        #expect(leaked == 0)
        #expect(Double(missing)/Double(opaque) < 0.005)
    }

    @Test func detectsPerspectiveButRejectsCircleAndOpaqueImage() throws {
        let polygon = image { ctx in
            ctx.move(to: CGPoint(x: 30, y: 20)); ctx.addLine(to: CGPoint(x: 185, y: 50))
            ctx.addLine(to: CGPoint(x: 160, y: 225)); ctx.addLine(to: CGPoint(x: 10, y: 200)); ctx.closePath()
            ctx.setFillColor(UIColor.red.cgColor); ctx.fillPath()
        }
        let slot = try #require(DiaryPhotoSlotDetector.detect(polygon, maskAssetID: UUID()))
        #expect(abs(slot.corners[0].x-0.15) < 0.025)
        #expect(abs(slot.corners[1].y-50.0/240) < 0.025)
        let circle = image { ctx in ctx.fillEllipse(in: CGRect(x: 20, y: 30, width: 160, height: 160)) }
        #expect(DiaryPhotoSlotDetector.detect(circle, maskAssetID: UUID()) == nil)
        let opaque = image { $0.fill(CGRect(x: 0, y: 0, width: 200, height: 240)) }
        #expect(DiaryPhotoSlotDetector.detect(opaque, maskAssetID: UUID()) == nil)
    }

    @Test func mappingPreservesOrientationAndFillModes() throws {
        let source = image(CGSize(width: 200, height: 100)) { ctx in
            ctx.setFillColor(UIColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            ctx.setFillColor(UIColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 30, height: 100))
            ctx.setFillColor(UIColor.green.cgColor); ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 30))
        }
        var slot = DiaryPhotoSlot(corners: full, maskAssetID: nil)
        let cover = try #require(DiaryPhotoSlotRenderer.image(source, mask: nil, slot: slot, size: CGSize(width: 100, height: 100), crop: DiaryCrop()))
        slot.fill = .stretch
        let stretch = try #require(DiaryPhotoSlotRenderer.image(source, mask: nil, slot: slot, size: CGSize(width: 100, height: 100), crop: DiaryCrop()))
        let a = try pixels(cover), b = try pixels(stretch)
        #expect(a[(50*100+5)*4+2] > 200)
        #expect(b[(50*100+5)*4] > 200)
        #expect(b[(5*100+75)*4+1] > 100)
        #expect(b[(95*100+75)*4+2] > 200)
    }

    @Test func replacementUndoSaveAndReopenKeepSlotAndMask() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryDocumentStore(ownerID: "slot-test", baseDirectory: folder)
        var document = DiaryDocument()
        let source = try original()
        let (old, originalImage) = try await store.importImage(try #require(source.pngData()), documentID: document.id)
        document.assets[old.id] = old
        let layer = DiaryLayer(name: "照片", kind: .photo, transform: DiaryTransform(position: .zero, pivot: .zero), size: source.size, assetID: old.id)
        document.objects[document.rootContentID]?.layers = [layer]
        let slot = try await store.photoSlot(for: layer, document: document)
        #expect(slot.maskAssetID == old.id)
        let newImage = image { $0.fill(CGRect(x: 0, y: 0, width: 200, height: 240)) }
        let (new, preview) = try await store.importImage(try #require(newImage.pngData()), documentID: document.id)
        let session = DiaryEditorSession(document: document, images: [old.id: originalImage], store: store)
        #expect(session.applyPhotoReplacements([(layer.id, new, preview, nil)], expected: document, slots: [layer.id: slot]))
        #expect(session.document.layer(layer.id)?.size == layer.size)
        session.undo()
        #expect(session.document.layer(layer.id) == layer)
        #expect(session.document.assets == document.assets)
        session.redo()
        var replaced = session.document
        replaced.replacePhoto(layer.id, with: new)
        #expect(replaced.layer(layer.id)?.photoSlot == slot)
        try await store.save(replaced)
        let reopened = try await store.load(document.id)
        #expect(reopened.document.layer(layer.id)?.photoSlot == slot)
        #expect(reopened.images[old.id] != nil)
        #expect(try await store.photoSlot(for: #require(reopened.document.layer(layer.id)), document: reopened.document) == slot)
        try DiaryDocumentStore.validate(reopened.document)
    }

    @Test func cropAndSingleReplacementKeepSlotGeometry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = DiaryDocumentStore(ownerID: "slot-crop-test", baseDirectory: folder)
        var document = DiaryDocument()
        let source = try original()
        let (asset, preview) = try await store.importImage(try #require(source.pngData()), documentID: document.id)
        document.assets[asset.id] = asset
        let layer = DiaryLayer(name: "照片", kind: .photo, transform: DiaryTransform(position: CGPoint(x: 10, y: 20), pivot: CGPoint(x: 20, y: 30)), size: source.size, assetID: asset.id)
        document.objects[document.rootContentID]?.layers = [layer]
        let session = DiaryEditorSession(document: document, images: [asset.id: preview], store: store)
        let new = image { $0.fill(CGRect(x: 0, y: 0, width: 200, height: 240)) }
        #expect(await session.importPhoto(try #require(new.pngData()), replacing: layer.id))
        let replacement = try #require(session.document.layer(layer.id))
        let slot = try #require(replacement.photoSlot)
        #expect(slot.maskAssetID == asset.id)
        let parameters = ImageCropParameters(outputSize: CGSize(width: 100, height: 100), translation: .zero, rotation: 0, scale: 1, flipped: false)
        #expect(await session.commitPhotoCrop(layerID: layer.id, image: new, parameters: parameters))
        let cropped = try #require(session.document.layer(layer.id))
        #expect(cropped.photoSlot == slot)
        #expect(cropped.size == layer.size)
        #expect(cropped.transform == layer.transform)
        #expect(cropped.photoFill == true)
        session.select(layer.id); session.restoreOriginalPhoto()
        #expect(session.document.layer(layer.id)?.assetID == replacement.assetID)
        #expect(session.document.layer(layer.id)?.photoSlot == slot)
    }

    @Test func actualTemplateImportInfersSlotBeforeReplacing() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let package = try #require(BundleDiaryPresetProvider(root: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/DiaryPresets.bundle")).catalog().books.first { $0.id == "food-new-year-wishes-with-you" })
        let sourceKey = "019856fbedca858123ccefc87a5117153b8f4f425188a01c9e8565c715f04de7"
        let page = try #require(package.pages.first { page in
            let doc = try package.instantiate(page, bookID: UUID(), targetSize: page.size.cg,
                assetIDs: Dictionary(uniqueKeysWithValues: package.manifest.assetTable.keys.map { ($0, UUID()) }))
            return doc.replaceablePhotos().contains { $0.name == "照片_亲吻与陪伴" }
        })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("new.png")
        let black = image { $0.fill(CGRect(x: 0, y: 0, width: 200, height: 240)) }
        try #require(black.pngData()).write(to: file)
        let library = DiaryDocumentStore(ownerID: "slot-import-test", baseDirectory: folder)
        let book = try await library.importPreset(package, pageIDs: [page.id], title: "槽位验证", operationID: UUID(), replacementPhotos: [file], replacementFill: .stretch)
        let store = DiaryDocumentStore(ownerID: "slot-import-test", baseDirectory: folder, bookID: book.id)
        let loaded = try await store.load(book.pages[0].id)
        let layer = try #require(loaded.document.replaceablePhotos().first)
        let slot = try #require(layer.photoSlot)
        #expect(slot.fill == .stretch)
        let mask = try #require(slot.maskAssetID.flatMap { loaded.images[$0] })
        #expect(mask.size.width > 96)
        #expect(layer.assetID != slot.maskAssetID)
        #expect(package.manifest.assetTable[sourceKey] != nil)
        let format = UIGraphicsImageRendererFormat(); format.scale = 0.4; format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: loaded.document.root.referenceSize, format: format).image { renderer in
            DiaryPageRenderer.draw(loaded.document, images: loaded.images, in: renderer.cgContext, cacheObjects: false)
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("photo-slot-template-replacement.png")
        try rendered.pngData()?.write(to: output)
        print("PHOTO-SLOT-PREVIEW \(output.path)")
    }

    @Test func canvasAndDirectRenderingAgreeAndMaskChangesInvalidateCache() throws {
        let maskID = UUID(), photoID = UUID()
        let mask = image { ctx in
            ctx.translateBy(x: 100, y: 120); ctx.rotate(by: 0.1)
            ctx.fill(CGRect(x: -70, y: -90, width: 140, height: 180))
        }
        let source = image { ctx in ctx.setFillColor(UIColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 240)) }
        let slot = try #require(DiaryPhotoSlotDetector.detect(mask, maskAssetID: maskID))
        var document = DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize = mask.size
        document.assets[maskID] = DiaryAsset(id: maskID, path: "assets/mask.png", pixelSize: mask.size)
        document.assets[photoID] = DiaryAsset(id: photoID, path: "assets/photo.png", pixelSize: source.size)
        var layer = DiaryLayer(name: "照片", kind: .photo, transform: DiaryTransform(position: .zero, pivot: .zero), size: mask.size, assetID: photoID)
        layer.photoSlot = slot; layer.photoFill = true
        document.objects[document.rootContentID]?.layers = [layer]
        var images = [maskID: mask, photoID: source]
        let cache = DiaryCanvasRenderCache()
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        cache.prepareResolution(pointsToPixels: 1)
        let entry = try #require(cache.ordered.first)
        #expect(cache.rasterize(entry))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false; format.preferredRange = .standard
        let direct = UIGraphicsImageRenderer(size: mask.size, format: format).image { renderer in
            DiaryPageRenderer.draw(document, images: images, in: renderer.cgContext, cacheObjects: false)
        }
        #expect(try pixels(#require(entry.image)) == pixels(direct))
        images[maskID] = image { $0.fill(CGRect(x: 40, y: 40, width: 100, height: 100)) }
        cache.synchronize(document: document, images: images, contentID: document.rootContentID)
        #expect(cache.ordered[0] !== entry)
        #expect(cache.ordered[0].needsRaster)
        var invalid = document
        invalid.update(layer.id) { $0.photoSlot?.corners.reverse() }
        #expect(throws: DiaryEditorError.self) { try DiaryDocumentStore.validate(invalid) }
    }

    @Test func perspectiveMapsFourSourceCornersWithoutFlipping() throws {
        let source = image(CGSize(width: 100, height: 100)) { ctx in
            for (rect, color) in [(CGRect(x: 0, y: 0, width: 50, height: 50), UIColor.red),
                (CGRect(x: 50, y: 0, width: 50, height: 50), UIColor.green),
                (CGRect(x: 50, y: 50, width: 50, height: 50), UIColor.blue),
                (CGRect(x: 0, y: 50, width: 50, height: 50), UIColor.white)] {
                ctx.setFillColor(color.cgColor); ctx.fill(rect)
            }
        }
        let slot = DiaryPhotoSlot(corners: [CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.9, y: 0.25), CGPoint(x: 0.8, y: 0.9), CGPoint(x: 0.1, y: 0.75)], maskAssetID: nil, fill: .stretch)
        let result = try #require(DiaryPhotoSlotRenderer.image(source, mask: nil, slot: slot, size: CGSize(width: 100, height: 100), crop: DiaryCrop()))
        let bytes = try pixels(result)
        #expect(bytes[(25*100+30)*4] > 200)
        #expect(bytes[(35*100+75)*4+1] > 100)
        #expect(bytes[(75*100+70)*4+2] > 200)
        #expect(bytes[(65*100+25)*4] > 200)
        #expect(bytes[(5*100+5)*4+3] == 0)
    }
}
