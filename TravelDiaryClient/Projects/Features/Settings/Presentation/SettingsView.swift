import SwiftUI

struct SettingsView: View {
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let session: UserSession
    let storageService: StorageService
    let onAccountEntryTap: () -> Void

    @ObservedObject private var help = HelpFeedbackService.shared
    @State private var legalDocument: IdentifiableURL?

    var body: some View {
        SupportCanvas {
            Button(action: onAccountEntryTap) {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle").font(.system(size: 38, weight: .light))
                        .foregroundStyle(DiaryLibraryStyle.accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(accountTrailingText).font(.headline).foregroundStyle(DiaryLibraryStyle.ink)
                        Text(session.isDeviceAccount ? "登录账户，让旅途记录有所归属" : "账户管理与安全设置")
                            .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.secondary)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).feedbackPaperCard()
            }.buttonStyle(.plain).accessibilityHint("打开账户管理")
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("我的资源")
                NavigationLink { FontGalleryScreen(mine: true) } label: { SupportNavigationRow(title: "我的字体", symbol: "textformat", detail: "已获取、收藏与最近使用") }.buttonStyle(.plain).feedbackPaperCard()
                NavigationLink { StickerGalleryScreen(mine: true) } label: { SupportNavigationRow(title: "我的贴纸", symbol: "heart", detail: "贴纸包与收藏") }.buttonStyle(.plain).feedbackPaperCard()
                NavigationLink { FontGalleryScreen() } label: { SupportNavigationRow(title: "字体集市", symbol: "textformat.abc", detail: "发现适合旅途记录的字体") }.buttonStyle(.plain).feedbackPaperCard()
                NavigationLink { FontStorageScreen() } label: { SupportNavigationRow(title: "字体存储", symbol: "internaldrive", detail: "查看字体下载与占用空间") }.buttonStyle(.plain).feedbackPaperCard()
                sectionTitle("通用")
                NavigationLink {
                    StorageManagementScreen(owner: String(session.accountID), service: storageService).id(session.accountID)
                } label: { SupportNavigationRow(title: "存储空间", symbol: "internaldrive", detail: "管理本机文件与缓存") }.buttonStyle(.plain).feedbackPaperCard()
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("服务")
                #if DEBUG
                NavigationLink { MembershipPurchaseScreen(owner: String(session.accountID)).id(session.accountID) } label: { SupportNavigationRow(title: "寻寻仔会员", symbol: "crown", detail: "会员状态、订阅与恢复购买") }.buttonStyle(.plain).feedbackPaperCard()
                NavigationLink { DiamondWalletScreen(owner: String(session.accountID)).id(session.accountID) } label: { SupportNavigationRow(title: "我的钻石", symbol: "diamond", detail: "充值、明细与已解锁内容") }.buttonStyle(.plain).feedbackPaperCard()
                #endif
                VStack(spacing: 0) {
                    #if DEBUG
                    NavigationLink { PrintOrdersScreen(owner: String(session.accountID)) } label: {
                        SupportNavigationRow(title: "我的印制订单", symbol: "shippingbox", detail: "查看印制与配送进度")
                    }
                    cardDivider
                    #endif
                    NavigationLink { HelpCenterScreen(owner: String(session.accountID)) } label: {
                        SupportNavigationRow(title: "帮助与反馈", symbol: "questionmark.bubble", detail: "使用帮助、建议与问题反馈", badge: help.unread > 0 ? "有新回复" : "")
                    }
                }.buttonStyle(.plain).feedbackPaperCard()
            }
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("关于")
                VStack(spacing: 0) {
                    Button { legalDocument = IdentifiableURL(url: AppEnvironment.current.privacyPolicyURL) } label: { SupportNavigationRow(title: "隐私政策", symbol: "hand.raised") }
                    cardDivider
                    Button { legalDocument = IdentifiableURL(url: AppEnvironment.current.termsOfServiceURL) } label: { SupportNavigationRow(title: "用户协议", symbol: "doc.text") }
                    cardDivider
                    NavigationLink { AppVersionScreen() } label: { SupportNavigationRow(title: "版本信息", symbol: "info.circle", badge: AppVersionInformation.title) }
                }.buttonStyle(.plain).feedbackPaperCard()
            }
            Text("TravelDiary · 把旅途留在手帐里").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary).frame(maxWidth: .infinity).padding(.top, 4)
        }
        .navigationTitle(L10n.text("settings.title", fallback: "设置"))
        .sheet(item: $legalDocument) { SafariWebViewSheet(url: $0.url) }
        .task(id: session.accountID) { await help.refreshUnread(owner: String(session.accountID)) }
    }

    private var cardDivider: some View { Divider().overlay(DiaryLibraryStyle.line).padding(.leading, 69) }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.secondary).padding(.leading, 4)
    }
    private var accountTrailingText: String {
        if session.isDeviceAccount { return "登录或注册" }
        let name = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty && !name.lowercased().hasPrefix("device_") && !name.lowercased().hasPrefix("guest_") { return name }
        return "我的账户"
    }
}
