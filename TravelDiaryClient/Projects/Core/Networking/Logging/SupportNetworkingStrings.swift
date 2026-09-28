import Foundation

/// 网络模块统一日志文案（单行、无 header/body）。
enum SupportNetworkingStrings {

    enum Backend {
        static let initialized = "Backend 初始化完成，已装配 HTTPClient、Operation、CallbackCache"

        nonisolated static func executing(api: String, operation: String, business: String) -> String {
            "Backend 即将执行 业务=\(business) API=\(api) Operation=\(operation)"
        }

        nonisolated static func callbackCacheHit(key: String, operation: String, business: String) -> String {
            "Operation 复用进行中的请求 业务=\(business) operation=\(operation) cacheKey=\(key)"
        }

        nonisolated static func callbackCacheMiss(key: String, operation: String, business: String) -> String {
            "Operation 首次发起请求 业务=\(business) operation=\(operation) cacheKey=\(key)"
        }
    }

    enum HTTPClient {
        nonisolated static func startingRequest(method: String, url: String) -> String {
            "开始网络请求 method=\(method) url=\(url)"
        }

        nonisolated static func queuedRequest(method: String, url: String, count: Int) -> String {
            "当前有请求执行中，已将请求排队 method=\(method) url=\(url) queueRemaining=\(count)"
        }

        nonisolated static func finishedRequest(method: String?, url: String?, count: Int) -> String {
            "请求执行完成 method=\(method ?? "-") url=\(url ?? "-") queueRemaining=\(count)"
        }

        nonisolated static func retryingRequest(method: String, url: String, retry: Int, delay: TimeInterval) -> String {
            "请求准备重试 method=\(method) url=\(url) retry=\(retry) delay=\(delay)s"
        }

        nonisolated static func completedRequest(method: String, url: String, statusCode: Int) -> String {
            "请求完成 method=\(method) url=\(url) status=\(statusCode)"
        }

        nonisolated static func failedRequest(method: String, url: String, reason: String) -> String {
            "请求失败 method=\(method) url=\(url) reason=\(reason)"
        }

        nonisolated static func authRefreshTriggered(path: String) -> String {
            "检测到 401，准备刷新令牌后重试 path=\(path)"
        }

        /// 出站摘要。
        nonisolated static func outbound(
            method: String,
            url: String,
            requestId: String
        ) -> String {
            "请求 method=\(method) url=\(url) requestId=\(requestId)"
        }

        /// 完整请求原始报文（headers 已脱敏，body 为 UTF-8 全文或二进制占位）。
        nonisolated static func outboundRaw(headers: String, body: String) -> String {
            "请求原始报文 headers=\(headers) body=\(body)"
        }

        /// 入站摘要：status、耗时、响应体字节数。
        nonisolated static func inbound(
            method: String,
            url: String,
            requestId: String,
            statusCode: Int,
            cost: TimeInterval,
            responseByteCount: Int
        ) -> String {
            "响应 method=\(method) url=\(url) requestId=\(requestId) status=\(statusCode) cost=\(String(format: "%.3f", cost))s size=\(responseByteCount)B"
        }

        /// 完整响应原始报文（headers 已脱敏，body 为 UTF-8 全文或二进制占位）。
        nonisolated static func inboundRaw(
            method: String,
            url: String,
            requestId: String,
            statusCode: Int,
            cost: TimeInterval,
            headers: String,
            body: String
        ) -> String {
            "响应原始报文 method=\(method) url=\(url) requestId=\(requestId) status=\(statusCode) cost=\(String(format: "%.3f", cost))s headers=\(headers) body=\(body)"
        }
    }

    enum ETag {
        nonisolated static func apply(tag: String, key: String) -> String {
            "附加 If-None-Match etag=\(tag) cacheKey=\(key)"
        }

        /// 304 合并后：完整缓存正文（UTF-8；若为 JSON 则 pretty-print），多行。
        nonisolated static func merged304FullPayload(path: String, cacheKey: String, byteCount: Int, presentationBody: String) -> String {
            """
            ETag 304 本地缓存完整响应体 path=\(path) cacheKey=\(cacheKey) bytes=\(byteCount)
            --- body ---
            \(presentationBody)
            """
        }

        nonisolated static func store(tag: String, key: String) -> String {
            "更新 ETag 缓存 etag=\(tag) cacheKey=\(key)"
        }

        nonisolated static func skipStaleCache(key: String) -> String {
            "ETag 缓存已过期，跳过 If-None-Match cacheKey=\(key)"
        }
    }

    enum Auth {
        nonisolated static func refreshing() -> String {
            "访问令牌即将过期或已失效，开始刷新令牌"
        }

        nonisolated static func refreshSucceeded() -> String {
            "令牌刷新成功"
        }

        nonisolated static func refreshFailed() -> String {
            "令牌刷新失败，已清理本地认证信息"
        }
    }
}
