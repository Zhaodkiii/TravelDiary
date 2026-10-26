import UIKit
import AlipaySDK

@MainActor
final class AlipayPrintPayment {
    static let shared = AlipayPrintPayment()
    private var scheme: String { Bundle.main.object(forInfoDictionaryKey: "AlipayURLScheme") as? String ?? "" }
    func checkAvailability() throws {
        guard !scheme.isEmpty, !scheme.contains("$(") else { throw PrintFailure("支付宝支付尚未配置") }
        guard let url = URL(string: "alipay://"), UIApplication.shared.canOpenURL(url) else { throw PrintFailure("请先安装支付宝后再支付") }
    }
    func pay(_ order: String) throws {
        try checkAvailability()
        AlipaySDK.defaultService().payOrder(order, fromScheme: scheme) { result in
            let status = result?["resultStatus"] as? String
            let outcome: PrintPaymentReturn = status == "6001" ? .cancelled : status == "4000" ? .failed : .returned
            Task { @MainActor in NotificationCenter.default.post(name: .printPaymentReturned, object: nil, userInfo: ["outcome": outcome.rawValue]) }
        }
    }
    @discardableResult func handle(_ url: URL) -> Bool {
        guard url.scheme == scheme else { return false }
        if url.host == "safepay" {
            AlipaySDK.defaultService().processOrder(withPaymentResult: url) { result in
                let status = result?["resultStatus"] as? String
                let outcome: PrintPaymentReturn = status == "6001" ? .cancelled : status == "4000" ? .failed : .returned
                Task { @MainActor in NotificationCenter.default.post(name: .printPaymentReturned, object: nil, userInfo: ["outcome": outcome.rawValue]) }
            }
        }
        return true
    }
}

import SwiftUI

struct PrintProbeLink: Identifiable {
    let id: UUID
    let token: UUID
    let origin: URL
    func launchRequest() throws -> URLRequest {
        let url = origin.appendingPathComponent("api/v1/print/payment-probes/\(id.uuidString.lowercased())/launch/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token.uuidString.lowercased()])
        return request
    }

    init?(_ url: URL) {
        guard url.scheme == "traveldiary-paytest", url.host == "launch",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = parts.queryItems ?? []
        guard let id = UUID(uuidString: values.first(where: {$0.name == "id"})?.value ?? ""),
              let token = UUID(uuidString: values.first(where: {$0.name == "token"})?.value ?? ""),
              let raw = values.first(where: {$0.name == "origin"})?.value,
              let origin = URL(string: raw), origin.scheme == "https", origin.host == "diary.dreamwhale.top",
              origin.user == nil, origin.password == nil, origin.port == nil else { return nil }
        self.id = id; self.token = token; self.origin = origin
    }
}

struct PrintProbeScreen: View {
    let link: PrintProbeLink
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var launched = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("管理员支付联调") {
                    Text("本次将支付 ¥0.01，用于验证收款配置。服务端确认付款后自动原路退款，不会产生印制订单。")
                    Text("服务：diary.dreamwhale.top").font(.caption)
                    Text("测试单：" + link.id.uuidString).font(.caption)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(launched ? "再次打开支付" : "确认支付 ¥0.01") { Task { await pay() } }.disabled(busy)
                    if busy { ProgressView() }
                }
                Section { Text("付款或取消后，请回到后台刷新测试结果。回跳提示不作为支付成功依据；退款由服务端查询确认。") }
            }.navigationTitle("支付联调").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
    private func pay() async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        do {
            let request = try link.launchRequest()
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PrintFailure("服务器响应异常，请稍后重试")
            }
            guard (200..<300).contains(http.statusCode) else {
                switch http.statusCode {
                case 400: throw PrintFailure("联调链接无效或已过期，请在后台重新创建测试并扫码")
                case 404: throw PrintFailure("未找到联调接口或测试单，请确认已安装最新 App，并在后台重新扫码")
                case 409: throw PrintFailure("测试单正在处理或已结束，请回后台查询支付及退款结果")
                case 429: throw PrintFailure("操作过于频繁，请稍后重试")
                case 500...599: throw PrintFailure("支付服务暂不可用，请稍后重试；如已付款，请回后台查询结果")
                default: throw PrintFailure("联调请求失败（HTTP \(http.statusCode)），请回后台查询")
                }
            }
            // API may return the common envelope; never log signed payment parameters.
            let json = try JSONSerialization.jsonObject(with: data) as? [String:Any]
            let payload: Data
            if let code = json?["code"] as? Int {
                guard code == 0, let value = json?["data"] else { throw PrintFailure("测试未能启动，请回后台查询") }
                payload = try JSONSerialization.data(withJSONObject: value)
            } else { payload = data }
            let launch = try JSONDecoder().decode(PrintPaymentLaunch.self, from: payload)
            guard UUID(uuidString: launch.attempt_id) == link.id else { throw PrintFailure("测试单不一致") }
            if launch.channel == "alipay", let order = launch.parameters.order_string {
                try AlipayPrintPayment.shared.pay(order)
            } else if launch.channel == "wechat" {
                try await WeChatPrintPayment.shared.pay(launch.parameters.wechat())
            } else { throw PrintFailure("此版本不支持该测试渠道") }
            launched = true
        } catch { self.error = error.localizedDescription }
    }
}
