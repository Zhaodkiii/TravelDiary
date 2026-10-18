import SwiftUI

/// 同意操作与协议链接各自独立；打开协议不改变同意状态。
struct LoginLegalAgreementNote: View {
    @Binding var hasAgreed: Bool
    let showsValidationHighlight: Bool
    let onRequestAgreement: () -> Void
    let onOpenTerms: () -> Void
    let onOpenPrivacy: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                if hasAgreed { hasAgreed = false } else { onRequestAgreement() }
            } label: {
                Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                    .font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel(L10n.text("auth.login.legal.toggle_accessibility"))
                .accessibilityValue(L10n.text(hasAgreed ? "auth.login.agreed" : "auth.login.not_agreed"))
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("auth.login.legal.checkbox_lead")).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { links }
                    VStack(alignment: .leading, spacing: 0) { links }
                }
            }.padding(.top, 10).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain).font(.footnote)
            .padding(8).background(showsValidationHighlight && !hasAgreed ? DiaryLibraryStyle.accent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var links: some View {
        Button(L10n.text("auth.login.legal.terms"), action: onOpenTerms).frame(minHeight: 44)
        Text(L10n.text("auth.login.legal.conjunction")).foregroundStyle(DiaryLibraryStyle.secondary)
        Button(L10n.text("auth.login.legal.privacy"), action: onOpenPrivacy).frame(minHeight: 44)
    }
}
