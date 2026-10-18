import SwiftUI

/// 数据准备完成后只收尾视觉，不延迟首页的创建和交互。
struct AppPreparationTransition<Content: View>: View {
    let isReady: Bool
    let failed: Bool
    let onRetry: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCover: Bool
    @State private var finishing = false

    init(isReady: Bool, failed: Bool, onRetry: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.isReady = isReady; self.failed = failed; self.onRetry = onRetry; self.content = content
        _showingCover = State(initialValue: !isReady)
    }
    var body: some View {
        ZStack {
            DiaryLibraryStyle.background.ignoresSafeArea()
            if isReady { content().transition(.opacity) }
            if showingCover {
                AppLaunchScreenView(finishing: finishing, failed: failed, onRetry: onRetry)
                    .opacity(finishing ? 0 : 1)
                    .allowsHitTesting(!isReady)
                    .accessibilityHidden(isReady)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.28), value: isReady)
        .task(id: isReady) {
            guard isReady else { finishing = false; showingCover = true; return }
            guard showingCover else { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.28)) { finishing = true }
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 280)) }
            catch { return }
            showingCover = false
        }
    }
}

struct AppLaunchScreenView: View {
    var finishing = false
    var failed = false
    var onRetry: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    var body: some View {
        VStack(spacing: 28) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || failed || finishing)) { context in
                let elapsed = max(0, context.date.timeIntervalSince(startedAt))
                DiaryLaunchBook(elapsed: elapsed, settled: reduceMotion || failed || finishing)
            }.frame(width: 156, height: 128).accessibilityHidden(true)
            Text(L10n.text(failed ? "app.preparing.failed" : "app.preparing.diary"))
                .font(.body).foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
            if failed, let onRetry {
                Button(L10n.text("app.preparing.retry"), action: onRetry)
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DiaryLibraryStyle.background.ignoresSafeArea())
        .tint(DiaryLibraryStyle.accent)
    }
}

/// 封面先打开，随后单页沿书脊循环翻动；无位图与外部动画资源。
struct DiaryLaunchBook: View {
    let elapsed: TimeInterval
    let settled: Bool
    private var opening: Double { settled ? 1 : min(1, elapsed / 0.65) }
    private var pagePhase: Double { settled ? 0 : max(0, elapsed - 0.65).truncatingRemainder(dividingBy: 1.8) / 1.8 }
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                leaf
                leaf
            }
            Rectangle().fill(DiaryLibraryStyle.accent.opacity(0.65)).frame(width: 2, height: 86)
            leaf
                .frame(width: 62, height: 88)
                .rotation3DEffect(.degrees(-180 * pagePhase), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.35)
                .offset(x: 31)
                .opacity(settled || elapsed < 0.65 ? 0 : 1)
            RoundedRectangle(cornerRadius: 5)
                .fill(DiaryLibraryStyle.surface)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DiaryLibraryStyle.accent, lineWidth: 2.5))
                .overlay(Image(systemName: "leaf").font(.title2).foregroundStyle(DiaryLibraryStyle.accent))
                .frame(width: 62, height: 92)
                .rotation3DEffect(.degrees(-160 * opening), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.35)
                .offset(x: 31)
                .opacity(opening >= 1 ? 0 : 1)
        }
        .frame(width: 124, height: 92)
    }
    private var leaf: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(DiaryLibraryStyle.surface)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(DiaryLibraryStyle.accent.opacity(0.85), lineWidth: 2))
            .overlay(alignment: .top) {
                VStack(spacing: 9) {
                    ForEach(0..<3) { _ in Capsule().fill(DiaryLibraryStyle.accent.opacity(0.2)).frame(height: 2) }
                }.padding(.horizontal, 11).padding(.top, 22)
            }
            .frame(width: 62, height: 88)
    }
}
