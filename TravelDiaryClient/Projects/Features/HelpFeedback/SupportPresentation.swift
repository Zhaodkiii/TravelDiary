import SwiftUI

struct SupportCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24, content: content)
                .frame(maxWidth: 640).frame(maxWidth: .infinity).padding(20).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink)
        .tint(DiaryLibraryStyle.accent).navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SupportNavigationRow: View {
    let title: String
    let symbol: String
    var detail = ""
    var badge = ""
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .foregroundStyle(DiaryLibraryStyle.accent).frame(width: 40, height: 40)
                .background(DiaryLibraryStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(DiaryLibraryStyle.ink)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
            }
            Spacer(minLength: 6)
            if !badge.isEmpty { Text(badge).font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.accent) }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(16).frame(minHeight: 72).contentShape(Rectangle())
    }
}

struct FeedbackStatusBadge: View {
    let ticket: FeedbackTicket
    var body: some View {
        Label(ticket.statusTitle, systemImage: ticket.statusSymbol)
            .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
            .foregroundStyle(ticket.status == "closed" ? DiaryLibraryStyle.secondary : DiaryLibraryStyle.accent)
            .background((ticket.status == "closed" ? DiaryLibraryStyle.secondary : DiaryLibraryStyle.accent).opacity(0.09), in: Capsule())
    }
}

extension FeedbackTicket {
    var statusSymbol: String {
        ["submitted": "checkmark.circle", "processing": "clock", "waiting_user": "pencil.line", "resolved": "bubble.left", "closed": "checkmark.seal"][status] ?? "info.circle"
    }
    var statusExplanation: String {
        ["submitted": "已收到你的反馈，回复会显示在这里。", "processing": "我们正在跟进这个问题，有进展会在这里回复。", "waiting_user": "需要你补充一些信息，请查看回复后继续说明。", "resolved": "已有处理答复。仍有问题可以继续补充，也可以确认解决。", "closed": "这条反馈已结束，问题和回复会保留在这里。" ][status] ?? "下拉刷新可查看最新进展。"
    }
}

struct FeedbackTicketCard: View {
    let ticket: FeedbackTicket
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(ticket.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                FeedbackStatusBadge(ticket: ticket)
            }
            Text(ticket.statusExplanation).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).lineLimit(2)
            HStack {
                Text(supportDate(ticket.last_public_activity_at)).font(.caption)
                Spacer()
                if ticket.unread { Label("有新回复", systemImage: "circle.fill").font(.caption.weight(.semibold)).foregroundStyle(DiaryLibraryStyle.accent) }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
            }.foregroundStyle(DiaryLibraryStyle.secondary)
        }.padding(18).feedbackPaperCard().contentShape(Rectangle())
    }
}

struct SupportEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(DiaryLibraryStyle.accent)
                .frame(width: 68, height: 68).background(DiaryLibraryStyle.accent.opacity(0.07), in: Circle())
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 32).feedbackPaperCard()
    }
}
