import Testing
import UIKit
import SwiftUI
@testable import TravelDiary

@MainActor
struct DiaryFreeTransformTests {
    private func fixture() -> (DiaryEditorSession, UUID) {
        var document=DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize=CGSize(width:240,height:320)
        let format=UIGraphicsImageRendererFormat(); format.scale=1; format.opaque=false
        let image=UIGraphicsImageRenderer(size:CGSize(width:120,height:160),format:format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x:0,y:0,width:120,height:80))
            UIColor.blue.setFill(); ctx.fill(CGRect(x:0,y:80,width:120,height:80))
        }
        let asset=DiaryAsset(id:UUID(),path:"assets/test.png",pixelSize:image.size)
        document.assets[asset.id]=asset
        let photo=DiaryLayer(name:"测试照片",kind:.photo,
            transform:DiaryTransform(position:CGPoint(x:55,y:65),pivot:.zero),size:image.size,assetID:asset.id)
        let frame=DiaryLayer(name:"相框",kind:.frame,transform:photo.transform,size:photo.size,
            frameTargetID:photo.id,frameColor:.white,frameWidth:8)
        document.objects[document.rootContentID]?.layers=[photo,frame]
        let session=DiaryEditorSession(document:document,images:[asset.id:image],
            store:DiaryDocumentStore(ownerID:"free-transform-tests",
                baseDirectory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        session.select(photo.id)
        return (session,photo.id)
    }
    private func warp() -> DiaryQuadWarp {
        DiaryQuadWarp(reference:CGRect(x:0,y:0,width:120,height:160),
            topLeft:CGPoint(x:0.15,y:0.05), topRight:CGPoint(x:0.85,y:0.10),
            bottomRight:CGPoint(x:1.05,y:1),bottomLeft:CGPoint(x:-0.10,y:0.95))
    }
    private func close(_ a: CGPoint,_ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y)<0.00001 }

    @Test func projectionMapsAllCornersAndInvertsInteriorPoints() {
        let w=warp(), r=w.reference
        #expect(w.isValid)
        for (source,normalized) in zip(r.diaryCorners,w.corners) {
            let expected=CGPoint(x:r.minX+normalized.x*r.width,y:r.minY+normalized.y*r.height)
            #expect(close(w.projection.point(source),expected))
        }
        var t=DiaryTransform(position:CGPoint(x:80,y:90),pivot:CGPoint(x:20,y:30),scale:1.4,rotationDegrees:23)
        t.warp=w
        for p in [CGPoint(x:15,y:20),CGPoint(x:90,y:140),CGPoint(x:60,y:80)] {
            #expect(close(t.projection.inverse.point(t.projection.point(p)),p))
        }
        let offset=DiaryQuadWarp(reference:CGRect(x:-30,y:15,width:200,height:170))
        #expect(close(offset.projection.point(CGPoint(x:50,y:65)),CGPoint(x:50,y:65)))
    }

    @Test func modesHaveDistinctConstraintsAndRejectFoldedQuads() throws {
        let w=DiaryQuadWarp(reference:CGRect(x:0,y:0,width:120,height:160))
        let delta=CGPoint(x:0.15,y:0.05)
        let free=try #require(DiaryTransformMode.free.moving(w,handle:0,delta:delta))
        #expect(free.topRight==w.topRight && free.bottomLeft==w.bottomLeft)
        let perspective=try #require(DiaryTransformMode.perspective.moving(w,handle:0,delta:delta))
        #expect(abs(perspective.topLeft.x+perspective.topRight.x-1)<0.00001)
        #expect(perspective.topLeft.y==perspective.topRight.y)
        let vertical=try #require(DiaryTransformMode.perspective.moving(w,handle:0,delta:CGPoint(x:0.01,y:0.15)))
        #expect(abs(vertical.topLeft.y+vertical.bottomLeft.y-1)<0.00001)
        #expect(vertical.topRight==w.topRight && vertical.bottomRight==w.bottomRight)
        let skew=try #require(DiaryTransformMode.skew.moving(w,handle:4,delta:delta))
        #expect(skew.topLeft.y==0 && skew.topRight.y==0)
        #expect(skew.bottomLeft==w.bottomLeft && skew.bottomRight==w.bottomRight)
        let stretch=try #require(DiaryTransformMode.stretch.moving(w,handle:5,delta:delta))
        #expect(stretch.topLeft==w.topLeft && stretch.bottomLeft==w.bottomLeft)
        #expect(abs(stretch.topRight.x-1.15)<0.00001 && stretch.topRight.y==0)
        #expect(DiaryTransformMode.free.moving(w,handle:0,delta:CGPoint(x:2,y:2))==nil)
        #expect(DiaryTransformMode.stretch.moving(w,handle:7,delta:CGPoint(x:2,y:0))==nil)
    }

    @Test func draftCancelResetCommitAndUndoPreserveOriginalContent() throws {
        let (session,id)=fixture(), before=session.document
        session.beginFreeTransform()
        var layer=try #require(session.transformDraft?.layer)
        layer.transform.warp=warp()
        session.previewFreeTransform(layer)
        #expect(session.document==before && session.undoStack.isEmpty)
        session.setTransformMode(.perspective)
        #expect(session.transformDraft?.layer.transform.warp==warp())
        session.resetFreeTransform()
        #expect(session.transformDraft?.layer.transform==before.layer(id)?.transform)
        session.previewFreeTransform(layer)
        session.finishFreeTransform(commit:false)
        #expect(session.document==before && session.undoStack.isEmpty)
        session.beginFreeTransform(); session.previewFreeTransform(layer); session.finishFreeTransform(commit:true)
        #expect(session.undoStack.count==1)
        #expect(session.selected?.transform.warp==warp())
        #expect(session.document.assets==before.assets)
        session.undo()
        #expect(session.selected?.transform==before.layer(id)?.transform)
        session.redo()
        #expect(session.selected?.transform.warp==warp())
        let decoded=try JSONDecoder().decode(DiaryDocument.self,from:JSONEncoder().encode(session.document))
        #expect(decoded.layer(id)?.transform.warp==warp())
        _ = try DiaryDocumentStore.validate(decoded)
        // Existing JSON without the optional field remains readable.
        let old=Data("{\"position\":[0,0],\"pivot\":[0,0],\"scale\":1,\"rotationDegrees\":0}".utf8)
        #expect(try JSONDecoder().decode(DiaryTransform.self,from:old).warp==nil)
    }

    @Test func lockedAndFrameTargetsDoNotOpenTransformTool() throws {
        let (session,id)=fixture()
        #expect(session.contextActions.contains(.transform))
        session.toggleLock(id); session.beginFreeTransform()
        #expect(session.transformDraft==nil)
        session.select(session.scopeLayers[1].id); session.beginFreeTransform()
        #expect(session.transformDraft==nil)
        #expect(!session.contextActions.contains(.transform))
    }

    private func render(_ session:DiaryEditorSession) -> UIImage {
        let format=UIGraphicsImageRendererFormat(); format.scale=1; format.opaque=false
        return UIGraphicsImageRenderer(size:session.content.referenceSize,format:format).image { ctx in
            DiaryPageRenderer.draw(session.document,images:session.images,in:ctx.cgContext,cacheObjects:false)
        }
    }
    private func rgba(_ image:UIImage,_ point:CGPoint) -> [UInt8] {
        let cg=image.cgImage!, width=cg.width, height=cg.height
        var bytes=[UInt8](repeating:0,count:width*height*4)
        bytes.withUnsafeMutableBytes { raw in
            let ctx=CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg,in:CGRect(x:0,y:0,width:width,height:height))
        }
        let x=max(0,min(width-1,Int(point.x))), y=max(0,min(height-1,Int(point.y)))
        return Array(bytes[(y*width+x)*4..<(y*width+x)*4+4])
    }

    @Test func exportUsesProjectionAndKeepsImageOrientationAndFrame() throws {
        let (session,_)=fixture()
        session.beginFreeTransform()
        var layer=try #require(session.transformDraft?.layer); layer.transform.warp=warp()
        session.previewFreeTransform(layer); session.finishFreeTransform(commit:true)
        let image=render(session), map=layer.transform.projection
        let top=rgba(image,map.point(CGPoint(x:60,y:35)))
        let bottom=rgba(image,map.point(CGPoint(x:60,y:125)))
        #expect(top[0]>230 && top[2]<20 && top[3]>230)
        #expect(bottom[2]>230 && bottom[0]<20 && bottom[3]>230)
        let frame=rgba(image,map.point(CGPoint(x:-4,y:70)))
        #expect(frame[0]>230 && frame[1]>230 && frame[2]>230 && frame[3]>230)
        #expect(rgba(image,CGPoint(x:5,y:5))[3]==0)
        let bounds=DiaryPageRenderer.objectBounds(session.content,document:session.document)
        #expect(bounds.contains(map.point(CGPoint(x:120,y:160))))
    }

    @Test func retainedPreviewSharesProjectionAndDoesNotRerasterizeWhileDragging() throws {
        let (session,id)=fixture()
        let surface=DiaryCanvasSurface(frame:CGRect(x:0,y:0,width:375,height:500)); surface.session=session; surface.refresh()
        for entry in surface.renderCache.ordered { surface.renderCache.rasterize(entry) }
        let count=surface.renderCache.rasterCount
        session.beginFreeTransform()
        var layer=try #require(session.transformDraft?.layer); layer.transform.warp=warp()
        session.previewFreeTransform(layer); surface.refresh()
        #expect(surface.renderCache.rasterCount==count)
        let artwork=try #require(surface.subviews.first)
        let retained=try #require(artwork.layer.sublayers?.first { $0.name==id.uuidString })
        let m=retained.transform, p=CGPoint(x:30,y:60), w=m.m14*p.x+m.m24*p.y+m.m44
        let mapped=CGPoint(x:(m.m11*p.x+m.m21*p.y+m.m41)/w,y:(m.m12*p.x+m.m22*p.y+m.m42)/w)
        #expect(close(mapped,layer.transform.projection.point(p)))
        let entry=try #require(surface.renderCache.entries[id])
        #expect(surface.renderCache.contains(layer.transform.projection.inverse.point(mapped),entry:entry))
        session.finishFreeTransform(commit:false); surface.refresh()
        #expect(abs(retained.transform.m14)<1e-8 && abs(retained.transform.m24)<1e-8)
    }

    @Test func cornerGesturesPreviewCommitAndCancelWithoutChangingDocument() throws {
        let (session,_)=fixture(), before=session.document
        let surface=DiaryCanvasSurface(frame:CGRect(x:0,y:0,width:375,height:500))
        surface.compactViewport=true; surface.session=session; surface.refresh()
        session.beginFreeTransform()
        let scale=CGFloat(375-16)/240
        let origin=CGPoint(x:55*scale+8,y:65*scale+8)
        let end=CGPoint(x:origin.x+18,y:origin.y+12)
        surface.updateFreeTransformGesture(state:.began,location:origin,translation:.zero)
        surface.updateFreeTransformGesture(state:.changed,location:end,translation:CGPoint(x:18,y:12))
        #expect(session.document==before && session.undoStack.isEmpty)
        surface.updateFreeTransformGesture(state:.ended,location:end,translation:CGPoint(x:18,y:12))
        let warp=try #require(session.transformDraft?.layer.transform.warp)
        #expect(abs(warp.topLeft.x-18/scale/120)<0.00001)
        #expect(abs(warp.topLeft.y-12/scale/160)<0.00001)
        #expect(session.document==before)
        // Cancel a second drag: retain the first draft, without committing either to the document.
        let point=session.transformDraft!.layer.transform.projection.point(.zero)
        let screen=CGPoint(x:point.x*scale+8,y:point.y*scale+8)
        surface.updateFreeTransformGesture(state:.began,location:screen,translation:.zero)
        surface.updateFreeTransformGesture(state:.changed,location:CGPoint(x:screen.x+10,y:screen.y),translation:CGPoint(x:10,y:0))
        surface.updateFreeTransformGesture(state:.cancelled,location:screen,translation:.zero)
        #expect(session.transformDraft?.layer.transform.warp==warp)
        session.finishFreeTransform(commit:true)
        #expect(session.undoStack.count==1 && session.selected?.transform.warp==warp)
    }

    @Test func nestedWarpPrintMatchesPageRendering() async throws {
        let (session,_)=fixture()
        var document=session.document
        var child=DiaryObjectContent(role:.canvas,referenceSize:document.root.referenceSize,layers:document.root.layers)
        child.layers[0].transform.warp=warp()
        document.objects[child.id]=child
        let ref=DiaryPageRenderer.objectBounds(child,document:document)
        var transform=DiaryTransform(position:CGPoint(x:2,y:3),pivot:.zero)
        transform.warp=DiaryQuadWarp(reference:ref,topLeft:CGPoint(x:0.1,y:0),topRight:CGPoint(x:0.9,y:0),
                                    bottomRight:CGPoint(x:1,y:1),bottomLeft:CGPoint(x:0,y:1))
        let group=DiaryLayer(name:"组合",kind:.object,transform:transform,size:child.referenceSize,contentID:child.id)
        document.objects[document.rootContentID]?.layers=[group]
        let nested=DiaryEditorSession(document:document,images:session.images,store:session.store)
        let expected=render(nested)
        let context=try #require(CGContext(data:nil,width:240,height:320,bitsPerComponent:8,bytesPerRow:240*4,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x:0,y:320); context.scaleBy(x:1,y:-1)
        try await DiaryPageRenderer.drawForPrinting(document,images:session.images,in:context)
        let actual=UIImage(cgImage:try #require(context.makeImage()))
        for point in [CGPoint(x:110,y:115),CGPoint(x:110,y:185),CGPoint(x:10,y:10)] {
            let a=rgba(actual,point), b=rgba(expected,point)
            #expect(zip(a,b).allSatisfy { abs(Int($0)-Int($1))<=2 })
        }
    }

    @Test func saveReopenPreservesWarpAndExportResources() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let store=DiaryDocumentStore(ownerID:"transform-persistence",baseDirectory:root)
        var document=DiaryDocument()
        document.objects[document.rootContentID]?.referenceSize=CGSize(width:240,height:320)
        let session=DiaryEditorSession(document:document,images:[:],store:store)
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let image=UIGraphicsImageRenderer(size:CGSize(width:120,height:160),format:format).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x:0,y:0,width:120,height:160))
        }
        #expect(await session.importPhoto(try #require(image.pngData()),asSticker:true))
        session.beginFreeTransform()
        var layer=try #require(session.transformDraft?.layer)
        var w=warp(); w.reference=try #require(session.transformDraft?.reference)
        layer.transform.warp=w; session.previewFreeTransform(layer); session.finishFreeTransform(commit:true)
        try await session.save()
        let loaded=try await store.load(session.document.id)
        #expect(loaded.document.layer(layer.id)?.transform.warp==w)
        let images=try await store.exportImages(for:loaded.document)
        #expect(!images.isEmpty)
        let reopened=DiaryEditorSession(document:loaded.document,images:images,store:store)
        reopened.select(layer.id); reopened.beginFreeTransform()
        #expect(reopened.transformDraft?.layer.transform.warp==w)
        #expect(render(reopened).cgImage != nil)
        var invalid=loaded.document
        invalid.update(layer.id) { $0.transform.warp?.topLeft=CGPoint(x:3,y:3) }
        #expect(throws:DiaryEditorError.self) { try DiaryDocumentStore.validate(invalid) }
    }

    @Test func compositedPreviewUsesSameWarpAsExport() throws {
        let (session,id)=fixture()
        var document=session.document
        document.objects[document.rootContentID]?.background = .white
        document.update(id) { $0.transform.warp=warp(); $0.blendMode = .multiply }
        let cache=DiaryCanvasRenderCache()
        cache.synchronize(document:document,images:session.images,contentID:document.rootContentID)
        cache.prepareResolution(pointsToPixels:1)
        for entry in cache.ordered { cache.rasterize(entry) }
        let view=DiaryCanvasArtworkView(frame:CGRect(x:0,y:0,width:240,height:320))
        view.cache=cache; view.composited=true; view.contentScaleFactor=1
        view.setNeedsDisplay(); view.layer.displayIfNeeded()
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let image=UIGraphicsImageRenderer(size:view.bounds.size,format:format).image { ctx in
            view.layer.render(in:ctx.cgContext)
        }
        let transformed=try #require(document.layer(id))
        let top=rgba(image,transformed.transform.projection.point(CGPoint(x:60,y:35)))
        let bottom=rgba(image,transformed.transform.projection.point(CGPoint(x:60,y:125)))
        #expect(top[0]>230 && top[2]<20)
        #expect(bottom[2]>230 && bottom[0]<20)
    }

    @Test func transformPanelVisualVerification() async throws {
        let (session,_)=fixture(); session.beginFreeTransform()
        var layer=try #require(session.transformDraft?.layer); layer.transform.warp=warp(); session.previewFreeTransform(layer)
        session.setTransformMode(.perspective)
        let host=UIHostingController(rootView:VStack(spacing:0) {
            DiaryCanvasView(session:session,compactViewport:true).frame(width:375,height:500)
            DiaryEditorToolPanel(title:"自由变形",onBack:{},onDone:{},backAccessibilityLabel:"取消变形") {
                DiaryTransformToolContent(session:session)
            }
        }.frame(width:375).background(DiaryLibraryStyle.background).ignoresSafeArea())
        let size=host.sizeThatFits(in:CGSize(width:375,height:900))
        let window=UIWindow(frame:CGRect(origin:.zero,size:size)); window.rootViewController=host; window.makeKeyAndVisible()
        defer { window.isHidden=true }
        host.view.frame=window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for:.milliseconds(500))
        let image=UIGraphicsImageRenderer(size:size).image { _ in host.view.drawHierarchy(in:host.view.bounds,afterScreenUpdates:true) }
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("diary-free-transform-qa.png")
        try #require(image.pngData()).write(to:url)
        print("Transform visual QA: \(url.path)")
    }
}
