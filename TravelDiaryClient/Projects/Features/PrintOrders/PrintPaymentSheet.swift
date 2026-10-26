import SwiftUI

struct PrintPaymentSheet: View {
    let order: PrintOrder
    let owner: String
    var onViewOrder: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var payment: PrintPaymentCoordinator
    @State private var methods: [PrintPaymentMethod] = []
    @State private var channel = ""
    @State private var loadingMethods = false
    @State private var methodError: String?
    @State private var unavailable: [String: String] = [:]
    @AppStorage("print.lastPaymentChannel") private var lastChannel = ""

    init(order: PrintOrder, owner: String, onViewOrder: (() -> Void)? = nil) {
        self.order = order; self.owner = owner; self.onViewOrder = onViewOrder
        _payment = StateObject(wrappedValue: PrintOrderService.shared.paymentCoordinator(id: order.id, owner: owner))
    }
    private var current: PrintOrder { payment.order ?? order }
    private var selectedChannel: String { payment.context?.channel ?? channel }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 10) {
                        if payment.phase.isResult {
                            Image(systemName: payment.phase == .succeeded ? "checkmark.circle.fill" : "info.circle")
                                .font(.system(size: 40)).foregroundStyle(DiaryLibraryStyle.accent)
                        }
                        Text(payment.phase.title).font(.headline)
                        Text(PrintText.money(current.total_fen)).font(.system(size: 36, weight: .semibold, design: .rounded))
                        Text(current.title).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(current.spec.title) · \(current.quantity) 份 · \(current.page_count) 面内页").font(.caption).foregroundStyle(.secondary)
                        if let date = current.paymentDeadline, !payment.phase.isResult {
                            Text("支付截止：\(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    if current.hasFeeBreakdown, let production = current.production_fen, let shipping = current.shipping_fen {
                        VStack(spacing: 10) {
                            LabeledContent("印制费", value: PrintText.money(production))
                            LabeledContent("运费", value: PrintText.money(shipping))
                        }.font(.subheadline)
                    }
                    if !payment.phase.isResult {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("选择支付方式").font(.headline).padding(.bottom, 12)
                            ForEach(methods) { method in
                                Button { channel = method.id } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: method.id == "wechat" ? "bubble.left.and.bubble.right.fill" : "creditcard.fill")
                                            .font(.title2).foregroundStyle(method.id == "wechat" ? Color.green : Color.blue)
                                            .frame(width: 36)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(method.title).foregroundStyle(.primary)
                                            if let reason = unavailable[method.id] { Text(reason).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Image(systemName: selectedChannel == method.id ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedChannel == method.id ? DiaryLibraryStyle.accent : .secondary)
                                    }.padding(.vertical, 18).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .disabled(!payment.canPay || unavailable[method.id] != nil || loadingMethods)
                                    .accessibilityLabel(method.title + (selectedChannel == method.id ? "，已选择" : "，未选择"))
                                Divider()
                            }
                            if loadingMethods { ProgressView("正在获取支付方式…").padding(.vertical) }
                            else if methods.isEmpty { Text("暂时没有可用支付方式").foregroundStyle(.secondary).padding(.vertical) }
                            Button("重新获取支付方式") { Task { await loadMethods() } }
                                .font(.footnote).padding(.top, 12).disabled(loadingMethods || payment.phase.isBusy)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text(payment.message).font(.subheadline).foregroundStyle(.secondary)
                        if let hint = payment.returnHint { Text(hint).font(.footnote).foregroundStyle(.secondary) }
                        if let error = payment.error ?? methodError { Text(error).font(.footnote).foregroundStyle(.red) }
                        if payment.phase.isBusy { ProgressView().controlSize(.small) }
                        if payment.canResumeOriginal {
                            Button("恢复原支付") { payment.resumeOriginalPayment() }
                            Text("沿用原订单和原支付方式恢复，不会切换支付方式。").font(.caption).foregroundStyle(.secondary)
                        }
                        if !payment.phase.isResult {
                            Button("查询支付结果") { payment.requestRefresh(poll: true) }.disabled(payment.phase.isBusy)
                        }
                    }
                    DisclosureGroup("订单与购买说明") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("订单号：\(current.number)").textSelection(.enabled)
                            Text(current.spec.terms)
                        }.font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }.background(DiaryLibraryStyle.background)
                .navigationTitle(payment.phase.isResult ? "支付结果" : "确认支付")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回订单") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 10) {
                        if payment.phase.isResult {
                            Button("查看订单") { dismiss(); onViewOrder?() }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                        } else {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("实付金额").font(.caption).foregroundStyle(.secondary)
                                    Text(PrintText.money(current.total_fen)).font(.title3.bold())
                                }
                                Spacer()
                                Button {
                                    lastChannel = channel; payment.pay(channel: channel)
                                } label: { Text(payment.phase.isBusy ? payment.phase.title : "确认支付").font(.headline).padding(.vertical, 8) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!payment.canPay || loadingMethods || channel.isEmpty || unavailable[channel] != nil || !methods.contains { $0.id == channel })
                            }
                            Button("稍后支付，返回订单") { dismiss() }.font(.footnote)
                        }
                    }.padding().background(.regularMaterial)
                }
                .task {
                    payment.requestRefresh(poll: payment.hasPendingPayment)
                    await loadMethods()
                }
        }.tint(DiaryLibraryStyle.accent)
    }
    private func loadMethods() async {
        guard !loadingMethods else { return }
        loadingMethods = true; methodError = nil
        defer { loadingMethods = false }
        do {
            let values = try await PrintOrderService.shared.paymentMethods(owner: owner)
            methods = values; unavailable = [:]
            for method in values {
                do { try PrintOrderService.shared.checkPaymentAvailability(method.id) }
                catch { unavailable[method.id] = error.localizedDescription }
            }
            if !values.contains(where: { $0.id == channel && unavailable[$0.id] == nil }) {
                channel = values.first(where: { $0.id == lastChannel && unavailable[$0.id] == nil })?.id
                    ?? values.first(where: { unavailable[$0.id] == nil })?.id ?? ""
            }
        } catch { methodError = error.localizedDescription; methods = []; channel = "" }
    }
}
