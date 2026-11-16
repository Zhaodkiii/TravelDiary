import AuthenticationServices
import SwiftUI

/// 由根协调器提供，让已展示的业务 sheet 也能在自身上方打开通用登录页。
struct AccountLoginContext {
    let isDeviceAccount: Bool
    let viewModel: LoginViewModel
}

private struct AccountLoginContextKey: EnvironmentKey {
    static let defaultValue: AccountLoginContext? = nil
}

extension EnvironmentValues {
    var accountLoginContext: AccountLoginContext? {
        get { self[AccountLoginContextKey.self] }
        set { self[AccountLoginContextKey.self] = newValue }
    }
}

struct LoginView: View {
    enum PresentationMode { case primarySignIn, upgradeDeviceAccount }
    @ObservedObject var viewModel: LoginViewModel
    var mode: PresentationMode = .primarySignIn
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @State private var path: [LoginRoute] = []
    @State private var hasAgreed = false
    @State private var showHint = false
    @State private var legalDocument: IdentifiableURL?
    private let consent = LoginConsentStore()

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        Text("寻寻仔").font(.system(.title2, design: .serif, weight: .semibold)).tracking(4).padding(.top, 8)
                        if !typeSize.isAccessibilitySize && geometry.size.height > 600 {
                            LoginTravelArtwork().frame(height: min(230, geometry.size.height * 0.29)).accessibilityHidden(true)
                        }
                        VStack(spacing: 12) {
                            Text(L10n.text(mode == .primarySignIn ? "auth.login.welcome" : "auth.login.upgrade_title"))
                                .font(.system(.title, design: .serif, weight: .semibold)).multilineTextAlignment(.center)
                            Text(L10n.text(mode == .primarySignIn ? "auth.login.subtitle" : "auth.login.upgrade_subtitle"))
                                .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
                        }
                        actions
                        if let error = viewModel.inlineError {
                            Text(error).font(.footnote).foregroundStyle(DiaryLibraryStyle.accent).multilineTextAlignment(.center)
                        }
                        LoginLegalAgreementNote(hasAgreed: $hasAgreed, showsValidationHighlight: showHint,
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
            .sheet(item: $legalDocument) {
                SafariWebViewSheet(url: $0.url)
            }
            .onAppear {
                hasAgreed = consent.isAccepted
            }
            .onChange(of: hasAgreed) { _, value in
                if !value { consent.revoke() }
                else { consent.accept(); showHint = false }
            }
        } destination: { _ in
            PhoneLoginView(viewModel: viewModel).navigationTitle(L10n.text("auth.login.phone_button"))
        }
    }
    private var actions: some View {
        VStack(spacing: 12) {
            ZStack {
                SignInWithAppleButton(.signIn, onRequest: { viewModel.prepareAppleRequest($0) }, onCompletion: { result in
                    Task { await viewModel.signInWithApple(result: result) }
                })
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52).clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(hasAgreed).accessibilityHidden(!hasAgreed)
                if viewModel.isLoading {
                    RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color.white : Color.black)
                    ProgressView(L10n.text("auth.login.processing"))
                        .tint(colorScheme == .dark ? .black : .white)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                }
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
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DiaryLibraryStyle.line))
            }.buttonStyle(.plain).foregroundStyle(DiaryLibraryStyle.ink)
            if mode == .primarySignIn {
                Button {
                    if hasAgreed { Task { await viewModel.signInWithDevice() } } else { requestAgreement() }
                } label: { Text(L10n.text("auth.login.guest_mode")).frame(minHeight: 44) }
                Text(L10n.text("auth.login.guest_note")).font(.footnote)
                    .foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
            }
        }
    }
    private func requestAgreement() { showHint = true }
}

private enum LoginRoute: Hashable { case phone }

/// 本地打包的写实手账素材，无需登录时访问照片库或网络。
struct LoginTravelArtwork: View {
    var body: some View {
        Image("LoginShanghaiJournal")
            .resizable()
            .scaledToFit()
    }
}
