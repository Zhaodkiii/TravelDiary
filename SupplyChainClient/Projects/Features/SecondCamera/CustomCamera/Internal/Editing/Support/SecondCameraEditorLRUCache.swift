//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// A simple LRU cache bounded by the number of entries.
public class SecondCameraEditorLRUCache<KeyType: Hashable & Equatable, ValueType> {

    private nonisolated(unsafe) let cache = NSCache<AnyObject, AnyObject>()
    private nonisolated(unsafe) let _resetCount = SecondCameraEditorAtomicUInt(0, lock: .sharedGlobal)
    nonisolated public var resetCount: UInt {
        _resetCount.get()
    }

    nonisolated public var maxSize: Int {
        get {
            return cache.countLimit
        }
        set {
            cache.countLimit = newValue
        }
    }

    nonisolated public init(
        maxSize: Int,
        nseMaxSize: Int = 0,
        shouldEvacuateInBackground: Bool = false,
    ) {
        self.cache.countLimit = SecondCameraEditorCurrentAppContext().isNSE ? nseMaxSize : maxSize

        if
            SecondCameraEditorCurrentAppContext().isMainApp,
            shouldEvacuateInBackground
        {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didEnterBackground),
                name: .SecondCameraEditorApplicationDidEnterBackground,
                object: nil,
            )
        }
    }

    @objc
    nonisolated private func didEnterBackground() {
        SecondCameraEditorAssertIsOnMainThread()

        clear()
    }

    nonisolated public func get(key: KeyType) -> ValueType? {
        // ValueType might be AnyObject, so we need to check
        // rawValue for nil; value might be NSNull.
        let rawValue = cache.object(forKey: wrapKeyIfNeeded(key))
        guard let rawValue, let value = rawValue as? ValueType else {
            return nil
        }
        secondCameraEditorAssertDebug(!(value is NSNull))
        return value
    }

    nonisolated public func set(key: KeyType, value: ValueType) {
        if value is NSNull {
            secondCameraEditorFailDebug("Nil value.")
            remove(key: key)
            return
        }
        guard cache.countLimit > 0 else {
            return
        }
        cache.setObject(value as AnyObject, forKey: wrapKeyIfNeeded(key))
    }

    nonisolated public func remove(key: KeyType) {
        cache.removeObject(forKey: wrapKeyIfNeeded(key))
    }

    @objc
    nonisolated public func clear() {
        _resetCount.increment()

        autoreleasepool {
            cache.removeAllObjects()
        }
    }

    nonisolated public subscript(key: KeyType) -> ValueType? {
        get {
            get(key: key)
        }
        set(value) {
            if let value {
                set(key: key, value: value)
            } else {
                remove(key: key)
            }
        }
    }

    // MARK: - NSCache Compatibility

    nonisolated public func setObject(_ value: ValueType, forKey key: KeyType) {
        set(key: key, value: value)
    }

    nonisolated public func object(forKey key: KeyType) -> ValueType? {
        self.get(key: key)
    }

    nonisolated public func removeObject(forKey key: KeyType) {
        remove(key: key)
    }

    nonisolated public func removeAllObjects() {
        clear()
    }

    // MARK: - Non-NSObject Compatibility

    private class WrappedKey: NSObject {
        nonisolated(unsafe) let wrappedValue: KeyType
        nonisolated init(_ wrappedValue: KeyType) {
            self.wrappedValue = wrappedValue
        }

        nonisolated override func isEqual(_ object: Any?) -> Bool {
            return self.wrappedValue == (object as? WrappedKey)?.wrappedValue
        }

        nonisolated override var hash: Int {
            return self.wrappedValue.hashValue
        }
    }

    nonisolated private func wrapKeyIfNeeded(_ key: KeyType) -> AnyObject {
        // Swift classes that don't inherit from NSObject "work" with NSCache, but
        // they "work" via pointer comparisons, and that's almost certainly
        // unintentional for Equatable & Hashable types.
        if KeyType.self is AnyClass, !(key is NSObject) {
            return WrappedKey(key)
        }
        return key as AnyObject
    }

}

// MARK: -

// NSCache sometimes evacuates entries off the main thread.
// Some cached entities should only be deallocated on the main thread.
// This handle can be used to ensure that cache entries are released
// on the main thread.
public class SecondCameraEditorThreadSafeCacheHandle<T: AnyObject> {

    nonisolated(unsafe) public let value: T

    public init(_ value: T) {
        self.value = value
    }

    deinit {
        guard !Thread.isMainThread else {
            return
        }
        SecondCameraEditorThreadSafeCacheReleaser.releaseOnMainThread(value)
    }
}

// MARK: -

// Some caches use SecondCameraEditorThreadSafeCacheHandle to ensure that their
// values are released on the main thread.  If one of these caches
// evacuated a large number of values at the same time off the main
// thread, we wouldn't want to dispatch to the main thread once for
// each value. This class buffers the values and releases them in
// batches.
private class SecondCameraEditorThreadSafeCacheReleaser {
    private nonisolated(unsafe) static let unfairLock = SecondCameraEditorUnfairLock()
    private nonisolated(unsafe) static let valuesToRelease = SecondCameraEditorAtomicValue<[AnyObject]>([], lock: unfairLock)

    nonisolated fileprivate static func releaseOnMainThread(_ value: AnyObject) {
        let shouldSchedule = valuesToRelease.update { values in
            let shouldSchedule = values.isEmpty
            values.append(value)
            return shouldSchedule
        }
        if shouldSchedule {
            DispatchQueue.main.async {
                Self.releaseValues()
            }
        }
    }

    nonisolated private static func releaseValues() {
        SecondCameraEditorAssertIsOnMainThread()

        autoreleasepool {
            var valuesToRelease: [AnyObject] = Self.valuesToRelease.swap([])
            // To avoid deadlock, we release the values without unfairLock acquired.
            secondCameraEditorAssertDebug(valuesToRelease.count > 0)
            SecondCameraEditorLogger.info("Releasing \(valuesToRelease.count) values.")
            valuesToRelease = []
            secondCameraEditorAssertDebug(valuesToRelease.isEmpty)
        }
    }
}
