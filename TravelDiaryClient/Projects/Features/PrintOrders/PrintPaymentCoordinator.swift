import Foundation
import Combine

@MainActor
protocol PrintPaymentClient: AnyObject {
    func refreshPayment(_ id: String, owner: String) async throws -> PrintOrder
    func checkPaymentAvailability(_ channel: String) throws
    func createPayment(_ id: String, owner: String, channel: String, key: UUID) async throws -> PrintPaymentLaunch
    func launchPayment(_ launch: PrintPaymentLaunch, owner: String) async throws
}

nonisolated enum PrintPaymentReturn: String, Sendable { case returned, cancelled, failed }

nonisolated struct PrintPaymentContext: Codable, Sendable {
    let owner: String
    let orderID: String
    let channel: String
    let key: UUID
    let createdAt: Date
    var attemptID: String?
    var expiresAt: String?
}

/// One worker per account/order. UI lifetimes never own a payment attempt.
@MainActor
final class PrintPaymentCoordinator: ObservableObject {
    enum Phase: Equatable {
        case loading, ready, creating, launching, verifying, unresolved, succeeded, closed, refunding, refunded, free, unavailable
        var isBusy: Bool { [.loading, .creating, .launching, .verifying].contains(self) }
        var isResult: Bool { [.succeeded, .closed, .refunding, .refunded, .free].contains(self) }
        var title: String {
            switch self {
            case .loading: "正在读取订单"
            case .ready: "确认支付"
            case .creating: "正在准备支付"
            case .launching: "正在打开支付应用"
            case .verifying: "正在确认支付结果"
            case .unresolved: "支付结果待确认"
            case .succeeded: "支付成功"
            case .closed: "订单已关闭"
            case .refunding: "退款处理中"
            case .refunded: "已退款"
            case .free: "无需支付"
            case .unavailable: "当前暂不可支付"
            }
        }
    }
    let id: String
    let owner: String
    @Published private(set) var order: PrintOrder?
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var error: String?
    @Published private(set) var returnHint: String?
    @Published private(set) var context: PrintPaymentContext?
    private let client: any PrintPaymentClient
    private let storageURL: URL
    private let delays: [Duration]
    private var worker: Task<Void, Never>?
    private var needsRefresh = false
    private var wantsPoll = false
    private var valid = true
    private var storageError: String?

    init(id: String, owner: String, client: any PrintPaymentClient, storageURL: URL,
         delays: [Duration] = [.zero, .seconds(2), .seconds(3), .seconds(5), .seconds(5), .seconds(5)]) {
        self.id = id; self.owner = owner; self.client = client; self.storageURL = storageURL; self.delays = delays
        if FileManager.default.fileExists(atPath: storageURL.path) {
            do {
                let saved = try JSONDecoder().decode(PrintPaymentContext.self, from: Data(contentsOf: storageURL))
                guard saved.owner == owner, saved.orderID == id else { throw PrintFailure("支付记录不匹配，请从原账号查看订单") }
                context = saved
            } catch { storageError = "无法读取本地支付记录，请核对订单后联系支持：" + error.localizedDescription }
        }
    }
    var hasPendingPayment: Bool { context != nil || storageError != nil }
    var canPay: Bool {
        valid && worker == nil && phase == .ready && order?.canPay == true && storageError == nil
            && (order?.paymentDeadline.map { $0 > Date() } ?? true)
    }
    /// Recovery sends the original key/channel only; it never creates a fresh local attempt.
    var canResumeOriginal: Bool {
        valid && worker == nil && phase == .unresolved && storageError == nil && context != nil && order?.canPay == true
    }
    var message: String {
        switch phase {
        case .succeeded: "款项已确认，后续印前审核与制作进度可在订单中查看。"
        case .free: "本订单无需付款，请在订单中查看印前审核进度。"
        case .closed: order?.payment_state == "paid" ? "订单已取消，款项已确认，请在订单中查看退款进度。" : "订单已关闭，不能继续付款。"
        case .refunding: "退款正在处理，请在订单中查看进度。"
        case .refunded: "退款结果已确认，请在订单中查看明细。"
        case .unresolved: "尚未确认上一笔交易的最终结果，请勿重复付款。可以查询结果或稍后从原订单继续。"
        case .unavailable: "请刷新订单，确认文件处理进度和支付期限。"
        default: returnHint ?? "请核对金额并选择支付方式。"
        }
    }
    func invalidate() {
        valid = false; worker?.cancel(); worker = nil; needsRefresh = false; wantsPoll = false
        order = nil; phase = .unavailable; error = "登录状态已变化，请重新打开订单"
    }
    func returned(_ outcome: PrintPaymentReturn) {
        guard valid, hasPendingPayment else { return }
        switch outcome {
        case .cancelled: returnHint = "已退出支付，正在核对订单是否付款。"
        case .failed: returnHint = "支付应用未完成操作，正在核对交易结果。"
        case .returned: returnHint = nil
        }
        requestRefresh(poll: true)
    }
    func requestRefresh(poll: Bool = false) {
        guard valid else { return }
        needsRefresh = true; wantsPoll = wantsPoll || poll
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await drainRefreshes()
            worker = nil
            // Publish after unlocking so computed action availability also updates.
            objectWillChange.send()
        }
    }
    func refresh(poll: Bool = false) async {
        requestRefresh(poll: poll)
        await worker?.value
    }
    func pay(channel: String) {
        guard canPay else { return }
        do { try client.checkPaymentAvailability(channel) }
        catch { self.error = error.localizedDescription; return }
        start(PrintPaymentContext(owner: owner, orderID: id, channel: channel, key: UUID(), createdAt: Date()))
    }
    func resumeOriginalPayment() {
        guard canResumeOriginal, let context else { return }
        do { try client.checkPaymentAvailability(context.channel) }
        catch { self.error = error.localizedDescription; return }
        start(context)
    }
    private func start(_ saved: PrintPaymentContext) {
        // A local write failure must not send a transaction request.
        do { try save(saved); context = saved }
        catch { self.error = "无法保存支付记录，请稍后重试：" + error.localizedDescription; return }
        error = nil; returnHint = nil; phase = .creating
        worker = Task { [weak self] in
            guard let self else { return }
            do {
                // Never replace this key on a transport error.
                let launch = try await client.createPayment(id, owner: owner, channel: saved.channel, key: saved.key)
                try checkActive()
                guard launch.channel == saved.channel else { throw PrintFailure("支付渠道不一致，请查询订单") }
                if let expected = saved.attemptID, expected != launch.attempt_id {
                    throw PrintFailure("原支付交易不一致，请查询订单后联系支持")
                }
                var updated = saved; updated.attemptID = launch.attempt_id; updated.expiresAt = launch.expires_at
                try save(updated); context = updated
                // Keep the attempt ID even when authorization expired, so a later
                // server-confirmed closure can release this exact attempt.
                guard let expires = PrintText.date(launch.expires_at), expires > Date() else {
                    throw PrintFailure("支付授权已过期，请查询订单后重试")
                }
                phase = .launching
                try await client.launchPayment(launch, owner: owner)
                try checkActive()
            } catch {
                guard valid else { return }
                self.error = error.localizedDescription
            }
            guard valid else { return }
            needsRefresh = true; wantsPoll = true
            await drainRefreshes()
            worker = nil; objectWillChange.send()
        }
    }
    private func checkActive() throws {
        try Task.checkCancellation()
        guard valid else { throw CancellationError() }
    }
    private func save(_ value: PrintPaymentContext) throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    private func clearContext() throws {
        if FileManager.default.fileExists(atPath: storageURL.path) { try FileManager.default.removeItem(at: storageURL) }
        context = nil; storageError = nil
    }
    private func drainRefreshes() async {
        while needsRefresh && valid && !Task.isCancelled {
            needsRefresh = false
            let poll = wantsPoll; wantsPoll = false
            phase = .verifying
            for delay in poll ? delays : [.zero] {
                do {
                    if delay > .zero { try await Task.sleep(for: delay) }
                    let value = try await client.refreshPayment(id, owner: owner)
                    try checkActive()
                    order = value
                    try reconcile(value)
                    if phase != .unresolved { break }
                } catch is CancellationError {
                    if valid {
                        phase = hasPendingPayment ? .unresolved : .unavailable
                        error = "查询已中断，请重新查询支付结果"
                    }
                    return
                }
                catch {
                    guard valid else { return }
                    self.error = error.localizedDescription
                    phase = hasPendingPayment ? .unresolved : .unavailable
                    break
                }
            }
        }
    }
    private func reconcile(_ value: PrintOrder) throws {
        switch value.payment_state {
        case "paid": phase = value.state == "cancelled" ? .closed : .succeeded
        case "refund_pending": phase = .refunding
        case "refunded": phase = .refunded
        case "not_required": phase = value.state == "cancelled" ? .closed : .free
        default: phase = value.state == "cancelled" ? .closed : .unavailable
        }
        if phase.isResult {
            do { try clearContext(); error = nil }
            catch {
                // A local cleanup failure cannot reverse a server-confirmed result.
                context = nil; storageError = nil
                self.error = "订单结果已确认，本地恢复记录暂未清理，可稍后重新打开订单核对。"
            }
            return
        }
        if let attemptID = context?.attemptID,
           let attempt = value.payments?.first(where: { $0.id == attemptID }),
           ["closed", "cancelled"].contains(attempt.state) {
            // Only an explicit server terminal state permits a new key/channel.
            try clearContext()
        }
        let activeAttempts = value.payments?.contains { !["closed", "cancelled"].contains($0.state) } ?? false
        if hasPendingPayment || activeAttempts {
            phase = .unresolved
            if let storageError { error = storageError }
        } else if value.canPay, value.paymentDeadline.map({ $0 > Date() }) ?? true {
            phase = .ready; error = nil
        } else { phase = .unavailable }
    }
}
