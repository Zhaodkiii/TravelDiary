import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

private struct InvitationSummary: Decodable {
    struct Campaign: Decodable { let id: Int; let title: String; let rules: String; let cardsPerInvite: Int; let cardDays: Int }
    struct Record: Decodable, Identifiable { let id: String; let createdAt: Date; let status: String }
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

    var body: some View {
        List {
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if let campaign = summary?.campaign {
                Section(campaign.title) {
                    Text("成功邀请 \(summary?.count ?? 0) 人").font(.title2.bold())
                    ProgressView("5 人：标准装订半价券", value: Double(min(summary?.count ?? 0, 5)), total: 5)
                    ProgressView("10 人：标准装订免费券", value: Double(min(summary?.count ?? 0, 10)), total: 10)
                    Text(campaign.rules).font(.footnote)
                    Button("生成二维码邀请海报") { Task { await createPoster() } }.disabled(busy)
                    if let link = sharingURL {
                        ShareLink(item: link,
                                  preview: SharePreview("一起收藏旅途 · 寻寻仔", image: Image("InvitationShareCover"))) {
                            Label("分享邀请链接", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let poster { Image(uiImage: poster).resizable().scaledToFit(); Button("分享或保存海报") { shareOpen = true } }
                }
            } else { Section { Text("当前暂无开放的邀请活动"); Text("已有奖励仍可在下方查看和使用。").font(.footnote) } }
            Section("制作额度重置卡") {
                ForEach(rewards?.cards ?? []) { card in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(service.quota?.plan == "pro" ? "完全重置（7 天 + 5 小时）" : "重置 7 天制作额度").font(.headline)
                        Text("到期：\(card.expiresAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        if card.status == "available" {
                            Button("使用重置卡") { Task { await inspect(card.id) } }.disabled(busy)
                        } else { Text(statusLabel(card.status)).foregroundStyle(.secondary) }
                    }
                }
                if rewards?.cards.isEmpty != false { Text("暂无重置卡").foregroundStyle(.secondary) }
            }
            Section("印制优惠券") {
                ForEach(rewards?.coupons ?? []) { coupon in
                    VStack(alignment: .leading) { Text(coupon.name); Text("\(statusLabel(coupon.status)) · \(coupon.expiresAt.formatted(date: .abbreviated, time: .omitted)) 到期").font(.caption) }
                }
                if let owner = service.owner { NavigationLink("前往印制订单，选择作品下单用券") { PrintOrdersScreen(owner: owner) } }
            }
            Section("奖励到账记录") {
                ForEach(rewards?.grants ?? []) { grant in
                    Text("邀请 \(grant.threshold) 人 · \(grant.kind == "reset_card" ? "重置卡 × \(grant.quantity)" : grant.kind == "half_print" ? "半价装订券" : "免费装订券") · \(grant.issuedAt == nil ? "待发放" : "已到账")")
                }
            }
            Section("邀请记录") {
                ForEach(summary?.records ?? []) { record in
                    HStack { Text(record.createdAt.formatted(date: .abbreviated, time: .shortened)); Spacer(); Text(statusLabel(record.status)) }
                }
            }
            Button("刷新进度与奖励") { Task { await load() } }.disabled(busy)
        }
        .navigationTitle("邀请有礼")
        .task(id: service.owner) { summary=nil; sharingURL=nil; rewards=nil; poster=nil; preview=nil; selectedCard=nil; useKeys=[:]; await load() }
        .sheet(isPresented: $shareOpen) { if let poster { InvitationActivitySheet(image: poster) } }
        .alert("确认使用重置卡？", isPresented: $confirm) {
            Button("取消", role: .cancel) {}
            Button("消耗一张并重置") { Task { await useCard() } }
        } message: {
            Text("\(preview?.plan == "pro" ? "7 天和 5 小时额度" : "7 天额度")将恢复至 100%。下次 AI 调用开始新周期。此操作立即消耗一张卡。")
        }
    }
    private func load() async {
        guard !busy, service.owner != nil else { return }; busy=true; defer { busy=false }; error=nil
        do {
            summary = try await service.invitationRequest("/api/v1/experience/invitations/me/")
            sharingURL = try service.invitationShareURL(token: summary?.inviteToken, legacyLink: summary?.link)
            poster = nil
            rewards = try await service.invitationRequest("/api/v1/experience/rewards/")
            await service.refreshQuota()
        } catch { self.error=error.localizedDescription }
    }
    private func createPoster() async {
        guard let c=summary?.campaign, !busy else { return };busy=true;defer{busy=false}
        do {
            if summary?.inviteToken == nil && summary?.link == nil { summary = try await service.invitationRequest("/api/v1/experience/invitations/me/",body:["campaign_id":c.id]) }
            sharingURL = try service.invitationShareURL(token: summary?.inviteToken, legacyLink: summary?.link)
            guard let link=sharingURL?.absoluteString else { return }
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
        switch state {case "confirmed":return "邀请成功";case "awaiting_app":return "待 App 登录／绑定";case "available":return "可用";case "used":return "已使用／订单占用";case "expired":return "已到期";case "revoked":return "已撤销";default:return state}
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
            text("寻寻仔 · 旅行手帐",80,32,60);text(title,190,64,180)
            text("把旅途，认真收藏",390,46,80)
            UIColor.white.setFill();ctx.fill(CGRect(x:280,y:530,width:520,height:520));ctx.cgContext.interpolationQuality = .none
            UIImage(cgImage:cg).draw(in:CGRect(x:320,y:570,width:440,height:440))
            text("扫码登记 → 下载 App → 登录或绑定",1120,36,100)
            text("使用同一手机号或邮箱完成验证，确认好友邀请。",1240,29,110)
            text("活动期限、奖励规格与领取条件请扫码查看。",1410,25,100)
        }
    }
}
private struct InvitationActivitySheet:UIViewControllerRepresentable {
    let image:UIImage
    func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[image],applicationActivities:nil)}
    func updateUIViewController(_ controller:UIActivityViewController,context:Context){}
}
