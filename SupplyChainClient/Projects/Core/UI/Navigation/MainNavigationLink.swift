import SwiftUI

/// Project-wide replacement for `NavigationLink` that automatically hides the
/// root `TabView` bar on the pushed destination — mirroring UIKit's
/// `hidesBottomBarWhenPushed = true`.
///
/// Use this instead of `NavigationLink` for any push that happens inside a tab's
/// navigation stack, so the bottom tab bar disappears while the detail page is
/// shown and reappears when popping back, without having to remember to apply
/// `.hidesMainTabBarWhenPushed()` on every destination.
struct MainNavigationLink<Label: View, Destination: View>: View {
    private let destination: () -> Destination
    private let label: () -> Label

    init(
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.destination = destination
        self.label = label
    }

    /// Mirrors `NavigationLink(destination:label:)` where the destination is
    /// passed as an already-built view value.
    init(
        destination: Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.destination = { destination }
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination()
                .hidesMainTabBarWhenPushed()
        } label: {
            label()
        }
    }
}
