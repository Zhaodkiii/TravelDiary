import SwiftUI
import UIKit
import Photos
import CoreImage.CIFilterBuiltins

private struct InvitationSummary: Decodable {
    struct Campaign: Decodable { let id: Int; let title: String; let rules: String; let cardsPerInvite: Int; let cardDays: Int; let endsAt: Date?; let available: Bool?; let remainingSlots: Int?; let joined: Bool?; let automatic: Bool? }
    struct Record: Decodable, Identifiable { let id: String; let createdAt: Date; let status: String; let expiresAt: Date? }
    let campaign: Campaign?
    let link: String?
    let inviteToken: String?
    let count: Int
    let records: [Record]
}
private struct InvitationRewards: Decodable {
    struct Card: Decodable, Identifiable { let id: String; let expiresAt: Date; let status: String }
    struct Coupon: Decodable, Identifiable { let id: String; let name: String; let expiresAt: Date; let status: String }
    struct Grant: Decodable, Identifiable { let id: Int; let kind: String; let threshold: Int; let quantity: Int; let issuedAt: Date? }
    let cards: [Card]; let coupons: [Coupon]; let grants: [Grant]
}
private struct ResetPreview: Decodable { let card: InvitationRewards.Card; let quota: DiaryProductionQuota; let plan: String? }
private struct ResetResult: Decodable { let card: InvitationRewards.Card; let quota: DiaryProductionQuota }

struct InvitationCenterView: View {
    @ObservedObject private var service = DiaryProductionService.shared
    @State private var summary: InvitationSummary?
    @State private var sharingURL: URL?
    @State private var rewards: InvitationRewards?
    @State private var error: String?
    @State private var busy = false
    @State private var poster: UIImage?
    @State private var shareOpen = false
    @State private var preview: ResetPreview?
    @State private var selectedCard: String?
    @State private var confirm = false
    @State private var useKeys: [String: UUID] = [:]

    @State private var sharePreviewOpen = false
    @State private var notice: String?
    @Environment(\.scenePhase) private var scenePhase

    private var count: Int { max(0, summary?.count ?? 0) }
    private var accent: Color { Color(red: 0.22, green: 0.43, blue: 0.39) }

    var body: some View {
        List {
            if service.owner == nil {
                Section { Label("登录后即可邀请好友和查看奖励", systemImage: "person.crop.circle") }
            } else if summary == nil && busy {
                Section { ProgressView("正在加载活动与奖励…") }
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    Button("重新加载") { Task { await load() } }.disabled(busy)
                }
            }
            if let campaign = summary?.campaign {
                Section {
                    Image("InvitationRealJournalHero").resizable().scaledToFit()
                        .accessibilityLabel("实拍手帐素材衍生展示")
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("实拍素材衍生展示").font(.caption).foregroundStyle(.secondary)
                    Text("把旅途，认真收藏").font(.title2.bold())
                    Text(campaign.title).foregroundStyle(.secondary)
                    Label("每成功邀请1位好友，获得\(campaign.cardsPerInvite)张制作额度重置卡", systemImage: "gift")
                        .font(.headline)
                    Text("恢复制作额度，按使用时的会员等级生效；不是增加会员时长。奖励期限与上限以本期规则为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let end = campaign.endsAt {
                        Text("活动截至 \(end.formatted(date: .abbreviated, time: .shortened))").font(.footnote)
                    }
                    if campaign.joined == true { Text("已获得本期邀请资格").font(.footnote).foregroundStyle(accent) }
                    else if let slots = campaign.remainingSlots { Text(slots > 0 ? "本期剩余\(slots)个邀请人名额，首次创建邀请时锁定" : "本期邀请人名额已满").font(.footnote) }
                    Text(campaign.automatic == true ? "达标后自动发放，可在下方查看到账记录。" : "达标后的奖励发放状态可在下方查看。").font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("本期活动规则与参与条件") {
                        Text(campaign.rules).font(.subheadline).textSelection(.enabled)
                    }
                }
                Section("我的邀请") {
                    Text("已成功邀请 \(count) 位").font(.title2.bold())
                    Text(count < 5 ? "再邀请\(5-count)位，达到半价装订券门槛" : count < 10 ? "再邀请\(10-count)位，达到标准装订免费券门槛" : "已达到两档装订奖励门槛，请查看到账记录")
                    ProgressView(value: Double(min(count, 10)), total: 10).tint(accent)
                        .accessibilityLabel("装订奖励进度").accessibilityValue("已邀请\(count)人，最高门槛10人")
                    HStack {
                        Text("0位")
                        Spacer()
                        Text("5位 · 半价券")
                        Spacer()
                        Text("10位 · 免费券")
                    }.font(.caption).foregroundStyle(.secondary)
                    Text("装订券限标准规格，运费、超页及升级费用另付；具体范围与抵扣上限见活动规则。")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("邀请记录（\(summary?.records.count ?? 0)）") {
                        List {
                            if summary?.records.isEmpty != false {
                                Text("还没有邀请记录，分享给第一位好友吧。")
                            }
                            ForEach(summary?.records ?? []) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(statusLabel(record.status)).font(.headline)
                                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                    if record.status == "awaiting_app" {
                                        if let expiry = record.expiresAt { Text("请在\(expiry.formatted(date: .abbreviated, time: .shortened))前完成").font(.caption) }
                                        Text("好友需要使用登记时的手机号或邮箱，在 App 完成验证。有效期限见活动规则。")
                                            .font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }.navigationTitle("邀请记录")
                    }
                }
            } else if !busy && error == nil && service.owner != nil {
                Section { Text("当前暂无开放的邀请活动"); Text("已有奖励仍可在下方查看和使用。").font(.footnote) }
            }
            Section("我的奖励 · 制作额度重置卡") {
                ForEach(rewards?.cards ?? []) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("制作额度重置卡").font(.headline)
                        Text("免费账号恢复7天额度；Pro恢复7天和5小时额度。使用前会核验当前等级。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("到期：\(card.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        if card.status == "available" && card.expiresAt > Date() {
                            Button("查看并使用") { Task { await inspect(card.id) } }.disabled(busy)
                        } else { Text(card.expiresAt <= Date() && card.status == "available" ? "已到期" : statusLabel(card.status)).foregroundStyle(.secondary) }
                    }
                }
                if rewards != nil && rewards?.cards.isEmpty != false {
                    Label("暂无重置卡", systemImage: "gift")
                    Text("活动期间完成有效邀请后，可在这里查看到账奖励。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("我的奖励 · 印制优惠券") {
                ForEach(rewards?.coupons ?? []) { coupon in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(coupon.name).font(.headline)
                        Text("\(statusLabel(coupon.status)) · \(coupon.expiresAt.formatted(date: .abbreviated, time: .omitted)) 到期").font(.caption)
                    }
                }
                if rewards != nil && rewards?.coupons.isEmpty != false { Text("暂无印制优惠券").foregroundStyle(.secondary) }
                if let owner = service.owner {
                    NavigationLink("查看印制订单与用券") { PrintOrdersScreen(owner: owner) }
                    Text("下单时选择可用优惠券，实际优惠以订单报价为准。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let rewards, !rewards.grants.isEmpty {
                Section("奖励到账记录") {
                    ForEach(rewards.grants) { grant in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("邀请 \(grant.threshold) 人 · \(grant.kind == "reset_card" ? "重置卡 × \(grant.quantity)" : grant.kind == "half_print" ? "半价装订券" : grant.kind == "free_print" ? "免费装订券" : "活动奖励")")
                            Text(grant.issuedAt.map { "已到账 · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "已达标，等待发放")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .tint(accent)
        .navigationTitle("邀请有礼")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            if let campaign = summary?.campaign, campaign.available != false, campaign.joined == true || campaign.remainingSlots != 0 {
                Button { Task { await createPoster(); if poster != nil { sharePreviewOpen = true } } } label: {
                    HStack { if busy { ProgressView().tint(.white) }; Label(busy ? "正在准备…" : "邀请好友", systemImage: "square.and.arrow.up") }
                        .font(.headline).frame(maxWidth: .infinity).padding(16)
                }.buttonStyle(.plain).foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 16))
                    .disabled(busy).padding(.horizontal).padding(.vertical, 10).background(.regularMaterial)
            }
        }
        .task(id: service.owner) { summary=nil; sharingURL=nil; rewards=nil; poster=nil; preview=nil; selectedCard=nil; useKeys=[:]; await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await load() } } }
        .sheet(isPresented: $sharePreviewOpen) { sharePreview }
        .alert("确认使用重置卡？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button("消耗一张并重置") { Task { await useCard() } }
        } message: {
            Text("\(preview?.plan == "pro" ? "7天和5小时额度" : "7天额度")将恢复至100%，不会与剩余额度叠加。下次 AI 调用开始新周期。此操作立即消耗一张卡。")
        }
    }

    private var sharePreview: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let poster { Image(uiImage: poster).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("邀请海报，包含品牌封面与专属邀请二维码") }
                    Text("好友扫码登记后，使用同一手机号或邮箱在 App 验证，才会计为有效邀请。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let link = sharingURL {
                        ShareLink(item: link, preview: SharePreview("一起收藏旅途 · 寻寻仔", image: Image("InvitationRealJournalHero"))) {
                            Label("分享邀请链接", systemImage: "link").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button("复制邀请链接") { UIPasteboard.general.url = link; notice = "邀请链接已复制" }
                    }
                    HStack {
                        Button { shareOpen = true } label: { Label("分享海报", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Button { Task { await savePoster() } } label: { Label("保存图片", systemImage: "square.and.arrow.down") }.disabled(busy)
                    }.buttonStyle(.bordered)
                    if let notice { Text(notice).font(.footnote).accessibilityAddTraits(.updatesFrequently) }
                }.padding()
            }
            .navigationTitle("邀请预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { sharePreviewOpen = false } } }
            .sheet(isPresented: $shareOpen) { if let poster { InvitationActivitySheet(image: poster) } }
        }.tint(accent)
    }

    @MainActor private func savePoster() async {
        guard let poster, !busy else { return }
        busy = true; defer { busy = false }
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            notice = "无法写入相册。可使用“分享海报”保存到文件，或在系统设置中允许添加照片。"; return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: poster) }
            notice = "海报已保存到相册"
        } catch { notice = "保存失败，请重试或使用分享海报。" }
    }
    private func load() async {
        guard !busy, service.owner != nil else { return }; busy=true; defer { busy=false }; error=nil
        do {
            summary = try await service.invitationRequest("/api/v1/experience/invitations/me/")
            sharingURL = try service.invitationShareURL(token: summary?.inviteToken, legacyLink: summary?.link)
            rewards = try await service.invitationRequest("/api/v1/experience/rewards/")
            await service.refreshQuota()
        } catch { self.error=error.localizedDescription }
    }
    private func createPoster() async {
        guard let c=summary?.campaign, !busy else { return };busy=true;defer{busy=false}
        do {
            if summary?.inviteToken == nil && summary?.link == nil { summary = try await service.invitationRequest("/api/v1/experience/invitations/me/",body:["campaign_id":c.id]) }
            sharingURL = try service.invitationShareURL(token: summary?.inviteToken, legacyLink: summary?.link)
            guard let link=sharingURL?.absoluteString else { error="邀请链接暂不可用，请重试"; return }
            notice = nil
            poster=InvitationPoster.render(title:c.title,rules:c.rules,link:link)
            if poster == nil { error="海报生成失败，请重试" }
        } catch { self.error=error.localizedDescription }
    }
    private func inspect(_ id:String) async {
        guard !busy else{return};busy=true;defer{busy=false};error=nil
        do {
            preview=try await service.invitationRequest("/api/v1/ai-production/reset-cards/\(id)/preview/",body:[:])
            guard let p=preview, p.card.status == "available", p.plan != nil else { error="卡片已失效或会员状态待确认";return }
            guard !p.quota.pendingUsage else {error="调用正在记账，请稍后重试";return}
            guard p.quota.windows.contains(where:{$0.remainingRatio < 1}) else {error="额度已满，无需消耗卡片";return}
            selectedCard=id;confirm=true
        }catch{self.error=error.localizedDescription}
    }
    private func useCard() async {
        guard let id=selectedCard,let plan=preview?.plan,!busy else{return};busy=true
        let storageKey="invitation.reset.\(service.owner ?? "").\(id)"
        let key=UserDefaults.standard.string(forKey:storageKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(key.uuidString,forKey:storageKey)
        useKeys[id]=key
        do {let _:ResetResult=try await service.invitationRequest("/api/v1/ai-production/reset-cards/\(id)/use/",body:["expected_plan":plan],key:key);error=nil}
        catch{self.error=error.localizedDescription;busy=false;return}
        busy=false;await load()
    }
    private func statusLabel(_ state:String)->String {
        switch state {case "confirmed":return "邀请成功";case "awaiting_app":return "待 App 登录／绑定";case "available":return "可用";case "used":return "已使用／订单占用";case "expired":return "已到期";case "revoked":return "已撤销";case "duplicate":return "重复账号，不计入邀请";case "ineligible":return "不符合活动条件";case "pending":return "正在核验";default:return "状态待确认，请刷新"}
    }
}

private enum InvitationPoster {
    @MainActor static func render(title:String,rules:String,link:String)->UIImage? {
        let filter=CIFilter.qrCodeGenerator();filter.message=Data(link.utf8);filter.correctionLevel="M"
        guard let output=filter.outputImage, let cg=CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:12,y:12)),from:output.extent.applying(CGAffineTransform(scaleX:12,y:12))) else{return nil}
        let format=UIGraphicsImageRendererFormat();format.scale=1
        return UIGraphicsImageRenderer(size:CGSize(width:1080,height:1600),format:format).image { ctx in
            UIColor(red:1,green:0.97,blue:0.92,alpha:1).setFill();ctx.fill(CGRect(x:0,y:0,width:1080,height:1600))
            func text(_ value:String,_ y:CGFloat,_ size:CGFloat,_ height:CGFloat) { (value as NSString).draw(in:CGRect(x:80,y:y,width:920,height:height),withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:UIColor.darkGray]) }
            text("寻寻仔 · 旅行手帐",60,30,50)
            text("把旅途，认真收藏",140,64,100)
            text("朋友邀请你，一起记录旅行中的美好",250,30,60)
            if let cover = UIImage(named: "InvitationRealJournalHero") {
                let box = CGRect(x:80,y:340,width:920,height:560)
                let ratio = max(box.width / cover.size.width, box.height / cover.size.height)
                let size = CGSize(width:cover.size.width * ratio,height:cover.size.height * ratio)
                ctx.cgContext.saveGState()
                UIBezierPath(roundedRect:box,cornerRadius:24).addClip()
                cover.draw(in:CGRect(x:box.midX-size.width/2,y:box.midY-size.height/2,width:size.width,height:size.height))
                ctx.cgContext.restoreGState()
            }
            UIColor.white.setFill();ctx.fill(CGRect(x:80,y:980,width:360,height:360));ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage:cg).draw(in:CGRect(x:110,y:1010,width:300,height:300))
            func detail(_ value:String,_ y:CGFloat,_ size:CGFloat) {
                (value as NSString).draw(in:CGRect(x:480,y:y,width:500,height:160),withAttributes:[.font:UIFont.systemFont(ofSize:size,weight:.medium),.foregroundColor:UIColor.darkGray])
            }
            detail("扫码接受好友邀请",1010,38)
            detail("登记手机号或邮箱\n下载 App 后用同一账号验证",1110,28)
            text("实拍素材衍生展示 · 活动资格、期限与奖励条件请扫码查看。",1430,25,90)

        }
    }
}
private struct InvitationActivitySheet:UIViewControllerRepresentable {
    let image:UIImage
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[image],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
