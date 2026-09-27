//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

nonisolated public func secondCameraEditorAssertOnQueue(_ queue: DispatchQueue) {
    dispatchPrecondition(condition: .onQueue(queue))
}

@inlinable
nonisolated public func SecondCameraEditorAssertIsOnMainThread(
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !Thread.isMainThread {
        secondCameraEditorFailDebug("Must be on main thread.", logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
nonisolated public func SecondCameraEditorAssertNotOnMainThread(
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if Thread.isMainThread {
        secondCameraEditorFailDebug("Must be off main thread.", logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
nonisolated public func secondCameraEditorFailDebug(
    _ logMessage: String,
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    logger.error(logMessage, file: file, function: function, line: line)
    logger.flush()
    if SecondCameraEditorIsDebuggerAttached() {
        SecondCameraEditorTrapDebugger()
    } else if SecondCameraEditorPreferences.isFailDebugEnabled {
        SecondCameraEditorPreferences.setIsFailDebugEnabled(false)
        fatalError(logMessage)
    } else {
        assertionFailure(logMessage)
    }
}

@inlinable
nonisolated public func secondCameraEditorAssertBeta(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "") {
    assert(condition(), message())
}

@inlinable
nonisolated public func secondCameraEditorFail(
    _ logMessage: String,
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) -> Never {
    logger.error(Thread.callStackSymbols.joined(separator: "\n"))
    secondCameraEditorFailDebug(logMessage, logger: logger, file: file, function: function, line: line)
    fatalError(logMessage)
}

@discardableResult
nonisolated public func secondCameraEditorFailIfThrows<T>(
    block: () throws -> T,
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) -> T {
    do {
        return try block()
    } catch {
        secondCameraEditorFail("Failing for unexpected throw: \(error)", file: file, function: function, line: line)
    }
}

@inlinable
nonisolated public func secondCameraEditorAssertDebug(
    _ condition: Bool,
    _ message: @autoclosure () -> String = String(),
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !condition {
        let message: String = message()
        secondCameraEditorFailDebug(message.isEmpty ? "Assertion failed." : message, logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
nonisolated public func secondCameraEditorPrecondition(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = String(),
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !condition() {
        let message: String = message()
        secondCameraEditorFail(message.isEmpty ? "Assertion failed." : message, logger: logger, file: file, function: function, line: line)
    }
}

@inlinable
nonisolated public func secondCameraEditorFailBeta(
    _ logMessage: String,
    logger: SecondCameraEditorPrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    secondCameraEditorFailDebug(logMessage, logger: logger, file: file, function: function, line: line)
}

@objc
public class SecondCameraEditorSwiftUtils: NSObject {
    @objc
    public class func secondCameraEditorFailObjC(
        _ logMessage: String,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
    ) -> Never {
        secondCameraEditorFail(logMessage, file: file, function: function, line: line)
    }
}
