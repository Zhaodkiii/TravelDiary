import SwiftUI

/// A guided demonstration only; never creates or modifies a user's books.
struct DiaryOnboardingView: View {
    var isPreparingHome = false
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var artwork: DiaryOnboardingArtwork?
    @State private var failed = false
    @State private var stage = 0
    @State private var generation = 0
    @State private var progress: CGFloat = 0
    @State private var revealed = 0
    @State private var ready = false
    @State private var bookOpen = false

    private let ink = Color(red: 0.16, green: 0.23, blue: 0.21)
    private let accent = Color(red: 0.39, green: 0.46, blue: 0.30)
    private let titles = ["把喜欢的，收集在一起", "先为回忆，铺一个底色", "把沿途风景，放进这一页", "让细节，长出旅行的模样", "最后，写下几句心情"]
    private let subtitles = ["照片、贴纸，还有旅途里的小片段。", "从一张空白纸，慢慢画出氛围。", "用照片，留住山野与同行的人。", "一枚邮戳，一朵花，都是记忆。", "把脚步放慢，把山风记住。"]
    private let buttons = ["开始制作", "贴上照片", "加点装饰", "写下心情", "进入我的手帐"]
    private let steps = ["收集", "背景", "照片", "贴纸", "文字"]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 16) {
                        HStack(spacing: 7) {
                            Text("TRAVEL DIARY").tracking(3)
                            Rectangle().frame(width: 24, height: 1)
                            Text("一页手帐的诞生")
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(accent).padding(.top, 18)
                        stageArtwork
                            .frame(height: max(240, min(geometry.size.height * 0.51, 510)))
                        VStack(spacing: 12) {
                            Text(titles[stage]).font(.system(size: 27, weight: .semibold, design: .serif))
                                .foregroundStyle(ink).minimumScaleFactor(0.75)
                            Text(subtitles[stage]).font(.system(size: 15)).foregroundStyle(ink.opacity(0.55))
                        }.multilineTextAlignment(.center).padding(.horizontal, 22)
                        HStack(spacing: 6) {
                            Image(systemName: stage == 0 ? "square.stack.3d.up" : stage == 1 ? "paintbrush.pointed" : stage == 2 ? "photo" : stage == 3 ? "seal" : "pencil.line")
                            Text(stage == 0 ? "以「雨崩，慢一点」为例" : ready ? "这一步完成了，继续看看吧" : "正在制作这一页…")
                        }.font(.caption).foregroundStyle(accent).padding(.top, 4)
                    }.frame(maxWidth: 760).frame(maxWidth: .infinity).padding(.bottom, 22)
                }.scrollIndicators(.hidden)
                footer
            }
        }
        .background {
            Color(red: 0.97, green: 0.96, blue: 0.93)
                .overlay {
                    Canvas { context, size in
                        for x in stride(from: 12.0, to: size.width, by: 22) {
                            for y in stride(from: 12.0, to: size.height, by: 22) {
                                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.3, height: 1.3)), with: .color(ink.opacity(0.08)))
                            }
                        }
                    }.accessibilityHidden(true)
                }.ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .task {
            guard artwork == nil else { return }
            do { artwork = try await DiaryOnboardingArtwork.load(); generation += 1 }
            catch is CancellationError { }
            catch { failed = true }
        }
        .task(id: "\(stage)-\(generation)") { await animateStage() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !ready { generation += 1 }
        }
        .onChange(of: reduceMotion) { _, _ in generation += 1 }
        .accessibilityAction(named: "下一步") { if ready { advance() } }
    }

    private var header: some View {
        HStack {
            Button { stage -= 1 } label: {
                Image(systemName: "arrow.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }.disabled(stage == 0).opacity(stage == 0 ? 0 : 1).accessibilityLabel("上一步")
            Spacer()
            Text("\(stage + 1) / 5").font(.caption.monospacedDigit()).foregroundStyle(accent)
            Spacer()
            Button(isPreparingHome ? "准备中" : "跳过") { onFinish() }.disabled(isPreparingHome).font(.system(size: 14)).frame(minWidth: 44, minHeight: 44)
        }.foregroundStyle(ink).padding(.horizontal, 16)
    }

    @ViewBuilder private var stageArtwork: some View {
        if let artwork {
            GeometryReader { proxy in
                let width = min(proxy.size.width - 42, 680)
                let height = width * artwork.size.height / artwork.size.width
                let scale = width / artwork.size.width
                ZStack {
                    // The same open book stays on screen throughout all four construction stages.
                    RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.48, green: 0.49, blue: 0.36))
                        .padding(.horizontal, -7).padding(.vertical, -5).offset(y: 5)
                        .opacity(stage == 0 ? 0 : 1)
                    Rectangle().fill(Color(red: 1, green: 0.99, blue: 0.96))
                        .shadow(color: ink.opacity(0.15), radius: 18, y: 12).opacity(stage == 0 ? 0 : 1)
                    ForEach(artwork.pieces) { piece in
                        pieceView(piece, scale: scale, width: width, height: height)
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.08), .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12).opacity(stage == 0 ? 0 : 1)
                }
                .frame(width: width, height: height)
                .rotation3DEffect(.degrees(stage == 1 && !bookOpen ? 65 : 0), axis: (x: 1, y: 0, z: 0))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel("雨崩旅行手帐，\(steps[stage])阶段\(ready ? "已完成" : "演示中")")
        } else if failed {
            ContentUnavailableView {
                Label("示例暂时无法展示", systemImage: "book.closed")
            } description: { Text("可以直接进入手帐，稍后在设置里重看引导。") }
        } else {
            ProgressView("正在准备旅行素材…").tint(accent)
        }
    }

    private func pieceView(_ piece: DiaryOnboardingArtwork.Piece, scale: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        let collecting = stage == 0
        let visible = collecting ? (piece.stage == 2 || piece.stage == 3) : piece.stage < stage || (piece.stage == stage && (stage == 1 || piece.order < revealed))
        let index = piece.order
        let column = index % 3
        let row = index / 3
        let x = collecting ? width * (0.18 + CGFloat(column) * 0.32) + (piece.stage == 3 ? width * 0.08 : 0) : piece.bounds.midX * scale
        let y = collecting ? height * (0.16 + CGFloat(row) * 0.42) + (piece.stage == 3 ? height * 0.24 : 0) : piece.bounds.midY * scale
        let targetWidth = piece.bounds.width * scale
        let collectionScale = min(width * (piece.stage == 2 ? 0.26 : 0.17) / max(1, targetWidth), 1.5)
        return Image(uiImage: piece.image).resizable()
            .frame(width: targetWidth, height: piece.bounds.height * scale)
            .mask {
                if piece.stage == 1 { DiaryOnboardingBrushMask(progress: stage > 1 ? 1 : progress) }
                else if piece.stage == 4 {
                    GeometryReader { mask in
                        Rectangle().frame(width: visible ? mask.size.width : 0)
                            .animation(reduceMotion ? nil : .linear(duration: 0.55), value: visible)
                    }
                } else { Rectangle() }
            }
            .scaleEffect(collecting ? collectionScale : visible ? 1 : 1.12)
            .rotationEffect(.degrees(collecting ? Double(index % 3 - 1) * 9 : visible ? 0 : -7))
            .opacity(visible ? 1 : 0)
            .offset(y: !visible && piece.stage > 1 ? -26 : 0)
            .position(x: x, y: y)
            .animation(reduceMotion ? nil : .spring(response: 0.65, dampingFraction: 0.82), value: stage)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8), value: revealed)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                ForEach(0..<5) { index in
                    VStack(spacing: 7) {
                        Capsule().fill(index <= stage ? accent : ink.opacity(0.10)).frame(height: 3)
                        Text(steps[index]).font(.system(size: 11, weight: index == stage ? .semibold : .regular))
                            .foregroundStyle(index == stage ? ink : ink.opacity(0.4))
                    }.frame(maxWidth: .infinity)
                    if index < 4 { Spacer().frame(width: 10) }
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("步骤 \(stage + 1)，共五步，\(steps[stage])")
            Button(action: advance) {
                HStack(spacing: 12) {
                    if isPreparingHome || (!ready && !failed) { ProgressView().tint(.white) }
                    Text(isPreparingHome ? "正在准备主页…" : failed ? "进入我的手帐" : ready ? buttons[stage] : stage == 1 ? "正在铺开底色…" : "正在制作…")
                    if !isPreparingHome && (ready || failed) { Image(systemName: "arrow.right") }
                }.font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(ink.opacity(ready || failed ? 1 : 0.45), in: Capsule())
            }.disabled(isPreparingHome || (!ready && !failed)).accessibilityIdentifier("onboarding.next")
            HStack {
                Button("重播本步", systemImage: "arrow.counterclockwise") { generation += 1 }
                    .disabled(artwork == nil)
                Spacer()
                if !ready && artwork != nil {
                    Button("直接看效果") { completeStage() }
                } else {
                    Text("照片 · 贴纸 · 手写的温度")
                }
            }.font(.system(size: 11)).foregroundStyle(ink.opacity(0.5))
        }.padding(.horizontal, 28).padding(.top, 16).padding(.bottom, 16)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
    }

    private func advance() {
        guard !isPreparingHome, ready || failed else { return }
        if failed || stage == 4 { onFinish() }
        else {
            ready = false
            progress = 0
            revealed = 0
            stage += 1
        }
    }

    private func completeStage() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { bookOpen = stage > 0; progress = 1; revealed = 100; ready = true }
    }

    private func animateStage() async {
        guard let artwork else { return }
        ready = false
        progress = 0
        revealed = 0
        if reduceMotion || stage == 0 { completeStage(); return }
        do {
            if stage == 1 {
                bookOpen = false
                try await Task.sleep(for: .milliseconds(100))
                guard !ready else { return }
                withAnimation(.easeOut(duration: 0.55)) { bookOpen = true }
                try await Task.sleep(for: .milliseconds(600))
                guard !ready else { return }
                withAnimation(.linear(duration: 2.8)) { progress = 1 }
                try await Task.sleep(for: .seconds(2.9))
            } else {
                let count = artwork.pieces.filter { $0.stage == stage }.count
                for index in 0..<count {
                    try await Task.sleep(for: .milliseconds(stage == 4 ? 220 : 300))
                    guard !ready else { return }
                    revealed = index + 1
                }
                try await Task.sleep(for: .milliseconds(600))
            }
            try Task.checkCancellation()
            ready = true
        } catch { /* Step changes and dismissal cancel the previous schedule. */ }
    }
}

#Preview { DiaryOnboardingView(onFinish: {}) }
