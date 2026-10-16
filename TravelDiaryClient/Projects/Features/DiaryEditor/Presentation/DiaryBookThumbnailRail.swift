import SwiftUI

/// Shared thumbnail sizing, selection, and scroll behavior for diary and preset readers.
struct DiaryBookThumbnailRail<Cover: View, Leaf: View>: View {
    let hasCover: Bool
    let spreadCount: Int
    let spread: Int
    let opened: Bool
    let title: (Int) -> String
    let onClose: () -> Void
    let onSelect: (Int) -> Void
    @ViewBuilder let cover: () -> Cover
    @ViewBuilder let leaf: (Int) -> Leaf
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    if hasCover {
                        Button(action: onClose) {
                            cover().frame(width: 54, height: 76)
                                .modifier(ThumbnailCard(selected: !opened))
                        }.buttonStyle(.plain).id(-1).accessibilityLabel("外壳")
                            .accessibilityAddTraits(!opened ? .isSelected : [])
                    }
                    ForEach(0..<spreadCount, id: \.self) { index in
                        Button { onSelect(index) } label: {
                            HStack(spacing: 2) {
                                leaf(index * 2 - 1).frame(width: 50, height: 76)
                                leaf(index * 2).frame(width: 50, height: 76)
                            }.modifier(ThumbnailCard(selected: opened && spread == index))
                        }.buttonStyle(.plain).id(index).accessibilityLabel(title(index))
                            .accessibilityAddTraits(opened && spread == index ? .isSelected : [])
                    }
                }.padding(12)
            }
            .frame(height: 110)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 16).padding(.bottom, 8)
            .onChange(of: spread) { _, _ in scrollToSelection(proxy) }
            .onChange(of: opened) { _, _ in scrollToSelection(proxy) }
            .onAppear { proxy.scrollTo(opened ? spread : -1, anchor: .center) }
        }
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            proxy.scrollTo(opened ? spread : -1, anchor: .center)
        }
    }
}

private struct ThumbnailCard: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content.padding(5).background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
    }
}
