import Foundation

@MainActor enum DiaryCanvasAIFactory {
    static func make(_ session: DiaryEditorSession) -> DiaryAIDraftController {
        let controller = DiaryAIDraftController(bridge: DiaryEditorAIBridge(session), model: DiaryArkResponsesClient())
        controller.startInWorkspace = { [weak session] request in
            guard let session else { return }
            Task {
                await session.aiWorkspace.enter(request)
                session.aiWorkspace.configureAndStart(request)
            }
        }
        return controller
    }
}
