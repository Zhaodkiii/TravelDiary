import SwiftUI

//extension View {
//    /// Hide the root `TabView` bar while this view is displayed as a pushed detail page.
//    func hidesMainTabBarWhenPushed() -> some View {
//        modifier(MainTabBarVisibilityModifier())
//    }
//}
//
//private struct MainTabBarVisibilityModifier: ViewModifier {
//    func body(content: Content) -> some View {
//        content.background(LegacyTabBarHiddenHostingBridge())
//    }
//}

extension View {
    /// Hide the root `TabView` bar while this view is displayed as a pushed detail page.
    @ViewBuilder
    func hidesMainTabBarWhenPushed() -> some View {
        self.toolbar(.hidden, for: .tabBar)
    }
}
