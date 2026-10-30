import SwiftUI

/// Content cards opt into the native, interactive zoom transition. Each link
/// owns its namespace so the same content can appear in multiple galleries.
struct ZoomNavigationLink<Label: View, Destination: View>: View {
    @Namespace private var transition
    private let destination: () -> Destination
    private let label: () -> Label

    init(
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
                .contentZoomTransition(sourceID: "card", in: transition)
        } label: {
            label()
                .matchedTransitionSource(id: "card", in: transition)
        }
    }
}

extension View {
    /// A nil namespace preserves ordinary navigation for routes opened without
    /// a visible source card, such as notifications and creation completions.
    func contentZoomTransition<ID: Hashable>(sourceID: ID, in namespace: Namespace.ID?) -> some View {
        modifier(ContentZoomTransition(sourceID: sourceID, namespace: namespace))
    }

    @ViewBuilder
    func contentZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}

private struct ContentZoomTransition<ID: Hashable>: ViewModifier {
    let sourceID: ID
    let namespace: Namespace.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}
