import QuickLook
import SwiftUI

/// Thin SwiftUI bridge for QLPreviewController.
struct QuickLookPreviewBridge: UIViewControllerRepresentable {
    let inputs: [FilePreviewInput]
    let startIndex: Int
    var onDismiss: (() -> Void)?

    init(
        inputs: [FilePreviewInput],
        startIndex: Int = 0,
        onDismiss: (() -> Void)? = nil
    ) {
        self.inputs = inputs
        self.startIndex = startIndex
        self.onDismiss = onDismiss
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.currentPreviewItemIndex = safeStartIndex
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        if uiViewController.currentPreviewItemIndex != safeStartIndex {
            uiViewController.currentPreviewItemIndex = safeStartIndex
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(items: inputs.map { PreviewItem(url: $0.fileURL, title: $0.resolvedDisplayName) }, onDismiss: onDismiss)
    }

    private var safeStartIndex: Int {
        guard inputs.isEmpty == false else { return 0 }
        return min(max(0, startIndex), inputs.count - 1)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        fileprivate let items: [PreviewItem]
        let onDismiss: (() -> Void)?

        fileprivate init(items: [PreviewItem], onDismiss: (() -> Void)?) {
            self.items = items
            self.onDismiss = onDismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            items.count
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            items[index]
        }

        func previewControllerWillDismiss(_ controller: QLPreviewController) {
            onDismiss?()
        }
    }
}

private final class PreviewItem: NSObject, QLPreviewItem {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }

    var previewItemURL: URL? { url }
    var previewItemTitle: String? { title }
}
