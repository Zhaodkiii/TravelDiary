import SwiftUI

struct NotificationHostView<Content: View>: View {
    @ObservedObject var store: NotificationStore
    let content: Content

    init(store: NotificationStore, @ViewBuilder content: () -> Content) {
        self.store = store
        self.content = content()
    }

    var body: some View {
        content
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if let banner = store.currentBanner {
                        NotificationBannerView(
                            message: banner,
                            onTap: store.tapAction(for: banner.id),
                            onDismiss: { store.dismissBanner(id: banner.id) }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if let toast = store.currentToast {
                        NotificationToastView(message: toast)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
            }
            .alert(
                store.currentAlert?.title ?? L10n.text("common.notice"),
                isPresented: Binding(
                    get: { store.currentAlert != nil },
                    set: { if $0 == false { store.dismissAlert(id: store.currentAlert?.id) } }
                ),
                presenting: store.currentAlert
            ) { _ in
                Button(L10n.text("common.ok")) {
                    store.dismissAlert(id: store.currentAlert?.id)
                }
            } message: { alert in
                Text(alert.message)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.currentBanner?.id)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: store.currentToast?.id)
    }
}

private struct NotificationToastView: View {
    let message: NotificationMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: message.level))
                .foregroundStyle(color(for: message.level))
            Text(message.message)
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        )
    }
}

private struct NotificationBannerView: View {
    let message: NotificationMessage
    let onTap: (@MainActor @Sendable () -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: message.level))
                .foregroundStyle(color(for: message.level))
            VStack(alignment: .leading, spacing: 2) {
                if let title = message.title, title.isEmpty == false {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(message.message)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onTap else { return }
            onDismiss()
            onTap()
        }
    }
}

private func symbol(for level: NotificationLevel) -> String {
    switch level {
    case .success:
        return "checkmark.circle.fill"
    case .error:
        return "xmark.octagon.fill"
    case .warning:
        return "exclamationmark.triangle.fill"
    case .info:
        return "info.circle.fill"
    }
}

private func color(for level: NotificationLevel) -> Color {
    switch level {
    case .success:
        return Color(uiColor: .systemGreen)
    case .error:
        return Color(uiColor: .systemRed)
    case .warning:
        return Color(uiColor: .systemOrange)
    case .info:
        return Color(uiColor: .systemBlue)
    }
}
