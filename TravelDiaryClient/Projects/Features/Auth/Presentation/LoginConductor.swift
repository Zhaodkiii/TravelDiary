import SwiftUI

struct PhoneLoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    @State private var regions: [PhoneRegion] = defaultRegions
    @State private var chosenRegion: PhoneRegion
    @State private var phone: String = ""
    @State private var isRequesting: Bool = false
    @State private var otpId: String?
    @State private var isApplyingAutoRegion: Bool = false
    @FocusState private var isPhoneFocused: Bool

    init(viewModel: LoginViewModel) {
        self.viewModel = viewModel
        let country = SparkSystemInfo.shared.mostLikelyCountryCode
        let initial = defaultRegions.first { $0.countryCode == country }
            ?? defaultRegions.first { $0.countryCode == "CN" }
            ?? defaultRegions[0]
        _chosenRegion = State(initialValue: initial)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerHero
                formPad
                if let error = viewModel.inlineError {
                    Text(error).font(.footnote).foregroundStyle(DiaryLibraryStyle.accent).padding(.horizontal)
                }
            }.frame(maxWidth: 440).padding(.vertical, 24).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DiaryLibraryStyle.background).tint(DiaryLibraryStyle.accent)
        .navigationDestination(isPresented: Binding(
            get: { otpId != nil },
            set: { isPresented in
                if isPresented == false {
                    otpId = nil
                }
            }
        )) {
            if let otpId {
                OTPVerifyView(viewModel: viewModel, region: chosenRegion, phone: phone, otpId: otpId)
            }
        }
    }

    private var headerHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "envelope.open").font(.largeTitle).foregroundStyle(DiaryLibraryStyle.accent).accessibilityHidden(true)
            Text(L10n.text("auth.phone.hero_title")).font(.largeTitle.weight(.semibold))
            Text(L10n.text("auth.phone.hero_subtitle")).foregroundStyle(DiaryLibraryStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
    }

    private var formPad: some View {
        //
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("auth.phone.field_title"))
                    .font(.footnote)
                    .fontWeight(.medium)
                HStack(spacing: 0) {
                    Menu {
                        ForEach(regions) { region in
                            Button("\(region.flag)  \(region.name)  \(region.dial)") {
                                chosenRegion = region
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(chosenRegion.flag).font(.title3)
                            Text(chosenRegion.dial)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()
                        .frame(height: 22)

                    TextField(L10n.text("auth.phone.placeholder"), text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isPhoneFocused)
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .onChange(of: phone) { newValue in
                            applyAutoRegionAndStripPrefixIfNeeded(newValue)
                        }
                }
                .padding(6)
                .background(Color(uiColor: .secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.6))
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal)

            Button(action: { requestOTP() }) {
                HStack {
                    if isRequesting { ProgressView().tint(.white) }
                    Text(L10n.text(isRequesting ? "auth.phone.sending" : "auth.phone.send_otp"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(DiaryLibraryStyle.accent)
            .disabled(!phoneIsLikelyValid || isRequesting)
            .padding(.horizontal)
        }
    }

    private var phoneIsLikelyValid: Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 6
    }

    /// 如果用户粘贴了完整的国际手机号（例如 +861538... / 00861538... / 861538...）
    /// 自动匹配并选中对应的国家/地区，同时从输入框中移除国家码
    /// 只保留国内号码用于显示（例如 1538...）
    private func applyAutoRegionAndStripPrefixIfNeeded(_ raw: String) {
        guard isApplyingAutoRegion == false else { return }
        // OTP 发送中或已发出后，禁止自动改写手机号，
        // 防止 iOS 自动填充等副作用导致号码与已发 OTP 不一致。
        guard isRequesting == false, otpId == nil else { return }
        isApplyingAutoRegion = true
        defer { isApplyingAutoRegion = false }

        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: raw,
            supportedDials: regions.map(\.dial)
        )
        guard let detected,
              let region = regions.first(where: { $0.dial == detected.dial }) else {
            return
        }

        chosenRegion = region
        phone = detected.nationalDigits
    }

    private func requestOTP() {
        guard phoneIsLikelyValid, !isRequesting else { return }
        isPhoneFocused = false
        isRequesting = true
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: chosenRegion.dial).e164
            let response = await viewModel.sendOTP(phoneNumber: full)
            isRequesting = false
            if let response {
                otpId = response.otpID
            }
        }
    }
}

struct OTPVerifyView: View {
    @ObservedObject var viewModel: LoginViewModel
    let region: PhoneRegion
    let phone: String
    @State var otpId: String
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var resendAt = Date().addingTimeInterval(60)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n.text("auth.otp.title")).font(.largeTitle.weight(.semibold))
                Text("\(L10n.text("auth.otp.sent_to")) \(region.dial) \(maskedPhone())")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                Button(L10n.text("auth.otp.change_phone")) { dismiss() }.frame(minHeight: 44)
                    .disabled(isVerifying || isResending)
                VerificationCodeField(code: $code, length: 6, onComplete: verify)
                    .disabled(isVerifying || isResending)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(ceil(resendAt.timeIntervalSince(context.date))))
                    if remaining > 0 {
                        Text("\(L10n.text("auth.otp.resend_countdown")) \(remaining)s")
                            .font(.footnote).monospacedDigit().foregroundStyle(DiaryLibraryStyle.secondary)
                    } else {
                        Button(L10n.text(isResending ? "auth.phone.sending" : "auth.otp.resend"), action: resendOTP)
                            .frame(minHeight: 44).disabled(isResending || isVerifying)
                    }
                }
                if let error = viewModel.inlineError { Text(error).font(.footnote).foregroundStyle(DiaryLibraryStyle.accent) }
                Text(L10n.text("auth.otp.safety_hint")).font(.footnote).foregroundStyle(DiaryLibraryStyle.secondary)
            }.frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity)
        }
        .background(DiaryLibraryStyle.background).tint(DiaryLibraryStyle.accent)
        .safeAreaInset(edge: .bottom) {
            Button(action: verify) {
                HStack {
                    if isVerifying { ProgressView() }
                    Text(L10n.text(isVerifying ? "auth.otp.verifying" : "auth.otp.verify_and_login"))
                }.frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(.borderedProminent).disabled(code.count != 6 || isVerifying || isResending)
                .frame(maxWidth: 400).padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
        }
    }
    private func resendOTP() {
        guard !isResending && !isVerifying && Date() >= resendAt else { return }
        isResending = true
        Task { @MainActor in
            defer { isResending = false }
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            if let response = await viewModel.sendOTP(phoneNumber: full, isResend: true) {
                otpId = response.otpID; code = ""; resendAt = Date().addingTimeInterval(60)
            }
        }
    }
    private func verify() {
        guard code.count == 6, !isVerifying, !isResending else { return }
        isVerifying = true
        Task { @MainActor in
            defer { isVerifying = false }
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            await viewModel.phoneLogin(phoneNumber: full, verificationCode: code, otpId: otpId)
        }
    }
    private func maskedPhone() -> String {
        let value = phone.filter(\.isNumber)
        guard value.count >= 7 else { return String(repeating: "•", count: value.count) }
        return "\(value.prefix(3))••••\(value.suffix(2))"
    }
}
