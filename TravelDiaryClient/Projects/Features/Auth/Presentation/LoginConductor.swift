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
        VStack(spacing: 20) {
            headerHero
            formPad
            Spacer()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: otpId)
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
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemTeal)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "phone")
                    .symbolRenderingMode(.hierarchical)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 90, height: 90)
            .shadow(color: .black.opacity(0.1), radius: 14, y: 8)

            VStack(spacing: 6) {
                Text(L10n.text("auth.phone.hero_title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(L10n.text("auth.phone.hero_subtitle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.top, 32)
        .padding(.horizontal)
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
                    Text(L10n.text("auth.phone.send_otp"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemBlue))
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
        guard phoneIsLikelyValid else { return }
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
    @State private var code: String = ""
    @State private var isVerifying: Bool = false
    @State private var countdown: Int = 60

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(L10n.text("auth.otp.title"))
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(L10n.text("auth.otp.sent_to")) \(region.dial) \(maskedPhone())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 6)

            VerificationCodeField(code: $code, length: 6, onComplete: {
                verify()
            })
                .padding(.top, 6)

            if countdown > 0 {
                Text("\(L10n.text("auth.otp.resend_countdown")) \(countdown)s")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Button(L10n.text("auth.otp.resend")) { resendOTP() }
                    .buttonStyle(.bordered)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shield")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                Text(L10n.text("auth.otp.safety_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer()
        }
        .padding()
        .onAppear { startTimer() }
        .overlay(alignment: .bottom) {
            Button(action: { verify() }) {
                HStack {
                    if isVerifying { ProgressView().tint(.white) }
                    Text(L10n.text("auth.otp.verify_and_login"))
                        .font(.body)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(uiColor: .systemBlue))
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: countdown)
    }

    private func startTimer() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }

    private func resendOTP() {
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            let response = await viewModel.sendOTP(phoneNumber: full, isResend: true)
            if let response {
                otpId = response.otpID
                startTimer()
            }
        }
    }

    private func verify() {
        guard code.count == 6 else { return }
        guard isVerifying == false else { return }
        isVerifying = true
        Task { @MainActor in
            let full = PhoneNumberNormalizer.normalize(rawInput: phone, defaultDial: region.dial).e164
            await viewModel.phoneLogin(phoneNumber: full, verificationCode: code, otpId: otpId)
            isVerifying = false
        }
    }

    private func maskedPhone() -> String {
        let trimmed = phone.replacingOccurrences(of: " ", with: "")
        guard trimmed.count >= 7 else { return phone }
        let start = trimmed.prefix(3)
        let end = trimmed.suffix(2)
        return "\(start)****\(end)"
    }
}
