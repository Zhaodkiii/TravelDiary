/// SparkClient 日志 API 兼容层，供迁移的 CustomCamera 模块使用。
enum SparkLogger {
    static func log(level: LogLevel, module: LogModule, message: String) {
        SupportLogger.log(level: level, module: module, message: message)
    }
}
