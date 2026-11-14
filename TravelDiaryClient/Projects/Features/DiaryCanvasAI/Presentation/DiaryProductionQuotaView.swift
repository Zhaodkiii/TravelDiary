import SwiftUI

struct DiaryProductionQuotaSection: View {
    @ObservedObject private var service = DiaryProductionService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("制作额度") {
            if service.owner == nil {
                Text("登录后可查看制作额度").foregroundStyle(.secondary)
            } else if let quota = service.quota {
                if let plan = quota.plan {
                    Text(plan == "pro" ? "Pro 会员" : "免费版").font(.subheadline)
                } else if quota.entitlementState == "unavailable" {
                    Text("会员状态暂时无法确认，请刷新额度。").foregroundStyle(.secondary)
                }
                ForEach(quota.windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(window.kind == "short" ? "5 小时额度" : "7 天额度")
                            .font(.headline)
                        Text(DiaryProductionQuotaSection.remainingText(window.remainingRatio))
                        ProgressView(value: window.remainingRatio)
                            .tint(window.remainingRatio < 0.1 ? .orange : Color.accentColor)
                        if let reset = window.resetAt, let date = date(reset) {
                            Text("\(date.formatted(date: .abbreviated, time: .shortened)) 恢复")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text(window.status == "awaiting_first_use" ? "额度已恢复，下次制作时开始新周期" : "首次制作时开始计时").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }
                if quota.plan == "free", quota.serviceStatus == "available", let owner = service.owner {
                    if service.canPurchaseMembership {
                        NavigationLink("查看 Pro 权益") { MembershipPurchaseScreen(owner: owner) }
                    } else {
                        Text("绑定正式账号后可开通 Pro，获得更多制作额度。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if quota.pendingUsage { Text("用量更新中").foregroundStyle(.secondary) }
                Text("按 AI 用量消耗额度，失败或取消也会消耗。").font(.footnote)
                if quota.serviceStatus == "maintenance" {
                    Text("制作服务维护中，已有制作可继续").foregroundStyle(.secondary)
                } else if quota.serviceStatus == "unconfigured" {
                    Text("制作服务尚未开放").foregroundStyle(.secondary)
                }
                if !quota.entitled {
                    Text("当前账号暂无 AI 制作权益").foregroundStyle(.secondary)
                }
            }
            if let error = service.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                Task { await service.refresh() }
            } label: {
                if service.loading { ProgressView("正在查询") }
                else { Text(service.error == nil ? "刷新额度" : "重试查询") }
            }.disabled(service.loading || service.owner == nil)
        }
        .task(id: service.owner) { if service.owner != nil { await service.refresh() } }
        .task(id: service.quota?.serverTime) {
            guard let snapshot = service.quota, let serverDate = date(snapshot.serverTime) else { return }
            var events = snapshot.windows.compactMap { $0.resetAt.flatMap(date) }
            if snapshot.plan == "pro", let expiry = snapshot.membershipExpiresAt.flatMap(date), expiry > serverDate {
                events.append(expiry)
            }
            guard let reset = events.min() else { return }
            let delay = max(1, reset.timeIntervalSince(serverDate))
            do {
                try await Task.sleep(for: .seconds(delay))
                if scenePhase == .active { await service.refresh() }
            } catch {}
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, service.owner != nil { Task { await service.refresh() } }
        }
    }

    static func remainingText(_ ratio: Double) -> String {
        if ratio > 0 && ratio < 0.01 { return "剩余不足 1%" }
        return "剩余 \(Int((min(1, max(0, ratio)) * 100).rounded(.down)))%"
    }

    private func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct DiaryProductionQuotaButton: View {
    @ObservedObject private var service = DiaryProductionService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var presented = false

    var body: some View {
        let short = remainingFraction(for: "short")
        let weekly = remainingFraction(for: "weekly")

        Button {
            presented = true
        } label: {
            ZStack {
                if short != nil {
                    quotaArc(start: 192, sweep: 156, remaining: short)
                    quotaArc(start: 168, sweep: -156, remaining: weekly)
                } else {
                    quotaArc(start: -90, sweep: 360, remaining: weekly)
                }
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel("查看制作额度")
        .accessibilityValue(short == nil ? "7 天 \(quotaDescription(weekly))" : "5 小时 \(quotaDescription(short))，7 天 \(quotaDescription(weekly))")
        .accessibilityIdentifier("diary.ai.production-quota")
        .task(id: service.owner) {
            if service.owner != nil { await service.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, service.owner != nil { Task { await service.refresh() } }
        }
        .popover(isPresented: $presented, arrowEdge: .top) {
            NavigationStack {
                Form { DiaryProductionQuotaSection() }
                    .navigationTitle("制作额度")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { presented = false }
                        }
                    }
            }
            .frame(idealWidth: 360, idealHeight: 440)
            .presentationCompactAdaptation(.sheet)
            .presentationDetents([.medium, .large])
        }
    }

    private func remainingFraction(for kind: String) -> Double? {
        guard let window = service.quota?.windows.first(where: { $0.kind == kind }) else { return nil }
        return window.remainingRatio
    }

    private func quotaDescription(_ fraction: Double?) -> String {
        fraction.map(DiaryProductionQuotaSection.remainingText) ?? "暂无数据"
    }

    private func quotaArc(start: Double, sweep: Double, remaining: Double?) -> some View {
        let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round)
        return ZStack {
            QuotaArc(start: start, sweep: sweep)
                .stroke(.primary.opacity(remaining == nil ? 0.4 : 0.22), style: stroke)
            if let remaining, remaining > 0 {
                QuotaArc(start: start, sweep: sweep * remaining)
                    .stroke(.primary, style: stroke)
            }
        }
    }
}

nonisolated private struct QuotaArc: Shape {
    let start: Double
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRelativeArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2 - 1,
            startAngle: .degrees(start),
            delta: .degrees(sweep)
        )
        return path
    }
}
