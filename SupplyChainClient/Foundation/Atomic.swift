import Foundation

/// 轻量级原子容器。
/// 适合承载少量全局配置或跨线程共享状态，不适合替代更复杂的 actor 业务边界。
final class Atomic<Value>: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var storage: Value

    nonisolated init(_ value: Value) {
        self.storage = value
    }

    nonisolated var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    @discardableResult
    nonisolated
    func withValue<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storage)
    }
}
