import SwiftUI

/// Shared inline tool shell. The editor owns presentation/header visibility;
/// each tool supplies its content and explicit back/done semantics.
struct DiaryEditorToolPanel<Content: View>: View {
    let title: String
    let onBack: () -> Void
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.compact.down" : "chevron.compact.up")
                    .font(.title3.weight(.semibold))
                    .frame(width: 60, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(expanded ? "收起操作面板" : "展开操作面板")
            if expanded { content().padding(.bottom, 8) }
            DiaryEditorToolFooter(title: title, onBack: onBack, onDone: onDone)
        }
        .foregroundStyle(DiaryLibraryStyle.ink)
        .background(DiaryLibraryStyle.background)
        .tint(DiaryLibraryStyle.accent)
    }
}

/// Shared by inline layer tools and native material sheets.
struct DiaryEditorToolFooter: View {
    let title: String
    let onBack: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            footerButton("返回", symbol: "chevron.left", action: onBack)
            Spacer()
            Text(title).font(.headline)
            Spacer()
            footerButton("完成", symbol: "checkmark", action: onDone)
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        .foregroundStyle(DiaryLibraryStyle.ink)
        .background(DiaryLibraryStyle.background)
    }

    private func footerButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2)
                .frame(width: 48, height: 48)
                .background(DiaryLibraryStyle.surface, in: Circle())
        }.accessibilityLabel(title)
    }
}

/// Add future tools here; their UI stays inside the same panel shell.
enum DiaryEditorTool: String, Identifiable {
    case layers
    var id: Self { self }
    var title: String { "图层" }
}
