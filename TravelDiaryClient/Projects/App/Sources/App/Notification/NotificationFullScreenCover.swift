import SwiftUI

extension View {
    func notificationFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        store: NotificationStore,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { item in
            NotificationHostView(store: store) {
                content(item)
            }
        }
    }

    func notificationFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        store: NotificationStore,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            NotificationHostView(store: store) {
                content()
            }
        }
    }
}
