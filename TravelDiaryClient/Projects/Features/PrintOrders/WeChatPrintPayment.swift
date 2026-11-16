import UIKit
import WebKit
import WechatOpenSDK

@MainActor
final class WeChatPrintPayment: NSObject, WXApiDelegate {
    static let shared = WeChatPrintPayment()
    private var registered = false
    private var appID: String { Bundle.main.object(forInfoDictionaryKey: "WeChatAppID") as? String ?? "" }
    var isConfigured: Bool {
        let link = Bundle.main.object(forInfoDictionaryKey: "WeChatUniversalLink") as? String ?? ""
        return appID.hasPrefix("wx") && !appID.contains("$(") && link.hasPrefix("https://") && !link.contains("$(")
    }
    func checkAvailability() throws {
        let link = Bundle.main.object(forInfoDictionaryKey: "WeChatUniversalLink") as? String ?? ""
        guard appID.hasPrefix("wx"), !appID.contains("$("), link.hasPrefix("https://") else {
            throw PrintFailure("微信服务尚未配置，请使用复制链接或分享海报")
        }
        if !registered { registered = WXApi.registerApp(appID, universalLink: link) }
        guard registered else { throw PrintFailure("微信服务初始化失败") }
        guard WXApi.isWXAppInstalled() else { throw PrintFailure("请先安装微信后再试") }
    }
    /// Explicit webpage message avoids the system share extension's unsupported item types.
    func shareInvitation(url: URL, cover: UIImage) async throws {
        try checkAvailability()
        guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.absoluteString.utf8.count < 10 * 1024 else {
            throw PrintFailure("邀请链接无效，请重新生成")
        }
        guard let thumbnail = Self.invitationThumbnail(cover) else {
            throw PrintFailure("分享封面处理失败，请使用分享海报")
        }
        let webpage = WXWebpageObject()
        webpage.webpageUrl = url.absoluteString
        let message = WXMediaMessage()
        message.title = "一起收藏旅途 · 寻寻仔"
        message.description = "好友邀请你一起制作旅行手帐。验证手机号或邮箱后，在 App 完成登录或绑定。"
        message.thumbData = thumbnail
        message.mediaObject = webpage
        let request = SendMessageToWXReq()
        request.bText = false
        request.scene = Int32(WXSceneSession.rawValue)
        request.message = message
        let accepted: Bool = await withCheckedContinuation { continuation in
            WXApi.send(request) { continuation.resume(returning: $0) }
        }
        guard accepted else { throw PrintFailure("未能打开微信分享，请重试或复制邀请链接") }
        // Accepted means handed to WeChat, never proof of delivery or invitation conversion.
    }

    static func invitationThumbnail(_ image: UIImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        for edge in [240, 180, 120] {
            let side = CGFloat(edge)
            let scale = min(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            for quality in [0.8, 0.6, 0.4] {
                if let data = resized.jpegData(compressionQuality: quality), data.count < 32 * 1024 {
                    return data
                }
            }
        }
        return nil
    }

    func pay(_ params: WeChatPaymentParameters) async throws {
        try checkAvailability()
        guard params.appid == appID else { throw PrintFailure("微信支付配置不匹配，请联系工作人员") }
        let req = PayReq()
        req.partnerId = params.partnerid; req.prepayId = params.prepayid
        req.package = params.package; req.nonceStr = params.noncestr; req.timeStamp = params.timestamp; req.sign = params.sign
        let sent: Bool = await withCheckedContinuation { continuation in
            WXApi.send(req) { continuation.resume(returning: $0) }
        }
        guard sent else { throw PrintFailure("未能打开微信支付，请重试") }
    }
    func handle(_ url: URL) { _ = try? checkAvailability(); _ = WXApi.handleOpen(url, delegate: self) }
    func handle(_ activity: NSUserActivity) { _ = try? checkAvailability(); _ = WXApi.handleOpenUniversalLink(activity, delegate: self) }
    nonisolated func onResp(_ resp: BaseResp) {
        if resp is SendMessageToWXResp {
            let code = resp.errCode
            Task { @MainActor in
                NotificationCenter.default.post(name: .invitationWeChatReturned, object: nil, userInfo: ["code": code])
            }
            return
        }
        // SDK 返回不改变付款结果；订单页回到前台后向服务端查单。
        guard resp is PayResp else { return }
        let outcome: PrintPaymentReturn = resp.errCode == -2 ? .cancelled : resp.errCode == 0 ? .returned : .failed
        Task { @MainActor in NotificationCenter.default.post(name: .printPaymentReturned, object: nil, userInfo: ["outcome": outcome.rawValue]) }
    }
}
extension Notification.Name { static let printPaymentReturned = Notification.Name("PrintPaymentReturned") }

extension Notification.Name { static let invitationWeChatReturned = Notification.Name("InvitationWeChatReturned") }
