import SwiftUI
import SafariServices

struct ProviderPrivacyPolicyWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        CompatibleNavigationContainer {
            ProviderPrivacyPolicySafariView(url: url)
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(L10n.text("ai_settings.providers.editor.privacy.view_policy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.close")) {
                    dismiss()
                }
            }
        }
    }
}

private struct ProviderPrivacyPolicySafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
