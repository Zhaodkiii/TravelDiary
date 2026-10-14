import AuthenticationServices
import SwiftUI
import UIKit

struct LoginView: View {
    enum PresentationMode {
        case primarySignIn
        case upgradeDeviceAccount
    }

    @ObservedObject var viewModel: LoginViewModel
    var mode: PresentationMode = .primarySignIn
    var presentsInitialLegalPromptOnAppear = true

    @State private var path: [LoginRoute] = []
    @State private var showPhoneLogin = true
    @State private var tapCount = 0
    @State private var lastTapTime: Date?
    @State private var hasAgreedToLegal = false
    @State private var legalAgreementShakeTrigger = 0
    @State private var showsLegalValidationHighlight = false
    @State private var showsInitialLegalPrompt = false
    @AppStorage("auth.login.initial_legal_prompt_accepted") private var hasAcceptedInitialLegalPrompt = false

    var body: some View {
        CompatibleRouteNavigationContainer(path: $path, legacyStackStyle: true) {
            ScrollView {
                VStack(spacing: 24) {
                    headerCluster
                    actionButtons
                    LoginLegalAgreementNote(
                        hasAgreed: hasAgreedToLegal,
                        shakeTrigger: legalAgreementShakeTrigger,
                        showsValidationHighlight: showsLegalValidationHighlight,
                        onOpenAgreementPrompt: {
                            presentInitialLegalPrompt()
                        }
                    )
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(L10n.text("auth.login.title"))
                        .font(.headline)
                        .fontWeight(.semibold)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isLoading)
            .interactiveDismissDisabled(viewModel.isLoading)
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .sheet(isPresented: $showsInitialLegalPrompt) {
                initialLegalPromptSheet
            }
            .onChange(of: hasAgreedToLegal) { agreed in
                if agreed {
                    showsLegalValidationHighlight = false
                }
            }
            .onAppear {
                if hasAcceptedInitialLegalPrompt {
                    hasAgreedToLegal = true
                } else if presentsInitialLegalPromptOnAppear {
                    presentInitialLegalPrompt(showsWarning: false)
                }
            }
        } destination: { route in
            switch route {
            case .phone:
                PhoneLoginView(viewModel: viewModel)
                    .navigationTitle("手机号登录")
            }
        }
    }

    private func requireLegalAgreementBeforeLogin() {
        presentInitialLegalPrompt()
    }

    private func presentInitialLegalPrompt(showsWarning: Bool = true) {
        if showsWarning {
            showsLegalValidationHighlight = true
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            legalAgreementShakeTrigger += 1
        }

        showsInitialLegalPrompt = true
    }

    @ViewBuilder
    private var initialLegalPromptSheet: some View {
        LoginInitialLegalPromptSheet(
            fixedHeight: UIScreen.main.bounds.height * 0.5,
            onDecline: {
                hasAcceptedInitialLegalPrompt = false
                hasAgreedToLegal = false
                showsInitialLegalPrompt = false
            },
            onAgree: {
                hasAcceptedInitialLegalPrompt = true
                hasAgreedToLegal = true
                showsLegalValidationHighlight = false
                showsInitialLegalPrompt = false
            }
        )
    }

    private var headerCluster: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "shield")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.95))
                    .font(.largeTitle.weight(.semibold))
            }
            .frame(width: 90, height: 90)
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .onTapGesture {
                handleIconTap()
            }

            VStack(spacing: 6) {
                Text(L10n.text("auth.login.welcome"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.text("auth.login.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
        }
        .padding(.top, 28)
    }

    private var actionButtons: some View {
        VStack(spacing: 14) {
            ZStack {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: { request in
                        viewModel.prepareAppleRequest(request)
                    },
                    onCompletion: { result in
                        Task {
                            await viewModel.signInWithApple(result: result)
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(maxWidth: 375)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(hasAgreedToLegal ? 1 : 0.55)
                .allowsHitTesting(hasAgreedToLegal)

                if hasAgreedToLegal == false {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            requireLegalAgreementBeforeLogin()
                        }
                        .accessibilityLabel(L10n.text("auth.login.legal.must_agree_hint"))
                }
            }

            if showPhoneLogin {
                HStack {
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                    Text("或")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
                }
                .padding(.vertical, 6)

                Button {
                    if hasAgreedToLegal {
                        path.append(.phone)
                    } else {
                        requireLegalAgreementBeforeLogin()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "phone").font(.body)
                        Text(L10n.text("auth.login.phone_button"))
                            .font(.body)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(
                    OutlinedButtonStyle(
                        tint: Color.accentColor.opacity(0.35),
                        hover: Color.accentColor.opacity(0.12)
                    )
                )
            }

            if mode == .primarySignIn {
                Button {
                    if hasAgreedToLegal {
                        Task { await viewModel.signInWithDevice() }
                    } else {
                        requireLegalAgreementBeforeLogin()
                    }
                } label: {
                    Text(L10n.text("auth.login.guest_mode"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .accessibilityHint(L10n.text("auth.login.guest_mode.accessibility_hint"))
            }
        }
    }

    private func handleIconTap() {
        let now = Date()
        if let lastTapTime, now.timeIntervalSince(lastTapTime) > 1.0 {
            tapCount = 0
        }

        tapCount += 1
        lastTapTime = now

        if tapCount >= 3 {
            showPhoneLogin = true
            tapCount = 0
        }
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(uiColor: .systemBlue))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("auth.login.safety_title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(L10n.text("auth.login.safety_body"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.5))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum LoginRoute: Hashable {
    case phone
}

private struct LoginInitialLegalPromptSheet: View {
    let fixedHeight: CGFloat
    let onDecline: () -> Void
    let onAgree: () -> Void

    var body: some View {
        AdaptiveSheetContainer(
            showConfirmButton: false,
            fixedHeight: fixedHeight,
            toolbarHeight: 0,
            contentVerticalPadding: 0,
            toolbarPlacement: .hidden,
            onCancel: onDecline
        ) {
            LoginInitialLegalPromptContent(
                onDecline: onDecline,
                onAgree: onAgree
            )
        }
    }
}

private struct LoginInitialLegalPromptContent: View {
    let onDecline: () -> Void
    let onAgree: () -> Void

    @State private var legalURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(L10n.text("auth.login.initial_prompt.title"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    legalIntro

                    Text(L10n.text("auth.login.initial_prompt.medical_disclaimer"))
                        .font(.body.weight(.semibold))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(permissionItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.secondary)
                                    .frame(width: 9, height: 9)
                                    .padding(.top, 8)

                                Text(item)
                                    .font(.body)
                                    .lineSpacing(5)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Text(L10n.text("auth.login.initial_prompt.permission_note"))
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundStyle(.secondary)

                    Text(L10n.text("auth.login.initial_prompt.security_commitment"))
                        .font(.body.weight(.semibold))
                        .lineSpacing(6)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 26)
                .padding(.top, 26)
                .padding(.bottom, 18)
            }

            HStack(spacing: 18) {
                Button(action: onDecline) {
                    Text(L10n.text("auth.login.initial_prompt.decline"))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onAgree) {
                    Text(L10n.text("auth.login.initial_prompt.agree"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color(uiColor: .systemBlue))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
                .padding(.bottom, 24)
            .background(Color(uiColor: .systemBackground))
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: Binding(
            get: { legalURL.map(IdentifiableURL.init(url:)) },
            set: { legalURL = $0?.url }
        )) { item in
            SafariWebViewSheet(url: item.url)
        }
    }

    private var legalIntro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("auth.login.initial_prompt.intro"))
                .font(.body)
                .lineSpacing(6)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button {
                    legalURL = AppEnvironment.current.termsOfServiceURL
                } label: {
                    Text(L10n.text("auth.login.initial_prompt.terms_link"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)

                Text(L10n.text("auth.login.initial_prompt.link_separator"))
                    .font(.body)
                    .foregroundStyle(.secondary)

                Button {
                    legalURL = AppEnvironment.current.privacyPolicyURL
                } label: {
                    Text(L10n.text("auth.login.initial_prompt.privacy_link"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var permissionItems: [String] {
        [
            L10n.text("auth.login.initial_prompt.permission.device"),
            L10n.text("auth.login.initial_prompt.permission.location"),
            L10n.text("auth.login.initial_prompt.permission.photos"),
            L10n.text("auth.login.initial_prompt.permission.microphone"),
            L10n.text("auth.login.initial_prompt.permission.logs")
        ]
    }
}
