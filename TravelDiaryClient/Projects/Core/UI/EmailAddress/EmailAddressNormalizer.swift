import Foundation

enum EmailAddressValidationError: String, Equatable, Sendable {
    case localRequired
    case domainRequired
    case domainInvalid
    case invalidFormat
    case tooLong

    var localizedKey: String {
        switch self {
        case .localRequired:
            return "account_management.identity.email.local_required"
        case .domainRequired:
            return "account_management.identity.email.domain_required"
        case .domainInvalid:
            return "account_management.identity.email.domain_invalid"
        case .invalidFormat, .tooLong:
            return "account_management.identity.email.invalid"
        }
    }

    var fallback: String {
        switch self {
        case .localRequired:
            return "请输入邮箱用户名"
        case .domainRequired:
            return "请选择或输入邮箱后缀"
        case .domainInvalid:
            return "邮箱后缀格式不正确"
        case .invalidFormat, .tooLong:
            return "邮箱格式不正确"
        }
    }
}

enum DefaultEmailDomains {
    static let mainlandChina: [String] = [
        "@qq.com",
        "@163.com",
        "@126.com",
        "@foxmail.com",
        "@sina.com",
        "@yeah.net",
        "@icloud.com",
        "@outlook.com",
        "@hotmail.com",
        "@gmail.com"
    ]

    static let global: [String] = [
        "@gmail.com",
        "@outlook.com",
        "@hotmail.com",
        "@icloud.com",
        "@qq.com",
        "@163.com",
        "@126.com",
        "@foxmail.com",
        "@sina.com",
        "@yeah.net"
    ]

    @MainActor
    static var ordered: [String] {
        SparkSystemInfo.shared.isMostLikelyMainlandChina ? mainlandChina : global
    }
}

enum EmailAddressNormalizer {
    struct Parsed: Equatable, Sendable {
        let localPart: String
        let domain: String
        let normalizedEmail: String
        let isKnownDomain: Bool
    }

    static func normalizeLocalPart(_ raw: String) -> String {
        compact(raw)
            .replacingOccurrences(of: "＠", with: "@")
            .lowercased()
    }

    static func normalizeDomain(_ raw: String) -> String {
        let normalized = compact(raw)
            .replacingOccurrences(of: "＠", with: "@")
            .lowercased()
        guard normalized.isEmpty == false else { return "" }
        return normalized.hasPrefix("@") ? normalized : "@\(normalized)"
    }

    static func normalize(localPart: String, domain: String) -> String {
        let normalizedLocal = normalizeLocalPart(localPart)
        let normalizedDomain = normalizeDomain(domain)
        guard normalizedLocal.isEmpty == false, normalizedDomain.isEmpty == false else { return "" }
        return "\(normalizedLocal)\(normalizedDomain)"
    }

    static func parseFullEmail(_ raw: String, knownDomains: [String]) -> Parsed? {
        let normalized = compact(raw)
            .replacingOccurrences(of: "＠", with: "@")
            .lowercased()
        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let localPart = String(parts[0])
        let domainPart = String(parts[1])
        guard localPart.isEmpty == false, domainPart.isEmpty == false else { return nil }

        let normalizedLocal = normalizeLocalPart(localPart)
        let domain = normalizeDomain(domainPart)
        return Parsed(
            localPart: normalizedLocal,
            domain: domain,
            normalizedEmail: "\(normalizedLocal)\(domain)",
            isKnownDomain: knownDomains.contains(domain)
        )
    }

    static func validate(localPart: String, domain: String) -> EmailAddressValidationError? {
        let normalizedLocal = normalizeLocalPart(localPart)
        let normalizedDomain = normalizeDomain(domain)

        if normalizedLocal.isEmpty {
            return .localRequired
        }
        if normalizedDomain.isEmpty {
            return .domainRequired
        }
        if normalizedDomain == "@" {
            return .domainRequired
        }
        if normalizedLocal.contains("@") {
            return .invalidFormat
        }
        if normalizedDomain.filter({ $0 == "@" }).count != 1 {
            return .invalidFormat
        }
        if normalizedDomain.contains(" ") || normalizedLocal.contains(" ") {
            return .invalidFormat
        }
        if normalizedDomain.hasPrefix("@.") || normalizedDomain.hasSuffix(".") || normalizedDomain.contains("..") {
            return .domainInvalid
        }
        if normalizedDomain.contains(".") == false {
            return .domainInvalid
        }

        let email = "\(normalizedLocal)\(normalizedDomain)"
        if email.filter({ $0 == "@" }).count != 1 {
            return .invalidFormat
        }
        if normalizedLocal.count > 64 || email.count > 254 {
            return .tooLong
        }
        return nil
    }

    private static func compact(_ raw: String) -> String {
        raw
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
    }
}
