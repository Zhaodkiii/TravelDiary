import UIKit
import WebKit
import WechatOpenSDK

@MainActor
final class WeChatPrintPayment: NSObject, WXApiDelegate {
    static let shared = WeChatPrintPayment()
    private var registered = false
    private var appID: String { Bundle.main.object(forInfoDictionaryKey: "WeChatAppID") as? String ?? "" }
    func checkAvailability() throws {
        let link = Bundle.main.object(forInfoDictionaryKey: "WeChatUniversalLink") as? String ?? ""
        guard appID.hasPrefix("wx"), !appID.contains("$("), link.hasPrefix("https://") else {
            throw PrintFailure("微信支付尚未开放，请稍后再试")
        }
        if !registered { registered = WXApi.registerApp(appID, universalLink: link) }
        guard registered else { throw PrintFailure("微信支付初始化失败") }
        guard WXApi.isWXAppInstalled() else { throw PrintFailure("请先安装微信后再支付") }
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
        // SDK 返回不改变付款结果；订单页回到前台后向服务端查单。
        Task { @MainActor in NotificationCenter.default.post(name: .printPaymentReturned, object: nil) }
    }
}
extension Notification.Name { static let printPaymentReturned = Notification.Name("PrintPaymentReturned") }
