import Foundation


nonisolated struct LocalModelCatalogItem: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let remoteURL: URL
    let suggestedFileName: String
    let summary: String

    init(
        id: String,
        displayName: String,
        remoteURL: URL,
        suggestedFileName: String,
        summary: String
    ) {
        self.id = id
        self.displayName = displayName
        self.remoteURL = remoteURL
        self.suggestedFileName = suggestedFileName
        self.summary = summary
    }
}

nonisolated struct LocalModelInstalled: Sendable {
    let modelName: String
    let displayName: String
    let fileName: String
}

enum LocalModelServiceError: LocalizedError {
    case fileNotFound
    case invalidGGUF
    case unsupportedURL
    case modelLoadFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "本地模型文件不存在。"
        case .invalidGGUF:
            return "仅支持 .gguf 模型文件。"
        case .unsupportedURL:
            return "模型下载链接不可用。"
        case .modelLoadFailed:
            return "本地模型加载失败，请检查模型体积与设备内存。"
        }
    }
}

actor LocalModelService {
    static let localCompany = "LOCAL"
    static let localProviderID = "LOCAL"

    private let fileManager: FileManager
    private let session: URLSession

    init(
        fileManager: FileManager = .default,
        session: URLSession = .shared
    ) {
        self.fileManager = fileManager
        self.session = session
    }

    nonisolated func builtInCatalog() -> [LocalModelCatalogItem] {
        [
            LocalModelCatalogItem(
                id: "qwen2_5_1_5b_q4_k_m",
                displayName: "Qwen2.5 1.5B (Q4_K_M)",
                remoteURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
                suggestedFileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
                summary: "轻量中文能力，适合手机端快速响应。"
            ),
            LocalModelCatalogItem(
                id: "qwen2_5_3b_q4_k_m",
                displayName: "Qwen2.5 3B (Q4_K_M)",
                remoteURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf")!,
                suggestedFileName: "qwen2.5-3b-instruct-q4_k_m.gguf",
                summary: "质量与速度平衡，推荐作为本地基座模型。"
            ),
            LocalModelCatalogItem(
                id: "deepseek_r1_1_5b_q4_k_m",
                displayName: "DeepSeek-R1 1.5B (Q4_K_M)",
                remoteURL: URL(string: "https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf")!,
                suggestedFileName: "deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf",
                summary: "推理型模型，适合结构化问答。"
            )
        ]
    }

    func localModelsDirectoryURL() throws -> URL {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LocalModelServiceError.fileNotFound
        }
        let dir = base.appendingPathComponent("LocalModels", isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) == false {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    func localModelFileURL(fileName: String) throws -> URL {
        let dir = try localModelsDirectoryURL()
        let target = dir.appendingPathComponent(fileName, isDirectory: false)
        guard fileManager.fileExists(atPath: target.path) else {
            throw LocalModelServiceError.fileNotFound
        }
        return target
    }

    func downloadModel(_ item: LocalModelCatalogItem) async throws -> LocalModelInstalled {
        guard item.remoteURL.scheme?.hasPrefix("http") == true else {
            throw LocalModelServiceError.unsupportedURL
        }
        let (temporaryURL, _) = try await session.download(from: item.remoteURL)
        return try installModelFile(
            from: temporaryURL,
            preferredDisplayName: item.displayName,
            preferredFileName: item.suggestedFileName
        )
    }

    func importModel(from sourceURL: URL, preferredDisplayName: String? = nil) throws -> LocalModelInstalled {
        try installModelFile(
            from: sourceURL,
            preferredDisplayName: preferredDisplayName,
            preferredFileName: sourceURL.lastPathComponent
        )
    }

    func deleteModel(fileName: String) throws {
        let target = try localModelFileURL(fileName: fileName)
        try fileManager.removeItem(at: target)
    }

    private func installModelFile(
        from sourceURL: URL,
        preferredDisplayName: String?,
        preferredFileName: String
    ) throws -> LocalModelInstalled {
        guard preferredFileName.lowercased().hasSuffix(".gguf") else {
            throw LocalModelServiceError.invalidGGUF
        }
        let destinationDirectory = try localModelsDirectoryURL()
        let uniqueFileName = try makeUniqueFileName(
            preferredFileName: preferredFileName,
            destinationDirectory: destinationDirectory
        )
        let destinationURL = destinationDirectory.appendingPathComponent(uniqueFileName, isDirectory: false)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let displayName = (preferredDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? preferredDisplayName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : uniqueFileName.replacingOccurrences(of: ".gguf", with: "")
        let modelName = makeStableModelName(from: uniqueFileName)
        return LocalModelInstalled(modelName: modelName, displayName: displayName, fileName: uniqueFileName)
    }

    private func makeUniqueFileName(
        preferredFileName: String,
        destinationDirectory: URL
    ) throws -> String {
        var candidate = preferredFileName
        var index = 1
        while fileManager.fileExists(atPath: destinationDirectory.appendingPathComponent(candidate).path) {
            let stem = (preferredFileName as NSString).deletingPathExtension
            let ext = (preferredFileName as NSString).pathExtension
            candidate = "\(stem)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    private func makeStableModelName(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        let transformed = stem.lowercased().replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
        return "local-\(transformed.trimmingCharacters(in: CharacterSet(charactersIn: "-")))"
    }
}
