import SwiftUI

struct DiaryProductionQuotaSection: View {
    @ObservedObject private var service = DiaryProductionService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("制作额度") {
            if service.owner == nil {
                Text("登录后可查看制作额度").foregroundStyle(.secondary)
            } else if let quota = service.quota {
                ForEach(quota.windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(window.kind == "short" ? "5 小时额度" : "7 天额度")
                            .font(.headline)
                        Text("可用 \(window.available) 次，共 \(window.limit) 次")
                        if window.reserved > 0 {
                            Text("\(window.reserved) 次正在制作中").foregroundStyle(.secondary)
                        }
                        if let reset = window.resetAt, let date = date(reset) {
                            Text("恢复时间 \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text(window.status == "awaiting_first_use" ? "额度已恢复，下次制作时开始新周期" : "首次制作时开始计时").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                }
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
            guard let snapshot = service.quota, let serverDate = date(snapshot.serverTime),
                  let reset = snapshot.windows.compactMap({ $0.resetAt.flatMap(date) }).min() else { return }
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
                quotaArc(start: 192, sweep: 156, remaining: short)
                quotaArc(start: 168, sweep: -156, remaining: weekly)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)
        }
        .accessibilityLabel("查看制作额度")
        .accessibilityValue("5 小时剩余 \(quotaDescription(short))，7 天剩余 \(quotaDescription(weekly))")
        .accessibilityIdentifier("diary.ai.production-quota")
        .task(id: service.owner) {
            if service.owner != nil { await service.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, service.owner != nil { Task { await service.refresh() } }
        }
        .popover(isPresented: $presented, arrowEdge: .top) {
            Form { DiaryProductionQuotaSection() }
                .frame(width: 300, height: 340)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func remainingFraction(for kind: String) -> Double? {
        guard let window = service.quota?.windows.first(where: { $0.kind == kind }) else { return nil }
        guard window.limit > 0 else { return 0 }
        return min(1, max(0, Double(window.available) / Double(window.limit)))
    }

    private func quotaDescription(_ fraction: Double?) -> String {
        fraction?.formatted(.percent.precision(.fractionLength(0))) ?? "暂无数据"
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
