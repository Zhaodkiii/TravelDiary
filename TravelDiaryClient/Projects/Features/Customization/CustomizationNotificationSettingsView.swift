import SwiftUI

/// 提醒偏好单独编辑；加载成功后才允许保存，避免默认值覆盖已有设置。
struct CustomizationNotificationSettingsView: View {
    let owner: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var push = PushAdapter.shared
    @State private var reminders = true
    @State private var quiet = false
    @State private var start = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var end = Calendar.current.date(from: DateComponents(hour: 8)) ?? Date()
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    private struct Preference: Decodable { let enabled: Bool; let quiet_hours: [String: String] }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { DiaryLibraryNotice(message: error) { Task { if loaded { await save() } else { await load() } } } } }
                if !loaded && !busy { Section { ProgressView("正在读取提醒设置…") } }
                Section {
                    Toggle("定制进度与成品提醒", isOn: $reminders)
                    Text("关闭提醒仍可在定制首页查看进度、领取成品。")
                        .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                }.disabled(!loaded)
                Section("免打扰") {
                    Toggle("使用静默时段", isOn: $quiet)
                    if quiet {
                        DatePicker("开始时间", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("结束时间", selection: $end, displayedComponents: .hourAndMinute)
                        Text("按 \(TimeZone.current.identifier) 时区执行，可跨越午夜。")
                            .font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                }.disabled(!loaded)
                Section("系统通知") {
                    if push.notificationsEnabled == true {
                        Label("系统通知已开启", systemImage: "checkmark.circle")
                    } else {
                        Button("开启系统通知") {
                            Task { _ = await push.requestAuthorizationIfNotDetermined(openSettingsIfDenied: true) }
                        }
                    }
                    if let problem = push.registrationError { Text(problem).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary) }
                }
            }
            .disabled(busy)
            .scrollContentBackground(.hidden).background(DiaryLibraryStyle.background)
            .foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
            .navigationTitle("定制提醒").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { await save() } }.disabled(!loaded || busy) }
            }
            .overlay { if busy { ProgressView("正在保存…") } }
            .task { await load(); await push.refreshRegistration() }
        }
    }
    private func load() async {
        do {
            let value: Preference = try await CustomizationService.shared.request("preferences/", owner: owner)
            reminders = value.enabled; quiet = !value.quiet_hours.isEmpty
            start = time(value.quiet_hours["start"] ?? "22:00")
            end = time(value.quiet_hours["end"] ?? "08:00")
            loaded = true; error = nil
        } catch { self.error = "提醒设置读取失败，请稍后重试。" }
    }
    private func save() async {
        guard loaded, !busy else { return }
        if quiet && formatted(start) == formatted(end) { error = "静默时段的开始和结束时间不能相同。"; return }
        busy = true; defer { busy = false }
        do {
            struct Saved: Decodable { let enabled: Bool }
            let _: Saved = try await CustomizationService.shared.request("preferences/", owner: owner, method: .patch,
                body: ["enabled": reminders, "quiet_hours": quiet ? ["start": formatted(start), "end": formatted(end), "timezone": TimeZone.current.identifier] : [:]])
            dismiss()
        } catch { self.error = "设置尚未保存：" + error.localizedDescription }
    }
    private func time(_ raw: String) -> Date {
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        return Calendar.current.date(from: DateComponents(hour: parts.first ?? 22, minute: parts.count > 1 ? parts[1] : 0)) ?? Date()
    }
    private func formatted(_ value: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
