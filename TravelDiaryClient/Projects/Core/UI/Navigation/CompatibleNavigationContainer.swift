import SwiftUI

struct CompatibleNavigationContainer<Content: View>: View {
    private let content: () -> Content

    init(legacyStackStyle: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        NavigationStack {
            content()
        }
    }
}

struct CompatibleRouteNavigationContainer<Route: Hashable, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    private let content: () -> Content
    private let destination: (Route) -> Destination

    init(
        path: Binding<[Route]>,
        legacyStackStyle: Bool = false,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.content = content
        self.destination = destination
    }

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
    }
}

private struct ShakeGeometryEffect: GeometryEffect {
    var amount: CGFloat = 10
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 2), y: 0))
    }
}

private struct ShakeModifier: ViewModifier {
    let trigger: Int
    @State private var shakeAmount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeGeometryEffect(amount: 10, animatableData: shakeAmount))
            .onChange(of: trigger) { newValue in
                guard newValue > 0 else { return }
                withAnimation(.linear(duration: 0.45)) {
                    shakeAmount = 3
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    shakeAmount = 0
                }
            }
    }
}

extension View {
    func shakeOnTrigger(_ trigger: Int) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }
}
