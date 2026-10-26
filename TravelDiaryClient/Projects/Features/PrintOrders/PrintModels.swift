import Foundation

nonisolated struct PrintProduct: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let revision: Int
    let width_mm: Int
    let height_mm: Int
    let paper: String
    let binding: String
    let description: String
    let cover_mode: String
    let duplex: Bool
    let min_pages: Int
    let max_pages: Int
    let max_quantity: Int
    var free_printing: Bool? = nil
    let base_fen: Int
    let page_fen: Int
    let shipping_fen: Int
    let regions: [String]
    let lead_time: String
    let terms: String
}
nonisolated struct PrintAddress: Codable, Equatable, Sendable {
    var name = ""
    var phone = ""
    var region = ""
    var detail = ""
    var trimmed: PrintAddress {
        PrintAddress(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                     phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
                     region: region.trimmingCharacters(in: .whitespacesAndNewlines),
                     detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var phoneValid: Bool {
        let value = trimmed.phone
        return value.range(of: #"^\+?[0-9][0-9 -]{5,18}[0-9]$"#, options: .regularExpression) != nil
            && value.filter(\.isNumber).count >= 7
    }
    var complete: Bool {
        let value = trimmed
        return !value.name.isEmpty && value.name.count <= 60 && !value.region.isEmpty &&
            !value.detail.isEmpty && value.detail.count <= 240 &&
            value.phoneValid
    }
}
nonisolated struct PrintFile: Codable, Sendable {
    let role: String
    let sha256: String
    let size: Int
    let page_count: Int
}
nonisolated struct PrintSnapshot: Codable, Sendable {
    struct Page: Codable, Sendable { let page_id: UUID; let revision_id: UUID; let role: String }
    let book_id: UUID
    let catalog_revision: UUID
    let pages: [Page]
    let exporter_version: String
}
nonisolated struct PrintSubmission: Codable, Sendable {
    var key: UUID
    let product_id: String
    let product_revision: Int
    let title: String
    let quantity: Int
    let page_count: Int
    let address: PrintAddress
    let snapshot: PrintSnapshot
    let files: [PrintFile]
    let confirmed: Bool
    let quote_total_fen: Int
    var revise_order_id: String? = nil
    var order_revision: Int? = nil
}
nonisolated struct PrintQuote: Decodable, Sendable {
    let total_fen: Int
    let production_fen: Int
    let shipping_fen: Int
    let page_count: Int
    let sheets: Int
    let product_revision: Int
}
nonisolated struct PrintOrder: Decodable, Identifiable, Sendable {
    var production_fen: Int? = nil
    var shipping_fen: Int? = nil
    var payment_expires_at: String?
    var payments: [PrintPaymentRecord]?
    var refunds: [PrintRefundRecord]?
    struct Event: Decodable, Identifiable, Sendable { let id: Int; let action: String; let message: String; let created_at: String }
    struct Shipment: Decodable, Identifiable, Sendable { let id: Int; let carrier: String; let tracking_number: String; let created_at: String; let kind: String }
    let id: String
    let number: String
    let title: String
    let spec: PrintProduct
    let address: PrintAddress
    let quantity: Int
    let page_count: Int
    let total_fen: Int
    var cover_page_count: Int? = nil
    let file_state: String
    let payment_state: String
    let state: String
    let revision: Int
    let allowed_actions: [String]
    let created_at: String
    let source_book_id: String
    let exception_reason: String
    let after_sale_state: String
    let after_sale_message: String
    let after_sale_resolution: String
    let refund_state: String
    let production_id: String?
    let production_error: String
    let checks: [String]
    let events: [Event]
    let shipments: [Shipment]
    var hasFeeBreakdown: Bool {
        guard let production_fen, let shipping_fen, production_fen >= 0, shipping_fen >= 0,
              production_fen <= total_fen, shipping_fen <= total_fen else { return false }
        return production_fen == total_fen - shipping_fen
    }
    var canPay: Bool { total_fen > 0 && payment_state == "unpaid" && state != "cancelled" && allowed_actions.contains("pay") }
    var paymentDeadline: Date? { payment_expires_at.flatMap(PrintText.date) }
    var statusText: String {
        if state == "draft" { return file_state == "ready" ? (payment_state == "unpaid" ? "待支付" : "等待审核") : PrintText.label(file_state) }
        return PrintText.label(state)
    }
}
nonisolated struct PrintOrderPage: Decodable, Sendable { let results: [PrintOrder]; let next_offset: Int? }
nonisolated struct PrintUploadPlan: Decodable, Sendable {
    struct File: Decodable, Sendable {
        struct Part: Decodable, Sendable { let number: Int; let offset: Int; let size: Int; let url: String; var headers: [String: String]? = nil }
        let role: String; let parts: [Part]; let upload_id: String?
        let init_url: String; let init_headers: [String:String]
        let list_url: String?; let complete_url: String?; let complete_headers: [String:String]; let head_url: String
    }
    let production_id: String
    let files: [File]
}
nonisolated struct WeChatPaymentParameters: Decodable, Sendable {
    let appid: String; let partnerid: String; let prepayid: String
    let package: String; let noncestr: String; let timestamp: UInt32; let sign: String
}
nonisolated enum PrintText {
    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func money(_ fen: Int) -> String { String(format: "¥%.2f", Double(fen) / 100) }
    static func label(_ value: String) -> String {
        ["draft":"准备中", "uploading":"待上传生产稿", "checking":"正在校验生产稿", "ready":"文件已就绪", "failed":"文件处理失败",
         "awaiting_review":"待印前审核", "needs_revision":"待修改重提", "paused":"制作暂停", "open":"待处理", "processing":"处理中", "resolved":"已解决", "exception":"退款异常", "queued":"等待制作", "producing":"打印装订中",
         "ready_to_ship":"等待发货", "shipped":"已发货", "completed":"已完成", "cancelled":"已取消",
         "not_required":"免费 · 无需支付", "unpaid":"未支付", "paid":"已支付", "refund_pending":"退款处理中", "refunded":"已退款"][value] ?? value
    }
}
nonisolated struct PrintFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

nonisolated struct PrintPaymentMethod: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
}
nonisolated struct PrintPaymentLaunch: Decodable, Sendable {
    let attempt_id: String
    let channel: String
    let expires_at: String
    let parameters: Parameters
    struct Parameters: Decodable, Sendable {
        let order_string: String?
        let appid: String?; let partnerid: String?; let prepayid: String?
        let package: String?; let noncestr: String?; let timestamp: UInt32?; let sign: String?
        func wechat() throws -> WeChatPaymentParameters {
            guard let appid, let partnerid, let prepayid, let package, let noncestr, let timestamp, let sign else { throw PrintFailure("支付参数不完整，请重试") }
            return WeChatPaymentParameters(appid: appid, partnerid: partnerid, prepayid: prepayid, package: package, noncestr: noncestr, timestamp: timestamp, sign: sign)
        }
    }
}

nonisolated struct PrintPaymentRecord: Decodable, Identifiable, Sendable {
    let id: String; let channel: String; let amount: Int; let state: String
    let paid_at: String?; let provider_id: String?
}
nonisolated struct PrintRefundRecord: Decodable, Identifiable, Sendable {
    let id: String; let channel: String; let amount: Int; let state: String; let reason: String
}
