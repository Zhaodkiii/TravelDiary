import SwiftUI

#if canImport(UIKit)
import SafariServices

/// Presents a URL in `SFSafariViewController` (used for privacy policy, terms of service, etc.).
struct SafariWebViewSheet: UIViewControllerRepresentable {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: { dismiss() }) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        private let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            // Safari 的关闭按钮也必须清除 SwiftUI 的 sheet 状态。
            onFinish()
        }
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.preferredBarTintColor = UIColor.systemBackground
        controller.preferredControlTintColor = UIColor.systemBlue
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

struct IdentifiableURL: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
}
