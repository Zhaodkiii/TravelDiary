//
// Signal Camera - SecondCameraEditorAtomicValue shim
//

import Foundation

public final class SecondCameraEditorAtomicValue<T>: @unchecked Sendable {
    private let lock: SecondCameraEditorUnfairLock
    private nonisolated(unsafe) var value: T

    nonisolated public init(_ value: T, lock: SecondCameraEditorUnfairLock) {
        self.value = value
        self.lock = lock
    }

    nonisolated public func get() -> T {
        lock.withLock { value }
    }

    nonisolated public func set(_ newValue: T) {
        lock.withLock { value = newValue }
    }

    @discardableResult
    nonisolated public func swap(_ newValue: T) -> T {
        lock.withLock {
            let oldValue = value
            value = newValue
            return oldValue
        }
    }

    @discardableResult
    nonisolated public func map(_ block: (T) -> T) -> T {
        lock.withLock {
            let newValue = block(value)
            value = newValue
            return newValue
        }
    }

    @discardableResult
    nonisolated public func update<Result>(block: (inout T) -> Result) -> Result {
        lock.withLock {
            block(&value)
        }
    }
}
