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
