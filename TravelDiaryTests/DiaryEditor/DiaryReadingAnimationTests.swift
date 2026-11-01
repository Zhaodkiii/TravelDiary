import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct DiaryReadingAnimationTests {
    private func layer(_ kind: DiaryLayer.Kind, semantic: DiaryLayerSemanticKind? = nil) -> DiaryLayer {
        var value = DiaryLayer(name: "test", kind: kind,
            transform: DiaryTransform(position: .zero, pivot: .zero), size: CGSize(width: 100, height: 100))
        value.semanticKind = semantic
        return value
    }
    @Test func backgroundRemainsWhileAllForegroundIsHidden() {
        var doc = DiaryDocument()
        let background = layer(.sticker, semantic: .background)
        var text = layer(.text); text.text = "旅行🙂"
        let sticker = layer(.sticker)
        doc.objects[doc.rootContentID]?.layers = [background, text, sticker]
        let plan = DiaryReadingPlan(document: doc)
        let start = plan.presentation(at: -1)
        #expect(start.states[background.id] == nil)
        #expect(start.states[text.id]?.opacity == 0)
        #expect(start.states[sticker.id]?.opacity == 0)
        #expect(!start.showsInk)
        let end = plan.presentation(at: plan.duration)
        #expect(end.states[text.id]?.characters == 3)
        #expect(end.states[sticker.id]?.opacity == 1)
        #expect(end.showsInk)
        #expect(doc.root.layers == [background, text, sticker])
    }
    @Test func frameSharesPhotoScheduleAndOriginalStackIsUnchanged() {
        var doc = DiaryDocument()
        let photo = layer(.photo)
        var frame = layer(.frame); frame.frameTargetID = photo.id
        var title = layer(.text); title.text = "标题"
        doc.objects[doc.rootContentID]?.layers = [photo, frame, title]
        let plan = DiaryReadingPlan(document: doc)
        #expect(plan.units.count == 2)
        #expect(plan.units[0].ids == [title.id])
        #expect(plan.units[1].ids == [photo.id, frame.id])
        #expect(doc.root.layers.map(\.id) == [photo.id, frame.id, title.id])
    }
    @Test func hiddenLayersDoNotAnimateAndLargePagesStayBounded() {
        var doc = DiaryDocument()
        var hidden = layer(.text); hidden.visible = false
        doc.objects[doc.rootContentID]?.layers = [hidden] + (0..<100).map { _ in layer(.sticker) }
        let plan = DiaryReadingPlan(document: doc)
        #expect(plan.units.count == 100)
        #expect(plan.duration < 7)
        #expect(plan.presentation(at: 0).states[hidden.id] == nil)
    }
    @Test func nestedTextIsRevealedWithoutChangingFinalRendering() {
        var doc = DiaryDocument()
        doc.objects[doc.rootContentID]?.referenceSize = CGSize(width: 160, height: 160)
        doc.objects[doc.rootContentID]?.background = .white
        var text = layer(.text); text.text = "旅行"; text.fontSize = 24
        doc.appendObject(containing: text)
        let plan = DiaryReadingPlan(document: doc)
        #expect(plan.units.count == 1)
        #expect(plan.units[0].characters == 2)
        func render(_ presentation: DiaryReadingPresentation?) -> Data? {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: doc.root.referenceSize, format: format).image {
                DiaryPageRenderer.draw(doc, images: [:], in: $0.cgContext, cacheObjects: false, presentation: presentation)
            }.pngData()
        }
        #expect(render(nil) == render(plan.presentation(at: plan.duration)))
        #expect(render(nil) != render(plan.presentation(at: -1)))
    }

}
