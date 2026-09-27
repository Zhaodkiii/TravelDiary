import Foundation

actor SessionSnapshotStore {
    private enum Keys {
        static let currentSession = "support.session.snapshot.v1"
    }

    private let userDefaults: UserDefaults
    private let logger: Logger

    init(userDefaults: UserDefaults = .standard, logger: Logger = ConsoleLogger()) {
        self.userDefaults = userDefaults
        self.logger = logger
    }

    func load() -> UserSession? {
        guard let data = userDefaults.data(forKey: Keys.currentSession) else {
            logger.debug("会话快照：UserDefaults 无键 \(Keys.currentSession)", module: .auth)
            return nil
        }
        do {
            let session = try JSONDecoder.default.decode(UserSession.self, from: data)
            logger.debug(
                "会话快照：读取成功 accountID=\(session.accountID) bytes=\(data.count)",
                module: .auth
            )
            return session
        } catch {
            logger.error(
                "会话快照：解码失败（返回 nil，调用方可能误判为未登录）bytes=\(data.count) error=\(error.localizedDescription)",
                module: .auth
            )
            return nil
        }
    }

    func save(_ session: UserSession) throws {
        let data: Data
        do {
            data = try JSONEncoder.default.encode(session)
        } catch {
            logger.error("会话快照：编码失败 accountID=\(session.accountID) error=\(error.localizedDescription)", module: .auth)
            throw error
        }
        userDefaults.set(data, forKey: Keys.currentSession)
        logger.info("会话快照：保存成功 accountID=\(session.accountID)", module: .auth)
    }

    func clear() {
        let hadData = userDefaults.data(forKey: Keys.currentSession) != nil
        userDefaults.removeObject(forKey: Keys.currentSession)
        logger.info("会话快照：已清除本地 UserSession hadData=\(hadData)", module: .auth)
    }
}
