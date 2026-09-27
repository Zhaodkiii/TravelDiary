import UIKit

@MainActor
protocol AISettingsPromptToolingProviding: AnyObject {
    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String
    func translate(text: String) async throws -> String
    func ocrImage(_ image: UIImage) async throws -> String
}

@MainActor
final class DefaultAISettingsPromptTooling: AISettingsPromptToolingProviding {
    private let ocrOrchestrator: OCROrchestrator

    init(ocrOrchestrator: OCROrchestrator) {
        self.ocrOrchestrator = ocrOrchestrator
    }

    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String { "" }
    func translate(text: String) async throws -> String { text }

    func ocrImage(_ image: UIImage) async throws -> String {
        let recognition = try await ocrOrchestrator.recognize(image: image)
        return recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class UnavailableAISettingsPromptTooling: AISettingsPromptToolingProviding {
    nonisolated init() {}

    func autoFillAgentPrompt(displayName: String, baseModelName: String) async throws -> String { "" }
    func translate(text: String) async throws -> String { text }
    func ocrImage(_ image: UIImage) async throws -> String { "" }
}
