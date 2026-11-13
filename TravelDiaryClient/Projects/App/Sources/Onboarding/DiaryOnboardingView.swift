import SwiftUI

/// A sample preview followed by a handoff to the mounted recording home.
struct DiaryOnboardingView: View {
    var isPreparingHome = false
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var showDetails = false

    private let ink = Color(red: 0.14, green: 0.15, blue: 0.13)
    private let yellow = Color(red: 1, green: 0.79, blue: 0.28)
    private let titles = ["把旅行，留在纸上", "看看一页旅行的模样", "把手艺与风景一起收藏", "选一个喜欢的风格"]
    private let captions = [
        "照片、票根和一句心情，\n拼成值得翻看的旅行手帐。",
        "喜洲古镇\n让照片和旅途里的小细节待在一起。",
        "周城扎染\n把蓝白纹样与旅行记忆留在同一页。",
        "点击风格，开始制作你的旅行手帐。"
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .opacity(page == 0 ? 0 : 1)
                    .disabled(page == 0 || isPreparingHome)
                    .accessibilityLabel("上一步")
                    Spacer()
                    Text("旅行手帐")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(yellow, in: Capsule())
                    Spacer()
                    Button(page == 3 ? "先逛逛" : "跳过", action: onFinish)
                        .font(.system(size: 14))
                        .frame(minWidth: 44, minHeight: 44)
                        .disabled(isPreparingHome)
                }
                .padding(.horizontal, 18)

                if page == 3 {
                    stylePicker
                } else {
                ScrollView {
                    VStack(spacing: 24) {
                        preview
                            .frame(height: max(230, min(geometry.size.height * 0.49, 450)))
                            .padding(.top, 12)
                        VStack(spacing: 12) {
                            Text(titles[page])
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(captions[page])
                                .font(.system(size: 16))
                                .foregroundStyle(ink.opacity(0.6))
                                .lineSpacing(5)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        if page < 3 {
                            Button("放大看看", systemImage: "arrow.up.left.and.arrow.down.right") {
                                showDetails = true
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                    }.padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)

                VStack(spacing: 22) {
                    HStack(spacing: 8) {
                        ForEach(0..<4) { index in
                            Circle().fill(index == page ? ink : ink.opacity(0.16))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("第 \(page + 1) 页，共四页")
                    Button {
                        if page == 3 { onFinish() }
                        else {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { page += 1 }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isPreparingHome { ProgressView().tint(yellow) }
                            Text(isPreparingHome ? "正在准备首页…" : ["看看样册", "继续", "选择风格", "先逛逛"][page])
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(yellow)
                        .frame(maxWidth: .infinity).frame(minHeight: 54)
                        .background(ink, in: Capsule())
                    }
                    .disabled(isPreparingHome)
                    .accessibilityIdentifier("onboarding.next")
                }
                .padding(.horizontal, 30).padding(.top, 12).padding(.bottom, 20)
                }
            }
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
        .preferredColorScheme(.light)
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                preview.padding(20)
                    .navigationTitle(["龙龛与洱海湖岸", "喜洲古镇", "周城扎染"][min(page, 2)])
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showDetails = false }
                        }
                    }
            }
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

    private var preview: some View {
        Image("OnboardingSpread" + String(min(page, 2)))
            .resizable().scaledToFit()
            .padding(18)
            .shadow(color: ink.opacity(0.13), radius: 12, y: 8)
            .accessibilityLabel(["龙龛与洱海湖岸完整跨页", "喜洲古镇完整跨页", "周城扎染完整跨页"][min(page, 2)])
    }
}
