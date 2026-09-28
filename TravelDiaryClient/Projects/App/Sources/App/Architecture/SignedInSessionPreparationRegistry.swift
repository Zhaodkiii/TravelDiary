import Foundation

/// 已登录冷启动/账号引导阶段状态。
enum SignedInLaunchPreparationState: Equatable, Sendable {
    case idle
    case preparing(accountID: Int64)
    case prepared(accountID: Int64)
}

/// 串行化已登录账号准备，支持并发调用方等待同一 in-flight 任务。
@MainActor
final class SignedInSessionPreparationRegistry {
    private(set) var state: SignedInLaunchPreparationState = .idle
    private var preparationTask: Task<Void, Never>?
    private var preparationAccountID: Int64?

    var preparedAccountID: Int64? {
        if case .prepared(let accountID) = state {
            return accountID
        }
        return nil
    }

    func runPreparationIfNeeded(
        accountID: Int64,
        operation: @escaping () async -> Void
    ) async {
        if case .prepared(let preparedID) = state, preparedID == accountID {
            return
        }
        if let preparationTask, preparationAccountID == accountID {
            await preparationTask.value
            return
        }

        state = .preparing(accountID: accountID)
        let task = Task {
            await operation()
        }
        preparationTask = task
        preparationAccountID = accountID
        await task.value
        preparationTask = nil
        preparationAccountID = nil
    }

    func markPrepared(accountID: Int64) {
        state = .prepared(accountID: accountID)
    }

    func rollbackPreparingIfNeeded(accountID: Int64) {
        if case .preparing(let preparingID) = state, preparingID == accountID {
            state = .idle
        }
    }

    func reset() {
        if preparationTask != nil {
            ConsoleLogger().debug(
                "SignedInSessionPreparationRegistry：取消进行中的账号准备任务 accountID=\(preparationAccountID.map(String.init) ?? "-")",
                module: .lifecycle
            )
        }
        preparationTask?.cancel()
        preparationTask = nil
        preparationAccountID = nil
        state = .idle
    }
}
