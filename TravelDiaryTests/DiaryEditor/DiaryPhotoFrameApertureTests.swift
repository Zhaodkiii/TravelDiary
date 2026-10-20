import Testing
import UIKit
@testable import TravelDiary

@MainActor struct DiaryPhotoFrameApertureTests {
    private func raster(_ image: UIImage, size: CGSize? = nil) throws -> (Int, Int, [UInt8]) {
        let w = Int(size?.width ?? image.size.width), h = Int(size?.height ?? image.size.height)
        var pixels = [UInt8](repeating: 0, count: w*h*4)
        try pixels.withUnsafeMutableBytes { bytes in
            let ctx = try #require(CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx); image.draw(in: CGRect(x: 0,y: 0,width: w,height: h)); UIGraphicsPopContext()
        }
        return (w,h,pixels)
    }
    private func solid() -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: 120,height: 180), format: f).image { _ in
            UIColor.red.setFill(); UIRectFill(CGRect(x: 0,y: 0,width: 120,height: 180))
        }
    }
    @Test func allBundledFramesHaveAnEnclosedAperture() throws {
        for item in DiaryPhotoFrameCatalog.items {
            let source = try #require(item.image)
            let aperture = try #require(DiaryPhotoFrameAperture.detect(source, opening: item.opening), "\(item.id) \(item.title)")
            #expect(aperture.slot.isValid)
            let (w,h,mask) = try raster(aperture.mask)
            #expect((0..<w).allSatisfy { mask[$0*4+3] == 0 && mask[((h-1)*w+$0)*4+3] == 0 })
            #expect((0..<h).allSatisfy { mask[($0*w)*4+3] == 0 && mask[($0*w+w-1)*4+3] == 0 })
            #expect(DiaryPhotoFrameAperture.detect(source, opening: item.opening) === aperture)
        }
    }

    @Test func curledFrameCoversWholeOpeningAndKeepsExteriorTransparent() throws {
        let item = DiaryPhotoFrameCatalog.items[0]
        let source = try #require(item.image)
        let aperture = try #require(DiaryPhotoFrameAperture.detect(source, opening: item.opening))
        let output = try #require(DiaryPhotoSlotRenderer.image(solid(), mask: aperture.mask, slot: aperture.slot,
            size: aperture.mask.size, crop: DiaryCrop()))
        let (w,h,mask) = try raster(aperture.mask)
        let (_,_,photo) = try raster(output, size: CGSize(width: w,height: h))
        var missing = 0, leaks = 0, covered = 0
        for i in stride(from: 3,to: mask.count,by: 4) {
            if mask[i] > 240 { covered += 1; if photo[i] < 220 { missing += 1 } }
            if mask[i] == 0 && photo[i] > 5 { leaks += 1 }
        }
        #expect(leaks == 0)
        #expect(Double(missing)/Double(covered) < 0.005)
    }

    @Test func savedPhotoAdaptsToFrameAndCacheInvalidatesOnChange() throws {
        let item = DiaryPhotoFrameCatalog.items[0]
        let image = solid(), frameImage = try #require(item.image)
        let asset = DiaryAsset(id: UUID(),path: "photo.png",pixelSize: image.size)
        let frameAsset = DiaryAsset(id: UUID(),path: "frame.png",pixelSize: frameImage.size)
        var photo = DiaryLayer.photo(asset: asset,center: .zero)
        photo.transform = DiaryTransform(position: .zero,pivot: .zero)
        let frame = DiaryEditorSession.photoFrame(item,asset: frameAsset,photo: photo)
        var doc = DiaryDocument()
        doc.assets = [asset.id: asset,frameAsset.id: frameAsset]
        doc.objects[doc.rootContentID]?.layers = [photo,frame]
        let images = [asset.id: image,frameAsset.id: frameImage]
        let cache = DiaryCanvasRenderCache()
        cache.synchronize(document: doc,images: images,contentID: doc.rootContentID)
        cache.prepareResolution(pointsToPixels: 1)
        let entry = try #require(cache.ordered.first)
        #expect(cache.rasterize(entry))
        #expect(entry.rect == DiaryPageRenderer.bounds(photo,document: doc,siblings: [photo,frame]))
        let format = UIGraphicsImageRendererFormat(); format.scale = entry.requestedScale; format.opaque = false; format.preferredRange = .standard
        let direct = UIGraphicsImageRenderer(size: entry.rect.size,format: format).image { renderer in
            renderer.cgContext.translateBy(x: -entry.rect.minX,y: -entry.rect.minY)
            DiaryPageRenderer.drawHitLayer(photo,document: doc,siblings: [photo,frame],images: images,in: renderer.cgContext)
        }
        #expect(try raster(#require(entry.image)).2 == raster(direct).2)
        // 留下一张可检查的合成图，底部斜边必须连续覆盖。
        let previewFormat = UIGraphicsImageRendererFormat(); previewFormat.scale = min(1, 600/entry.rect.width); previewFormat.opaque = false
        let preview = UIGraphicsImageRenderer(size: entry.rect.size, format: previewFormat).image { renderer in
            renderer.cgContext.translateBy(x: -entry.rect.minX,y: -entry.rect.minY)
            DiaryPageRenderer.drawHitLayer(photo,document: doc,siblings: [photo,frame],images: images,in: renderer.cgContext)
            DiaryPageRenderer.drawHitLayer(frame,document: doc,siblings: [photo,frame],images: images,in: renderer.cgContext)
        }
        let previewURL = FileManager.default.temporaryDirectory.appendingPathComponent("photo-frame-aperture-preview.png")
        try preview.pngData()?.write(to: previewURL)
        print("FRAME-APERTURE-PREVIEW \(previewURL.path)")
        let reopened = try JSONDecoder().decode(DiaryDocument.self,from: JSONEncoder().encode(doc))
        #expect(reopened == doc)
        doc.update(frame.id) { $0.visible = false }
        cache.synchronize(document: doc,images: images,contentID: doc.rootContentID)
        #expect(cache.ordered[0] !== entry)
        #expect(cache.ordered[0].rect == CGRect(origin: .zero,size: photo.size))
    }
}
