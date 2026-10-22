import SwiftUI
import UIKit

/// 作品保留原色，应用界面仅提供安静的承托面。
// SwiftUI.AsyncRenderer 会在后台线程解析动态颜色。这里必须脱离工程默认的
// MainActor 隔离，provider 也显式标为 Sendable，不能捕获界面状态。
nonisolated enum DiaryLibraryStyle {
    static let background = adaptive(0xF7F5F0, dark: 0x1C1B19)
    static let surface = adaptive(0xFFFEFB, dark: 0x282622)
    static let ink = adaptive(0x292622, dark: 0xF2EEE7)
    static let secondary = adaptive(0x706A62, dark: 0xBDB6AC)
    static let accent = adaptive(0x9C4F34, dark: 0xE9AA8E)
    static let line = adaptive(0xDDD7CE, dark: 0x49433B)

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct DiaryLibrarySearch: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(DiaryLibraryStyle.secondary)
            TextField(prompt, text: $text).submitLabel(.search).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("清除搜索").frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.leading, 14).padding(.trailing, 4).frame(minHeight: 48)
        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DiaryLibraryStyle.line.opacity(0.6)))
    }
}

struct DiaryLibraryChip: View {
    let title: String
    let selected: Bool
    var compact = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font((compact ? Font.caption2 : .caption).weight(.semibold)) }
                Text(title).font((compact ? Font.caption : .subheadline).weight(selected ? .semibold : .regular))
            }
            .padding(.horizontal, compact ? 10 : 14).frame(minHeight: compact ? 30 : 44)
            .foregroundStyle(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
            .background(selected ? DiaryLibraryStyle.accent.opacity(0.12) : DiaryLibraryStyle.surface, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct DiaryLibraryNotice: View {
    let message: String
    var actionTitle = "重试"
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "info.circle").font(.subheadline)
            if let action { Button(actionTitle, action: action).frame(minHeight: 44) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// 与现有反馈表单一致的主操作样式，不依赖系统 tint 或 controlSize 的额外内边距。
struct DiaryPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 52)
            .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : .white)
            .background(DiaryLibraryStyle.accent.opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct DiarySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 52)
            .foregroundStyle(DiaryLibraryStyle.accent)
            .background(DiaryLibraryStyle.surface.opacity(configuration.isPressed ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(DiaryLibraryStyle.line, lineWidth: 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
