import Testing
import UIKit
import ImageIO
@testable import TravelDiary

@MainActor struct HelpFeedbackTests {
    @Test func supportPushRequiresKnownSceneActionAndValidIdentifiers() {
        let ticket=UUID().uuidString,event=UUID().uuidString
        let valid:[AnyHashable:Any] = ["schema_version":1,"scene_key":"support.feedback.updated","action":"open_support_ticket","ticket_id":ticket,"event_id":event]
        #expect(SupportPushPayload(valid)?.ticket == ticket)
        var invalid=valid;invalid["scene_key"]="diary.customization.delivered"
        #expect(SupportPushPayload(invalid) == nil)
        invalid=valid;invalid["ticket_id"]="../other-account"
        #expect(SupportPushPayload(invalid) == nil)
        invalid=valid;invalid["action"]="open_arbitrary_url"
        #expect(SupportPushPayload(invalid) == nil)
    }
    @Test func screenshotNormalizationBoundsSizeAndDiscardsPrivateMetadata() throws {
        let format=UIGraphicsImageRendererFormat();format.scale=1
        let source=UIGraphicsImageRenderer(size:CGSize(width:3200,height:1600),format:format).image { c in UIColor.red.setFill();c.fill(CGRect(x:0,y:0,width:3200,height:1600)) }
        let result=try HelpFeedbackService().normalizePhoto(try #require(source.pngData()))
        let image=try #require(UIImage(data:result.bytes))
        #expect(max(image.size.width,image.size.height) <= 2400)
        #expect(result.bytes.count <= 10_000_000)
        let cg=try #require(CGImageSourceCreateWithData(result.bytes as CFData,nil))
        let properties=CGImageSourceCopyPropertiesAtIndex(cg,0,nil) as? [String:Any]
        #expect(properties?[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(result.attachmentID == nil)
    }
    @Test func draftRoundTripPreservesRetryKeyAndAttachmentIdentity() throws {
        var draft=FeedbackDraft();draft.title="保存失败";draft.description="重启应用后仍有保存失败提示";draft.photos=[FeedbackPhoto(bytes:Data([1,2,3]),attachmentID:UUID().uuidString,uploadedAt:Date())]
        let decoded=try JSONDecoder().decode(FeedbackDraft.self,from:JSONEncoder().encode(draft))
        #expect(decoded.requestID == draft.requestID)
        #expect(decoded.photos[0].id == draft.photos[0].id)
        #expect(decoded.photos[0].attachmentID == draft.photos[0].attachmentID)
    }
    @Test func helpImageParsingDoesNotInterpretPrivateAttachmentsOrArbitrarySchemes() {
        let id=UUID().uuidString
        let blocks=HelpBodyBlock.parse("步骤说明\n![示意图](support-image:\(id))\n后续说明")
        #expect(blocks.count == 3)
        #expect(blocks[1] == .image(1,id,"示意图"))
        #expect(HelpBodyBlock.parse("![不可信](javascript:alert)" ) == [.text(0,"![不可信](javascript:alert)")])
        #expect(HelpBodyBlock.parse("![私人截图](support-attachment:\(id))").count == 1)
    }
    @Test func textLimitsCountUnicodeScalarsLikeTheServer() {
        #expect(supportCharacterCount("中文") == 2)
        #expect(supportCharacterCount("👨‍👩‍👧‍👦") == 7)
    }
    @Test func unknownTicketStateDoesNotGrantClientActions() throws {
        let json="""
        {"id":"test","number":"FBTEST","title":"问题","kind":"other","status":"future_state","revision":1,"public_sequence":0,"read_sequence":0,"unread":false,"allowed_actions":[],"created_at":"2026-10-20T00:00:00Z","last_public_activity_at":"2026-10-20T00:00:00Z"}
        """
        let ticket=try JSONDecoder().decode(FeedbackTicket.self,from:Data(json.utf8))
        #expect(ticket.statusTitle == "状态待更新")
        #expect(ticket.allowed_actions.isEmpty)
    }
}
