import SwiftUI

extension View {
    func scrollContentBackgroundIfAvailable(_ visibility: Visibility) -> some View {
        scrollContentBackground(visibility)
    }

    func sparkInputPresentationChromeIfAvailable() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    func defaultScrollAnchorIfAvailable(_ anchor: UnitPoint) -> some View {
        if #available(iOS 17.0, *) {
            defaultScrollAnchor(anchor)
        } else {
            self
        }
    }

    func textInputAutocapitalizationIfAvailable(_ autocapitalization: TextInputAutocapitalization) -> some View {
        textInputAutocapitalization(autocapitalization)
    }

    func autocorrectionDisabledIfAvailable() -> some View {
        autocorrectionDisabled()
    }
}
