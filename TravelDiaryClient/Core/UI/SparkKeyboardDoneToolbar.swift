import SwiftUI
import UIKit

/// 在系统键盘上方显示「完成」，用于收起第一响应者（与 `TextField` / `TextEditor` 的 `.toolbar(placement: .keyboard)` 一致）。
///
/// 对 `UITextView`（如 `UIViewRepresentable`）同样有效：在 `dismiss` 中调用 `SparkKeyboardDismiss.endEditing()` 即可。
public struct SparkKeyboardDoneToolbar: ViewModifier {
    public let dismiss: () -> Void

    public init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }

    public func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done"), action: dismiss)
            }
            // ✅ 正确：键盘关闭按钮（单独 ToolbarItem + .keyboard）
//              ToolbarItem(placement: .keyboard) {
//                  Button(L10n.text("common.done"), action: dismiss)
//              }
        }
    }
}

public extension View {
    func sparkKeyboardDoneToolbar(dismiss: @escaping () -> Void) -> some View {
        modifier(SparkKeyboardDoneToolbar(dismiss: dismiss))
    }
}

/// 收起键盘的常用入口，供 `sparkKeyboardDoneToolbar` 的 `dismiss` 闭包使用。
public enum SparkKeyboardDismiss {
    public static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
