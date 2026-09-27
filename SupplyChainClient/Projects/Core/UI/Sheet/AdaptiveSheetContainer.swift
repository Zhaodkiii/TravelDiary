import SwiftUI

/// Reusable sheet container for compact picker-style sheets.
enum AdaptiveSheetToolbarPlacement: Equatable {
    case top
    case bottom
    case hidden
}

struct AdaptiveSheetContainer<Content: View>: View {
    let content: Content
    let cancelTitle: String
    let confirmTitle: String
    let cancelColor: Color
    let confirmColor: Color
    let showConfirmButton: Bool
    let fixedHeight: CGFloat?
    let toolbarHeight: CGFloat
    let contentVerticalPadding: CGFloat
    let toolbarPlacement: AdaptiveSheetToolbarPlacement
    let dismissOnConfirm: Bool
    let onCancel: () -> Void
    let onConfirm: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        cancelTitle: String = L10n.text("common.cancel"),
        confirmTitle: String = L10n.text("common.done"),
        cancelColor: Color = .secondary,
        confirmColor: Color = .accentColor,
        showConfirmButton: Bool = true,
        fixedHeight: CGFloat? = nil,
        toolbarHeight: CGFloat = 68,
        contentVerticalPadding: CGFloat = 20,
        toolbarPlacement: AdaptiveSheetToolbarPlacement = .top,
        dismissOnConfirm: Bool = true,
        onCancel: @escaping () -> Void = {},
        onConfirm: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.cancelColor = cancelColor
        self.confirmColor = confirmColor
        self.showConfirmButton = showConfirmButton
        self.fixedHeight = fixedHeight
        self.toolbarHeight = toolbarHeight
        self.contentVerticalPadding = contentVerticalPadding
        self.toolbarPlacement = toolbarPlacement
        self.dismissOnConfirm = dismissOnConfirm
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if toolbarPlacement == .top {
                toolbar
            }

            content
                .padding(.vertical, contentVerticalPadding)

            if toolbarPlacement == .bottom {
                toolbar
            }
        }
        .presentationDetents(
            fixedHeight != nil
                ? [.height(fixedHeight! + toolbarHeight)]
                : [.medium, .large]
        )
        .presentationDragIndicator(.visible)
    }

    private var toolbar: some View {
        HStack {
            Button(cancelTitle) {
                onCancel()
                dismiss()
            }
            .foregroundColor(cancelColor)

            Spacer()

            if showConfirmButton, let onConfirm {
                Button(confirmTitle) {
                    onConfirm()
                    if dismissOnConfirm {
                        dismiss()
                    }
                }
                .foregroundColor(confirmColor)
                .fontWeight(.medium)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

extension AdaptiveSheetContainer {
    static func fixed(
        height: CGFloat,
        cancelTitle: String = L10n.text("common.cancel"),
        confirmTitle: String = L10n.text("common.done"),
        cancelColor: Color = .secondary,
        confirmColor: Color = .accentColor,
        onCancel: @escaping () -> Void = {},
        onConfirm: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> AdaptiveSheetContainer {
        AdaptiveSheetContainer(
            cancelTitle: cancelTitle,
            confirmTitle: confirmTitle,
            cancelColor: cancelColor,
            confirmColor: confirmColor,
            fixedHeight: height,
            dismissOnConfirm: true,
            onCancel: onCancel,
            onConfirm: onConfirm,
            content: content
        )
    }
}
