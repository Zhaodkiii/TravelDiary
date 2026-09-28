import Foundation

enum RetryAfterParserError: Error {
    case invalidFormat
    case invalidDate
}

enum RetryAfterParser {
    /// Parse `Retry-After` header.
    /// - Supports: `delta-seconds` (integer) and HTTP-date.
    static func parseSeconds(from headerValue: String?, now: Date = Date()) -> TimeInterval? {
        guard let headerValue else { return nil }
        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) delta-seconds (RFC: either integer seconds)
        if let seconds = TimeInterval(trimmed), seconds >= 0 {
            return seconds
        }

        // 2) HTTP-date (RFC1123)
        let formats: [String] = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                let delta = date.timeIntervalSince(now)
                return delta >= 0 ? delta : 0
            }
        }

        return nil
    }
}

protocol RetryScheduler: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

struct DefaultRetryScheduler: RetryScheduler {
    func sleep(for seconds: TimeInterval) async throws {
        let clamped = max(0, seconds)
        let nanoseconds = UInt64(clamped * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

struct RetryPolicy: Sendable {
    let config: RetryConfig
    let scheduler: RetryScheduler

    init(config: RetryConfig = .default, scheduler: RetryScheduler = DefaultRetryScheduler()) {
        self.config = config
        self.scheduler = scheduler
    }

    func canRetry(retryCount: Int) -> Bool {
        retryCount < config.maxRetryCount
    }

    func shouldRetry(statusCode: Int?, error: URLError?) -> Bool {
        if let statusCode, config.retryableStatusCodes.contains(statusCode) {
            return true
        }
        if let error, config.retryableURLErrorCodes.contains(error.code) {
            return true
        }
        return false
    }

    func computeDelaySeconds(
        retryCount: Int,
        retryAfterHeader: String?,
        responseStatusCode: Int?
    ) -> TimeInterval {
        if config.honorsRetryAfter {
            if let header = retryAfterHeader,
               let parsed = RetryAfterParser.parseSeconds(from: header) {
                return parsed
            }
        }

        guard !config.backoffIntervals.isEmpty else { return 0 }
        let idx = min(retryCount, config.backoffIntervals.count - 1)
        // backoffIntervals is expected to start from 0 for the first retry.
        return config.backoffIntervals[idx]
    }

    func sleepIfNeeded(
        retryCount: Int,
        retryAfterHeader: String?,
        responseStatusCode: Int?
    ) async throws {
        let delay = computeDelaySeconds(
            retryCount: retryCount,
            retryAfterHeader: retryAfterHeader,
            responseStatusCode: responseStatusCode
        )
        if delay > 0 {
            try await scheduler.sleep(for: delay)
        }
    }
}

