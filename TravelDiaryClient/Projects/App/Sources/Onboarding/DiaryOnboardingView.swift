import SwiftUI

/// A sample preview followed by a handoff to the mounted recording home.
struct DiaryOnboardingView: View {
    var isPreparingHome = false
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = Self.initialPage
    @State private var requestedSpread = min(Self.initialPage, 3)
    @State private var isTurning = false
    @State private var assembly = DiaryOnboardingAssembly(initialSpread: min(Self.initialPage, 3))

    private static var initialPage: Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-diary-onboarding-page"),
           let value = arguments.dropFirst(flag + 1).first.flatMap(Int.init),
           (1...5).contains(value) {
            return value - 1
        }
        #endif
        return 0
    }

    private let ink = Color(red: 0.14, green: 0.15, blue: 0.13)
    private let yellow = Color(red: 1, green: 0.79, blue: 0.28)
    private let buttonFill = Color(red: 0.15, green: 0.145, blue: 0.135)
    private let buttonInk = Color(red: 0.99, green: 0.98, blue: 0.96)
    private let titles = ["把旅行，留在纸上", "把相爱，写成我们的故事", "把这一岁，好好珍藏", "陪你长大，记住每一步"]
    private let captions = [
        "收藏大理的风景，也收藏当时的心情。",
        "从很高兴认识你，到一起走过的每一天。",
        "照片里的笑容，是送给新一岁的礼物。",
        "把成长的小小瞬间，装订成家的回忆。"
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button {
                        navigate(to: page - 1)
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .opacity(page == 0 ? 0 : 1)
                    .disabled(page == 0 || isPreparingHome || isTurning || (page < 4 && !assembly.canNavigate))
                    .accessibilityLabel("上一步")
                    Spacer()
                    Text(["大理", "爱情", "生日", "亲子", "手帐风格"][page])
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(yellow, in: Capsule())
                    Spacer()
                    Button("跳过", action: onFinish)
                        .font(.system(size: 14))
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isPreparingHome)
                }
                .padding(.horizontal, 18)


                if page == 4 {
                    stylePicker
                } else {
                    GeometryReader { stage in
                        ZStack(alignment: .bottom) {
                            preview
                            VStack(spacing: 12) {
                                Text(titles[page])
                                    .font(.system(size: stage.size.height < 450 ? 23 : 28, weight: .bold, design: .rounded))
                                Text(captions[page])
                                    .font(.system(size: stage.size.height < 450 ? 14 : 16))
                                    .foregroundStyle(ink.opacity(0.6))
                                    .lineSpacing(5)
                            }
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.bottom, stage.size.height * 0.17)
                            .opacity(isTurning || !assembly.showsCopy ? 0 : 1)
                            .accessibilityHidden(isTurning || !assembly.showsCopy)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: assembly.showsCopy)
                        }
                        .frame(width: stage.size.width, height: stage.size.height)
                        .clipped()
                    }

                }

                VStack(spacing: 22) {
                    HStack(spacing: 8) {
                        ForEach(0..<5) { index in
                            Circle().fill(index == page ? ink : ink.opacity(0.16))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(page + 1) 页，共五页")
                    if page < 4 {
                        Button {
                            if assembly.phase == .floating { assembly.bind() }
                            else {
                                navigate(to: page + 1)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if isPreparingHome { ProgressView().tint(buttonInk) }
                                Text(isPreparingHome ? "正在准备首页…" : assembly.buttonTitle)
                            }
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(buttonInk)
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(buttonFill)
                        .disabled(isPreparingHome || isTurning || !assembly.canAct)
                        .accessibilityIdentifier("onboarding.next")
                    }
                }
                .padding(.horizontal, 30).padding(.top, 12).padding(.bottom, 20)
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onDisappear { assembly.suspend() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-onboarding-verify") {
                for target in 0..<4 {
                    while !assembly.canAct { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
                    recordCheck("ONBOARDING_CHECK floating page=\(page) phase=\(assembly.phase)")
                    try? await Task.sleep(for: .seconds(2))
                    assembly.bind()
                    while !assembly.showsCopy { try? await Task.sleep(for: .milliseconds(100)); if Task.isCancelled { return } }
                    recordCheck("ONBOARDING_CHECK bound page=\(page) phase=\(assembly.phase)")
                    try? await Task.sleep(for: .seconds(2))
                    if target < 3 { navigate(to: target + 1) }
                }
                navigate(to: 4)
                recordCheck("ONBOARDING_CHECK styles page=\(page)")
                try? await Task.sleep(for: .seconds(2))
                navigate(to: 3)
                recordCheck("ONBOARDING_CHECK return page=\(page) phase=\(assembly.phase)")

            }
            #endif
        }

    }

    private var stylePicker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("选一个喜欢的风格")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("选一种风格，进入制作")
                        .font(.system(size: 16))
                        .foregroundStyle(ink.opacity(0.6))
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 24) {
                    ForEach(DiaryAIPageStyle.allCases, id: \.self) { style in
                        Button {
                            UserDefaults.standard.set(style.rawValue, forKey: "diary.onboarding.pendingStyle")
                            onFinish()
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image("TravelStyle-" + style.rawValue)
                                    .resizable().scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .background(.white.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                HStack(spacing: 6) {
                                    Text(style.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(ink.opacity(0.5))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingHome)
                        .accessibilityLabel(style.name)
                        .accessibilityHint("进入此风格的制作流程")
                    }
                }
                if isPreparingHome {
                    ProgressView("正在准备制作入口…")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("onboarding.styles")
    }

    private func recordCheck(_ message: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("onboarding-verification.txt")
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (old + message + "\n").write(to: url, atomically: true, encoding: .utf8)
    }
    private func navigate(to target: Int) {
        guard !isTurning, (0..<5).contains(target), target != page,
              page == 4 || assembly.canNavigate else { return }
        if target == 4 || page == 4 {
            requestedSpread = min(target, 3)
            if target < 4 { assembly.settle(on: target) }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { page = target }
        } else if assembly.phase == .failed {
            page = target
            requestedSpread = target
        } else {
            assembly.beginTurn()
            isTurning = true
            requestedSpread = target
        }
    }

    private var preview: some View {
        DiaryOnboardingBook(requestedSpread: requestedSpread, assembly: assembly,
            onSettled: { displayed in
                guard (0..<4).contains(displayed) else { return }
                page = displayed
                requestedSpread = displayed
                isTurning = false
            })
            .padding(.horizontal, 18)
    }
}
