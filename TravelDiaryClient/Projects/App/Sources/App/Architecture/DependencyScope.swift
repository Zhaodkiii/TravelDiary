import Foundation

/// Dependency lifetime used by the composition root and feature assemblies.
enum DependencyScope: String, Sendable {
    /// Process-wide objects that survive account switches.
    case appSingleton
    /// Objects bound to the current account and reset on sign-out or account change.
    case accountScoped
    /// Objects bound to one SwiftUI scene/window.
    case sceneScoped
    /// Objects created for one screen flow or short-lived task.
    case screenScoped
}

struct ScopedDependency<Value> {
    let scope: DependencyScope
    let value: Value
}

/// 账号级缓存槽：用于标记并集中管理“同一账号会话期间复用、账号切换/登出清空”的对象。
struct AccountScopedCache<Value> {
    let scope: DependencyScope = .accountScoped
    var value: Value?
    var ownerAccountID: Int64?

    func matches(_ accountID: Int64) -> Bool {
        ownerAccountID == accountID && value != nil
    }

    mutating func store(_ newValue: Value, ownerAccountID: Int64) {
        value = newValue
        self.ownerAccountID = ownerAccountID
    }

    mutating func clear() {
        value = nil
        ownerAccountID = nil
    }
}
