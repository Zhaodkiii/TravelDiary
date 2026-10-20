import SwiftUI

struct DiaryTransformToolContent: View {
    @ObservedObject var session: DiaryEditorSession
    var body: some View {
        HStack(spacing: 0) {
            ForEach(DiaryTransformMode.allCases) { mode in
                Button { session.setTransformMode(mode) } label: {
                    VStack(spacing: 7) {
                        Image(systemName: mode.symbol).font(.system(size: 22))
                        Text(mode.title).font(.caption)
                    }
                    .frame(maxWidth: .infinity).frame(minHeight: 64)
                    .foregroundStyle(session.transformDraft?.mode == mode ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(session.transformDraft?.mode == mode ? [.isSelected] : [])
                .accessibilityIdentifier("diary.transform.\(mode.rawValue)")
            }
            Divider().frame(height: 32).padding(.horizontal, 6)
            Button { session.resetFreeTransform() } label: {
                VStack(spacing: 7) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 22))
                    Text("重置").font(.caption)
                }.frame(maxWidth: .infinity).frame(minHeight: 64)
            }
            .buttonStyle(.plain).accessibilityLabel("恢复进入自由变形时的状态")
        }
        .padding(.horizontal, 16)
    }
}
