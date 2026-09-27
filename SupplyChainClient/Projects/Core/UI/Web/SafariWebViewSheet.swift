import SwiftUI

#if canImport(UIKit)
import SafariServices

/// Presents a URL in `SFSafariViewController` (used for privacy policy, terms of service, etc.).
struct SafariWebViewSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true

        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredBarTintColor = UIColor.systemBackground
        controller.preferredControlTintColor = UIColor.systemBlue
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

struct IdentifiableURL: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}
