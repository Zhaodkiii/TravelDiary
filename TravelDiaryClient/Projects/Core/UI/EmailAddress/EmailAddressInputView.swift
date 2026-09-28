import SwiftUI

struct EmailAddressInputModel: Equatable {
    var localPart: String = ""
    var selectedDomain: String = ""
    var customDomain: String = ""
    var isCustomDomain: Bool = false
    var normalizedEmail: String = ""
    var isValid: Bool = false
    var validationError: EmailAddressValidationError?
}

struct EmailAddressInputView: View {
    @Binding var model: EmailAddressInputModel
    var knownDomains: [String] = []
    var isLocked: Bool = false

    @FocusState private var focusedField: Field?
    @State private var resolvedDomains: [String] = []
    @State private var isApplyingParsedInput = false

    private enum Field {
        case localPart
        case customDomain
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                TextField(
                    L10n.text("account_management.identity.email.local_placeholder", fallback: "邮箱用户名"),
                    text: $model.localPart
                )
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .localPart)
                .disabled(isLocked)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .onChange(of: model.localPart) { newValue in
                    applyAddressInputIfNeeded(newValue)
                }

                Divider()
                    .frame(height: 26)

                if model.isCustomDomain {
                    HStack(spacing: 4) {
                        Text("@")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        TextField(
                            L10n.text("account_management.identity.email.custom_domain_placeholder", fallback: "company.com"),
                            text: customDomainBinding
                        )
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .customDomain)
                        .disabled(isLocked)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else {
                    Menu {
                        ForEach(resolvedDomains, id: \.self) { domain in
                            Button(domain) {
                                guard isLocked == false else { return }
                                model.isCustomDomain = false
                                model.selectedDomain = domain
                                recompute()
                            }
                        }
                        Divider()
                        Button(L10n.text("account_management.identity.email.custom_domain", fallback: "自定义后缀")) {
                            guard isLocked == false else { return }
                            model.isCustomDomain = true
                            if model.customDomain.isEmpty {
                                model.customDomain = "@"
                            }
                            recompute()
                            focusedField = .customDomain
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(currentDomainDisplay)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 112)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .disabled(isLocked)
                    .accessibilityLabel(L10n.text("account_management.identity.email.domain_picker", fallback: "选择邮箱后缀"))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.6))
            )
            .opacity(isLocked ? 0.72 : 1)

            if let validationError, shouldShowValidation {
                Text(L10n.text(validationError.localizedKey, fallback: validationError.fallback))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isLocked {
                Text(L10n.text("account_management.identity.email.locked_hint", fallback: "验证码已发送，邮箱暂不可修改"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L10n.text("common.done")) {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            if resolvedDomains.isEmpty {
                resolvedDomains = knownDomains.isEmpty ? DefaultEmailDomains.ordered : knownDomains
            }
            if model.selectedDomain.isEmpty {
                model.selectedDomain = resolvedDomains.first ?? "@qq.com"
            }
            recompute()
        }
    }

    private var validationError: EmailAddressValidationError? {
        model.validationError
    }

    private var shouldShowValidation: Bool {
        model.localPart.isEmpty == false || model.customDomain.isEmpty == false || model.isCustomDomain
    }

    private var currentDomainDisplay: String {
        if model.isCustomDomain {
            let normalized = EmailAddressNormalizer.normalizeDomain(model.customDomain)
            return normalized.isEmpty ? "@..." : normalized
        }
        let normalized = EmailAddressNormalizer.normalizeDomain(model.selectedDomain)
        return normalized.isEmpty ? (resolvedDomains.first ?? "@qq.com") : normalized
    }

    private var customDomainBinding: Binding<String> {
        Binding(
            get: {
                let normalized = EmailAddressNormalizer.normalizeDomain(model.customDomain)
                if normalized.hasPrefix("@") {
                    return String(normalized.dropFirst())
                }
                return normalized
            },
            set: { newValue in
                guard isLocked == false else { return }
                model.customDomain = newValue
                recompute()
            }
        )
    }

    private func applyAddressInputIfNeeded(_ raw: String) {
        guard isLocked == false else {
            recompute()
            return
        }
        guard isApplyingParsedInput == false else { return }

        let normalized = raw.replacingOccurrences(of: "＠", with: "@")
        guard normalized.contains("@") else {
            recompute()
            return
        }

        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            recompute()
            return
        }

        isApplyingParsedInput = true
        defer { isApplyingParsedInput = false }

        model.localPart = String(parts[0])
        let domainPart = String(parts[1])
        if domainPart.isEmpty {
            model.isCustomDomain = true
            model.customDomain = ""
        } else {
            applyDetectedDomain("@\(domainPart)")
        }
        recompute()
    }

    private func applyDetectedDomain(_ rawDomain: String) {
        let normalizedDomain = EmailAddressNormalizer.normalizeDomain(rawDomain)
        if resolvedDomains.contains(normalizedDomain) {
            model.isCustomDomain = false
            model.selectedDomain = normalizedDomain
            model.customDomain = ""
        } else {
            model.isCustomDomain = true
            model.customDomain = normalizedDomain
        }
    }

    private func recompute() {
        let normalizedLocal = EmailAddressNormalizer.normalizeLocalPart(model.localPart)
        let defaultDomain = resolvedDomains.first ?? "@qq.com"
        let selectedDomain = model.selectedDomain.isEmpty ? defaultDomain : model.selectedDomain
        let normalizedSelectedDomain = EmailAddressNormalizer.normalizeDomain(selectedDomain)
        let normalizedCustomDomain = EmailAddressNormalizer.normalizeDomain(model.customDomain)
        let domain = model.isCustomDomain ? normalizedCustomDomain : normalizedSelectedDomain
        let validationError = EmailAddressNormalizer.validate(localPart: normalizedLocal, domain: domain)
        let normalizedEmail = validationError == nil
            ? EmailAddressNormalizer.normalize(localPart: normalizedLocal, domain: domain)
            : ""

        model = EmailAddressInputModel(
            localPart: normalizedLocal,
            selectedDomain: normalizedSelectedDomain,
            customDomain: normalizedCustomDomain,
            isCustomDomain: model.isCustomDomain,
            normalizedEmail: normalizedEmail,
            isValid: validationError == nil,
            validationError: validationError
        )
    }
}
