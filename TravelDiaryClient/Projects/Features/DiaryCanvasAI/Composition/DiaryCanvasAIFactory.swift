import Foundation

@MainActor enum DiaryCanvasAIFactory {
    static func make(_ session: DiaryEditorSession) -> DiaryAIDraftController {
        DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: DiaryArkResponsesClient())
    }
}
