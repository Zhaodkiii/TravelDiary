import SwiftUI

/// Personal center. Account-scoped services retain ownership of transactions and data.
struct SettingsView: View {
    let session: UserSession
    let storageService: StorageService
    let onAccountEntryTap: () -> Void

    @ObservedObject private var help = HelpFeedbackService.shared
    @ObservedObject private var billing = BillingStore.shared
    @ObservedObject private var production = DiaryProductionService.shared
    @State private var membershipError = false
    @State private var refreshing = false
    @Environment(\.scenePhase) private var scenePhase

    private var owner: String { String(session.accountID) }
    private var member: MembershipStatus? { billing.owner == owner ? billing.membership : nil }
    private var pending: Bool { billing.owner == owner && billing.membershipPending }

    var body: some View {
        List {
            Section {
                Button(action: onAccountEntryTap) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(DiaryLibraryStyle.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(accountTrailingText).font(.title3.weight(.semibold))
                            Text(session.isDeviceAccount ? "可选登录，同步你的手帐" : "账户与安全")
                                .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            .foregroundStyle(DiaryLibraryStyle.secondary)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("profile.account")
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section {
                NavigationLink { MembershipPurchaseScreen(owner: owner).id(owner) } label: { membershipCard }
                    .accessibilityIdentifier("profile.membership")
                NavigationLink {
                    Form { DiaryProductionQuotaSection() }
                        .navigationTitle("制作额度").navigationBarTitleDisplayMode(.inline)
                        .tint(DiaryLibraryStyle.accent)
                } label: { PersonalSettingsRow(title: "制作额度", symbol: "sparkles", detail: quotaSummary) }
                if membershipError {
                    Button { Task { await refresh() } } label: {
                        Label("会员状态暂未更新，点此重试", systemImage: "arrow.clockwise")
                            .font(.footnote)
                    }.disabled(refreshing)
                }
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section("我的服务") {
                NavigationLink { PrintOrdersScreen(owner: owner) } label: {
                    PersonalSettingsRow(title: "印制订单", symbol: "shippingbox")
                }
                NavigationLink { PrintCouponWallet(owner: owner) } label: {
                    PersonalSettingsRow(title: "我的优惠券", symbol: "ticket")
                }.accessibilityIdentifier("profile.coupons")
                NavigationLink { InvitationCenterView() } label: {
                    PersonalSettingsRow(title: "邀请有礼", symbol: "gift")
                }
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section("应用设置") {
                NavigationLink { DiaryAIMakingSettingsView() } label: {
                    PersonalSettingsRow(title: "创作偏好", symbol: "slider.horizontal.3")
                }
                NavigationLink { StorageManagementScreen(owner: owner, service: storageService).id(owner) } label: {
                    PersonalSettingsRow(title: "存储空间", symbol: "internaldrive")
                }
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Section("支持") {
                NavigationLink { HelpCenterScreen(owner: owner) } label: {
                    PersonalSettingsRow(title: "帮助与反馈", symbol: "questionmark.bubble",
                                        badge: help.unread > 0 ? "有新回复" : "")
                }
                NavigationLink { PersonalAboutView() } label: {
                    PersonalSettingsRow(title: "关于寻寻仔", symbol: "info.circle")
                }
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            #if DEBUG
            Section("开发版本") {
                NavigationLink { PersonalDeveloperTools(owner: owner) } label: {
                    PersonalSettingsRow(title: "开发工具", symbol: "hammer", detail: "仅开发构建可见")
                }.accessibilityIdentifier("profile.developer-tools")
            }.listRowBackground(DiaryLibraryStyle.surface)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            #endif
        }
        .listStyle(.insetGrouped).listSectionSpacing(20).scrollContentBackground(.hidden)
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent)
        .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
        .task(id: owner) { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("寻寻仔 Pro", systemImage: "book.closed.fill")
                    .font(.headline).foregroundStyle(DiaryLibraryStyle.accent)
                Spacer(minLength: 4)
                if refreshing { ProgressView().controlSize(.small) }
            }
            Text(membershipTitle).font(.title3.weight(.semibold))
            Text(membershipDetail).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }

    private var membershipTitle: String {
        if pending { return "正在确认订阅状态" }
        if let member { return member.title }
        return "把旅途，认真收藏"
    }
    private var membershipDetail: String {
        if pending { return "查看同步进度与会员权益" }
        if let member, member.sync_state == "fresh", member.active {
            if let date = member.subscriptionDate {
                return "\(member.planName) · \(date.label) \(date.date.formatted(date: .abbreviated, time: .omitted))"
            }
            return "查看会员权益与订阅管理"
        }
        // Gift eligibility, price and availability are resolved by the purchase screen.
        return "查看制作权益、精选素材与年费开通礼"
    }
    private var quotaSummary: String {
        guard production.owner == owner else { return "查看剩余额度与恢复时间" }
        if production.error != nil { return "暂时无法更新，点击查看" }
        guard let quota = production.quota, !quota.windows.isEmpty else { return "查看剩余额度与恢复时间" }
        return quota.windows.map {
            "\($0.kind == "short" ? "5 小时" : "7 天")\(DiaryProductionQuotaSection.remainingText($0.remainingRatio))"
        }.joined(separator: " · ")
    }
    private func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-personal-center") { return }
        #endif
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await help.refreshUnread(owner: owner)
        if production.owner == owner { await production.refresh() }
        do {
            try await billing.refreshMembership(owner: owner)
            membershipError = false
        } catch is CancellationError { }
        catch { membershipError = true }
    }
    private var accountTrailingText: String {
        if session.isDeviceAccount { return "登录或注册" }
        let name = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !name.lowercased().hasPrefix("device_") && !name.lowercased().hasPrefix("guest_") { return name }
        return "我的账户"
    }
}

private struct PersonalSettingsRow: View {
    let title: String
    let symbol: String
    var detail = ""
    var badge = ""
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(DiaryLibraryStyle.accent).frame(width: 32, height: 32)
                .background(DiaryLibraryStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !badge.isEmpty {
                Spacer(minLength: 4)
                Text(badge).font(.caption).foregroundStyle(DiaryLibraryStyle.accent)
            }
        }.frame(minHeight: detail.isEmpty ? 36 : 48)
            .padding(.vertical, 2).accessibilityElement(children: .combine)
    }
}

private struct PersonalAboutView: View {
    @State private var legalDocument: IdentifiableURL?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("寻寻仔").font(.title2.bold())
                    Text("把旅途留在手帐里").foregroundStyle(DiaryLibraryStyle.secondary)
                }.padding(.vertical, 12)
                NavigationLink { AppVersionScreen() } label: {
                    LabeledContent("版本信息", value: AppVersionInformation.title)
                }
            }
            Section("条款与隐私") {
                Button("隐私政策") { legalDocument = IdentifiableURL(url: AppEnvironment.current.privacyPolicyURL) }
                Button("用户协议") { legalDocument = IdentifiableURL(url: AppEnvironment.current.termsOfServiceURL) }
            }
        }.navigationTitle("关于寻寻仔").navigationBarTitleDisplayMode(.inline)
            .tint(DiaryLibraryStyle.accent)
            .sheet(item: $legalDocument) { SafariWebViewSheet(url: $0.url) }
    }
}

#if DEBUG
private struct PersonalDeveloperTools: View {
    let owner: String
    @AppStorage("DiaryCanvasAI.backgroundMode") private var mode = "textOnly"
    @State private var purchasePreview = false
    @State private var memberPreview = false
    var body: some View {
        Form {
            Section {
                Text("以下为开发验证功能，正式版本不展示此页面。")
                    .font(.footnote).foregroundStyle(.secondary)
                NavigationLink("钻石钱包测试") { DiamondWalletScreen(owner: owner).id(owner) }
            }
            Section("会员页面预览") {
                Button("订阅购买页") { purchasePreview = true }
                Button("已开通会员页") { memberPreview = true }
            }
            Section("背景生成实验") {
                Picker("生成方式", selection: $mode) {
                    Text("文字提示词 + 空间占位图").tag("guided")
                    Text("纯文本生成").tag("textOnly")
                }
                Text("修改仅对新任务生效。").font(.footnote).foregroundStyle(.secondary)
            }
            DiaryMakingAnimationSettings()
        }.navigationTitle("开发工具").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $purchasePreview) {
                ProSubscriptionPreview().overlay(alignment: .topTrailing) {
                    Button("关闭预览") { purchasePreview = false }.padding()
                }
            }
            .fullScreenCover(isPresented: $memberPreview) {
                ProMembershipPreview().overlay(alignment: .topTrailing) {
                    Button("关闭预览") { memberPreview = false }.padding()
                }
            }
    }
}
#endif

private struct DiaryAIMakingSettingsView: View {
    @AppStorage("DiaryCanvasAI.autoSaveCompletedWork") private var autoSaveCompletedWork = true
    @AppStorage(DiaryAILayoutMode.preferenceKey) private var layoutMode: DiaryAILayoutMode = .native
    @AppStorage("DiaryMaking.animationEnabled") private var animationEnabled = true
    @AppStorage("DiaryMaking.film") private var film = DiaryMakingFilm.factory
    var body: some View {
        Form {
            Section("制作过程") {
                Toggle("显示制作动画", isOn: $animationEnabled)
                Picker("动画风格", selection: $film) {
                    ForEach(DiaryMakingFilm.allCases) { Text($0.title).tag($0) }
                }.disabled(!animationEnabled)
                Text("仅改变制作时的展示，不影响作品内容与制作速度。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("作品保存") {
                Toggle("制作完成后自动保存作品", isOn: $autoSaveCompletedWork)
                    .accessibilityIdentifier("settings.ai.auto-save-completed-work")
                Text("开启后，AI 制作完成会自动保存作品。关闭后保留制作结果，点击“保存作品”后保存；草稿进度仍会保留。此设置不影响背景保存到相册。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("排版方式") {
                ForEach(DiaryAILayoutMode.allCases) { mode in
                    Button {
                        layoutMode = mode
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title).foregroundStyle(.primary)
                                Text(mode.explanation).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if layoutMode == mode { Image(systemName: "checkmark") }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(layoutMode == mode ? .isSelected : [])
                }
                Text("默认设置在下次开始制作时生效。").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("创作偏好").navigationBarTitleDisplayMode(.inline)
            .tint(DiaryLibraryStyle.accent)
    }
}

#if DEBUG
/// Runs the actual personal-center layout without requests or account mutations.
struct PersonalCenterPreview: View {
    @State private var selected = 3
    var body: some View {
        NavigationStack {
            TabView(selection: $selected) {
                Tab("随记", systemImage: "sparkles", value: 0) { Color.clear }
                Tab("手帐", systemImage: "book.pages", value: 1) { Color.clear }
                Tab("素材", systemImage: "books.vertical", value: 2) { PersonalMaterialLibrary(owner: "preview") }
                Tab("我的", systemImage: "person.crop.circle", value: 3) {
                    SettingsView(session: UserSession(accountID: -1, email: "", displayName: "旅行记录者",
                        signedInAt: Date(), signInMethod: .device, isDeviceAccount: true),
                        storageService: StorageService(), onAccountEntryTap: {})
                }
            }.tint(DiaryLibraryStyle.accent)
                .navigationTitle(selected == 3 ? "我的" : "素材").navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
