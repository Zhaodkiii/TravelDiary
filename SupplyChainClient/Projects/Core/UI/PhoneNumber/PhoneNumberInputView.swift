import SwiftUI

struct PhoneRegion: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let dial: String
    let flag: String
    let countryCode: String
}

/// 规范化手机号输入（登录、账号管理、远程邀请等共用）。
struct PhoneNumberInputModel: Equatable {
    var rawInput: String = ""
    var countryCode: String = "+86"
    var nationalNumber: String = ""
    var e164: String = ""
    var isValid: Bool = false
}

struct PhoneNumberInputView: View {
    @Binding var model: PhoneNumberInputModel
    var regions: [PhoneRegion] = defaultRegions
    var isLocked: Bool = false

    @FocusState private var isFocused: Bool
    @State private var chosenRegion: PhoneRegion = defaultRegions.first ?? .init(name: "", dial: "+86", flag: "🇨🇳", countryCode: "CN")
    @State private var isApplyingAutoRegion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(regions) { region in
                        Button("\(region.flag)  \(region.name)  \(region.dial)") {
                            guard isLocked == false else { return }
                            chosenRegion = region
                            recompute()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(chosenRegion.flag).font(.title3)
                        Text(chosenRegion.dial)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .disabled(isLocked)
                .accessibilityLabel(L10n.text("account_management.identity.phone.country_picker", fallback: "选择国家或地区"))

                TextField(L10n.text("auth.phone.placeholder"), text: $model.rawInput)
                    .keyboardType(.phonePad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .disabled(isLocked)
                    .padding(.horizontal, 12)
                    .onChange(of: model.rawInput) { newValue in
                        applyAutoRegionAndStripPrefixIfNeeded(newValue)
                    }
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .opacity(isLocked ? 0.72 : 1)

            if isLocked {
                Text(L10n.text("account_management.identity.phone.locked_hint", fallback: "验证码已发送，手机号暂不可修改"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done")) {
                    isFocused = false
                }
            }
        }
        .onAppear {
            syncChosenRegionFromModelOrSystem()
            recompute()
        }
        .onChange(of: model.countryCode) { newCode in
            guard isApplyingAutoRegion == false else { return }
            if let region = regions.first(where: { $0.dial == newCode }) {
                chosenRegion = region
            }
        }
    }

    private func syncChosenRegionFromModelOrSystem() {
        if model.countryCode.isEmpty == false,
           let matched = regions.first(where: { $0.dial == model.countryCode }) {
            chosenRegion = matched
            return
        }
        let country = SparkSystemInfo.shared.mostLikelyCountryCode
        chosenRegion = regions.first { $0.countryCode == country }
            ?? regions.first { $0.countryCode == "CN" }
            ?? chosenRegion
    }

    /// 粘贴完整国际手机号时自动切换区号，并只保留 national number。
    private func applyAutoRegionAndStripPrefixIfNeeded(_ raw: String) {
        guard isLocked == false else { return }
        guard isApplyingAutoRegion == false else { return }

        let detected = PhoneNumberNormalizer.detectRegionNumber(
            rawInput: raw,
            supportedDials: regions.map(\.dial)
        )
        guard let detected,
              let region = regions.first(where: { $0.dial == detected.dial }) else {
            recompute()
            return
        }

        isApplyingAutoRegion = true
        chosenRegion = region
        model.rawInput = detected.nationalDigits
        recompute()
        isApplyingAutoRegion = false
    }

    private func recompute() {
        let raw = model.rawInput
        let dial = chosenRegion.dial
        let normalized = PhoneNumberNormalizer.normalize(rawInput: raw, defaultDial: dial)
        let e164 = normalized.e164
        let national = normalized.nationalDigits
        let isValid = national.count >= 7 && national.count <= 15
        model = PhoneNumberInputModel(
            rawInput: raw,
            countryCode: dial,
            nationalNumber: national,
            e164: e164,
            isValid: isValid
        )
    }
}
