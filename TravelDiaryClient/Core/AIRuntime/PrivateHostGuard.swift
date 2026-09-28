import Foundation
import Network

/// SSRF guard aligned with DeepTutorServer `web_fetch._is_disallowed_host`.
nonisolated enum PrivateHostGuard {
    static func isDisallowedHost(_ host: String) -> Bool {
        var candidate = host.trimmingCharacters(in: .whitespacesAndNewlines)
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard candidate.isEmpty == false else { return true }

        if let ipv4 = IPv4Address(candidate) {
            return isDisallowedIPv4(ipv4)
        }
        if let ipv6 = IPv6Address(candidate) {
            return isDisallowedIPv6(ipv6)
        }

        let lower = candidate.lowercased()
        if lower == "localhost" || lower == "ip6-localhost" || lower == "ip6-loopback" {
            return true
        }
        if lower.hasSuffix(".local") {
            return true
        }

        let addresses = resolveAddresses(for: candidate)
        if addresses.isEmpty {
            return true
        }
        for address in addresses where isDisallowedAddressString(address) {
            return true
        }
        return false
    }

    private static func isDisallowedIPv4(_ address: IPv4Address) -> Bool {
        let raw = address.rawValue
        let first = raw[0]
        let second = raw[1]

        if first == 127 { return true }
        if first == 10 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        if first == 192 && second == 168 { return true }
        if first == 169 && second == 254 { return true }
        if (224...239).contains(first) { return true }
        if first == 0 { return true }
        return false
    }

    private static func isDisallowedIPv6(_ address: IPv6Address) -> Bool {
        let raw = address.rawValue
        if raw.allSatisfy({ $0 == 0 }) { return true }
        if raw[0] == 0 && raw[1] == 0 && raw[2] == 0 && raw[3] == 0
            && raw[4] == 0 && raw[5] == 0 && raw[6] == 0 && raw[7] == 0
            && raw[8] == 0 && raw[9] == 0 && raw[10] == 0 && raw[11] == 0
            && raw[12] == 0 && raw[13] == 0 && raw[14] == 0 && raw[15] == 1 {
            return true
        }
        if raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80 { return true }
        if (raw[0] & 0xfe) == 0xfc { return true }
        if raw[0] == 0xff { return true }
        return false
    }

    private static func resolveAddresses(for host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let result else { return [] }
        defer { freeaddrinfo(result) }

        var addresses: [String] = []
        var pointer: UnsafeMutablePointer<addrinfo>? = result
        while let info = pointer?.pointee {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.ai_addr,
                socklen_t(info.ai_addrlen),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                addresses.append(String(cString: hostname))
            }
            pointer = info.ai_next
        }
        return addresses
    }

    private static func isDisallowedAddressString(_ address: String) -> Bool {
        var trimmed = address
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        if trimmed.lowercased().hasPrefix("::ffff:") {
            let ipv4Part = String(trimmed.dropFirst("::ffff:".count))
            if let ipv4 = IPv4Address(ipv4Part) {
                return isDisallowedIPv4(ipv4)
            }
        }
        if let ipv4 = IPv4Address(trimmed) {
            return isDisallowedIPv4(ipv4)
        }
        if let ipv6 = IPv6Address(trimmed) {
            return isDisallowedIPv6(ipv6)
        }
        return true
    }
}
