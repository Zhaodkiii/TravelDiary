import Foundation

/// Lists can remain visible offline, but signed pagination cursors are short-lived.
nonisolated enum MaterialPaginationPolicy {
    struct Expired: Error { }
    static func expired(_ cursor: String, now: Date = Date()) -> Bool {
        let parts = cursor.split(separator: ":")
        guard parts.count >= 3 else { return true }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        var seconds: Double = 0
        for char in parts[parts.count - 2] {
            guard let value = alphabet.firstIndex(of: char) else { return true }
            seconds = seconds * 62 + Double(value)
        }
        let age = now.timeIntervalSince1970 - seconds
        // Leave five minutes for requests/clock skew before the server's 30-minute limit.
        return !age.isFinite || age < -300 || age >= 1500
    }
    static func shouldRestart(_ error: Error) -> Bool {
        if error is Expired { return true }
        guard case let SupportNetworkError.http(statusCode: 410, backend: _, data: data) = error else { return false }
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = body?["msg"] as? [String: Any]
        let code = message?["code"] as? String ?? body?["code"] as? String
        if let code { return ["CURSOR_EXPIRED", "SNAPSHOT_MISSING"].contains(code) }
        // Compatibility with the old server's ambiguous cursor-only 410 response.
        return body?["msg"] is String
    }
}
