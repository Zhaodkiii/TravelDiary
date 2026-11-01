import SwiftUI

nonisolated struct DiaryAIActivityGroup: Identifiable {
    var id: UUID
    var title: String
    var events: [DiaryAIWorkspaceEvent]
    var requests: Int { events.filter { $0.kind == "request" }.count }
    var issues: Int { events.filter { $0.kind == "error" }.count }
    var summaries: [DiaryAIWorkspaceEvent] { events.filter {
        if ["request", "response", "transport", "tool", "phase"].contains($0.kind) { return false }
        return $0.kind != "result" || !["get_workspace", "get_canvas_image", "list_fonts", "list_frame_styles", "inspect_layers", "validate_layout"].contains(where: $0.title.hasPrefix)
    } }
    static func build(_ events: [DiaryAIWorkspaceEvent]) -> [Self] {
        var groups: [Self] = []
        for event in events {
            if groups.isEmpty || event.kind == "phase" {
                groups.append(.init(id: event.id, title: event.kind == "phase" ? event.title : (events.contains { $0.kind == "phase" } ? "准备与恢复" : "制作过程"), events: []))
            }
            groups[groups.count - 1].events.append(event)
        }
        return groups
    }
}

struct DiaryAIActivityCard: View {
    let group: DiaryAIActivityGroup
    let running: Bool
    @State private var expanded = true
    private var completed: Bool { group.events.contains { $0.kind == "batch" || $0.kind == "complete" || $0.kind == "plan" || $0.kind == "album" } }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(group.summaries) { event in
                    details(event)
                }
                if running { Label("正在处理，画布会随提交更新", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary) }
                if group.requests > 0 {
                    DisclosureGroup("AI 请求与技术详情 · \(group.requests) 次") {
                        ForEach(rounds) { round in
                            DisclosureGroup {
                                ForEach(round.events) { details($0) }
                            } label: { Text(round.title).font(.subheadline) }
                        }
                    }.font(.subheadline).padding(.top, 4)
                }
            }.padding(.top, 10)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: completed ? "checkmark.circle.fill" : running ? "circle.dotted" : group.issues > 0 ? "exclamationmark.circle" : "circle")
                    .foregroundStyle(completed ? Color.accentColor : group.issues > 0 ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.headline)
                    Text("\(completed ? "已完成" : running ? "处理中" : group.issues > 0 ? "需要处理" : "已记录") · \(group.requests) 次 AI 请求\(group.issues > 0 ? " · \(group.issues) 条异常记录" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private var rounds: [DiaryAIActivityGroup] {
        var result: [DiaryAIActivityGroup] = []
        for event in group.events.filter({ ["request", "response", "transport", "tool", "result", "error"].contains($0.kind) }) {
            if result.isEmpty || event.kind == "request" { result.append(.init(id: event.id, title: "请求 \(result.count + 1)", events: [])) }
            result[result.count - 1].events.append(event)
        }
        return result
    }
    private func details(_ event: DiaryAIWorkspaceEvent) -> some View {
        DisclosureGroup {
            Text(event.detail).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            if !event.images.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(event.images.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().frame(width: 140, height: 100) }
                        }
                    }
                }
            }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: event.kind == "error" ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(event.kind == "error" ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.subheadline)
                    Text(event.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
