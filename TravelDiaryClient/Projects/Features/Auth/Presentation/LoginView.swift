import AuthenticationServices
import SwiftUI

struct LoginView: View {
    enum PresentationMode { case primarySignIn, upgradeDeviceAccount }
    @ObservedObject var viewModel: LoginViewModel
    var mode: PresentationMode = .primarySignIn
    var presentsInitialLegalPromptOnAppear = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @State private var path: [LoginRoute] = []
    @State private var hasAgreed = false
    @State private var showAgreement = false
    @State private var showHint = false
    @State private var legalDocument: IdentifiableURL?
    private let consent = LoginConsentStore()

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 28) {
                        Text("TravelDiary").font(.headline).tracking(2).padding(.top, 12)
                        if !typeSize.isAccessibilitySize && geometry.size.height > 600 {
                            LoginTravelArtwork().frame(height: min(220, geometry.size.height * 0.28)).accessibilityHidden(true)
                        }
                        VStack(spacing: 12) {
                            Text(L10n.text(mode == .primarySignIn ? "auth.login.welcome" : "auth.login.upgrade_title"))
                                .font(.largeTitle.weight(.semibold)).multilineTextAlignment(.center)
                            Text(L10n.text(mode == .primarySignIn ? "auth.login.subtitle" : "auth.login.upgrade_subtitle"))
                                .font(.body).foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
                        }
                        actions
                        if let error = viewModel.inlineError {
                            Text(error).font(.footnote).foregroundStyle(DiaryLibraryStyle.accent).multilineTextAlignment(.center)
                        }
                        LoginLegalAgreementNote(hasAgreed: $hasAgreed, showsValidationHighlight: showHint,
                            onRequestAgreement: { showAgreement = true },
                            onOpenTerms: { legalDocument = IdentifiableURL(url: AppEnvironment.current.termsOfServiceURL) },
                            onOpenPrivacy: { legalDocument = IdentifiableURL(url: AppEnvironment.current.privacyPolicyURL) })
                        if showHint && !hasAgreed {
                            Text(L10n.text("auth.login.legal.must_agree_hint")).font(.footnote).foregroundStyle(DiaryLibraryStyle.accent)
                        }
                    }.frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity)
                }
            }
            .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .upgradeDeviceAccount {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.text("auth.login.return")) { dismiss() }.disabled(viewModel.isLoading)
                    }
                }
            }
            .disabled(viewModel.isLoading)
            .interactiveDismissDisabled(viewModel.isLoading)
            .sheet(isPresented: $showAgreement) {
                LoginAgreementSheet(onDecline: { hasAgreed = false; showAgreement = false }, onAgree: {
                    consent.accept()
                    hasAgreed = true; showHint = false; showAgreement = false
                })
            }
            .sheet(item: $legalDocument) {
                SafariWebViewSheet(url: $0.url)
            }
            .onAppear {
                hasAgreed = consent.isAccepted
                if !hasAgreed && presentsInitialLegalPromptOnAppear { showAgreement = true }
            }
            .onChange(of: hasAgreed) { _, value in
                if !value { consent.revoke() }
                else { showHint = false }
            }
        } destination: { _ in
            PhoneLoginView(viewModel: viewModel).navigationTitle(L10n.text("auth.login.phone_button"))
        }
    }
    private var actions: some View {
        VStack(spacing: 12) {
            if viewModel.isLoading {
                ProgressView(L10n.text("auth.login.processing"))
                    .font(.subheadline).tint(DiaryLibraryStyle.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ZStack {
                SignInWithAppleButton(.signIn, onRequest: { viewModel.prepareAppleRequest($0) }, onCompletion: { result in
                    Task { await viewModel.signInWithApple(result: result) }
                })
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(hasAgreed).accessibilityHidden(!hasAgreed)
                if !hasAgreed {
                    Button { requestAgreement() } label: {
                        Color.clear.frame(height: 52).contentShape(Rectangle())
                    }.accessibilityLabel(L10n.text("auth.login.apple_button"))
                }
            }
            Button {
                if hasAgreed { path.append(.phone) } else { requestAgreement() }
            } label: {
                Label(L10n.text("auth.login.phone_button"), systemImage: "phone")
                    .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DiaryLibraryStyle.accent.opacity(0.5)))
            }.buttonStyle(.plain).foregroundStyle(DiaryLibraryStyle.accent)
            if mode == .primarySignIn {
                Button {
                    if hasAgreed { Task { await viewModel.signInWithDevice() } } else { requestAgreement() }
                } label: { Text(L10n.text("auth.login.guest_mode")).frame(minHeight: 44) }
                Text(L10n.text("auth.login.guest_note")).font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
            }
        }
    }
    private func requestAgreement() { showHint = true; showAgreement = true }
}

private enum LoginRoute: Hashable { case phone }

/// 纯本地矢量拼贴，不加载用户照片或在登录时请求照片权限。
struct LoginTravelArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(DiaryLibraryStyle.surface)
                .frame(width: 155, height: 180).rotationEffect(.degrees(9)).offset(x: 48, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.68, green: 0.78, blue: 0.72), Color(red: 0.87, green: 0.86, blue: 0.71)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "mountain.2.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.85))
                }.frame(width: 148, height: 116).clipped()
                Text("A little journey").font(.system(.caption, design: .serif)).foregroundStyle(Color(red: 0.3, green: 0.32, blue: 0.28))
            }.padding(10).background(Color(red: 0.99, green: 0.98, blue: 0.94))
                .rotationEffect(.degrees(-8)).offset(x: -28)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
            Image(systemName: "airplane.circle").font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(DiaryLibraryStyle.accent).rotationEffect(.degrees(-20)).offset(x: 90, y: 60)
        }
    }
}

struct LoginAgreementSheet: View {
    let onDecline: () -> Void
    let onAgree: () -> Void
    @State private var legalDocument: IdentifiableURL?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(DiaryLibraryStyle.accent).accessibilityHidden(true)
                Text(L10n.text("auth.login.initial_prompt.title")).font(.title2.weight(.semibold))
                Text(L10n.text("auth.login.initial_prompt.intro")).lineSpacing(5)
                VStack(alignment: .leading, spacing: 6) {
                    Button(L10n.text("auth.login.legal.terms")) { legalDocument = IdentifiableURL(url: AppEnvironment.current.termsOfServiceURL) }.frame(minHeight: 44)
                    Button(L10n.text("auth.login.legal.privacy")) { legalDocument = IdentifiableURL(url: AppEnvironment.current.privacyPolicyURL) }.frame(minHeight: 44)
                }
                Text(L10n.text("auth.login.initial_prompt.permissions")).lineSpacing(5)
                Text(L10n.text("auth.login.initial_prompt.permission_note")).font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            }.padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(L10n.text("auth.login.initial_prompt.agree"), action: onAgree)
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
                Button(L10n.text("auth.login.initial_prompt.decline"), action: onDecline).frame(minHeight: 44)
            }.padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink).tint(DiaryLibraryStyle.accent)
        .presentationDetents([.fraction(0.5)])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
        .sheet(item: $legalDocument) { SafariWebViewSheet(url: $0.url) }
    }
}
