import Foundation
import CoreGraphics

nonisolated enum DiaryAIError: LocalizedError, Sendable {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let text): text } }
}
nonisolated struct DiaryAIFont: Codable, Sendable { var id: String; var version: String; var name: String }
nonisolated struct DiaryAIObject: Codable, Identifiable, Sendable {
    var id: UUID
    var shortID: String
    var name: String
    var role: String
    var center: CGPoint
    var bounds: CGRect
    var scale: Double
    var angle: Double
    var locked: Bool
    var visible: Bool
    var editable: Bool
    var text: String?
    var assetIDs: [UUID]
}
nonisolated struct DiaryAIContext: Codable, Sendable {
    var id: UUID
    var digest: String
    var contentID: UUID
    var size: CGSize
    var spineX: Double?
    var objects: [DiaryAIObject]
    var fonts: [DiaryAIFont]
    var frameStyles: [String] = ["手撕纸", "简洁纸边", "拍立得"]
}
/// Planned page regions use design units and survive model context recovery.
nonisolated struct DiaryAILayoutRegion: Codable, Sendable {
    var role: String
    var objectID: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var bounds: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
nonisolated struct DiaryAIVisualRevision: Codable, Sendable {
    var ids: [UUID]
    var reason: String
    var attempt: Int
}
nonisolated struct DiaryAIImage: Sendable { var id: String; var caption: String; var data: Data }
nonisolated struct DiaryAIOperation: Codable, Sendable {
    var operationID: String
    var type: String
    var objectID: UUID?
    var clientObjectKey: String?
    var textRole: String? = nil
    var center: CGPoint?
    var scale: Double?
    var angle: Double?
    var order: [UUID]?
    var text: String?
    var fontID: String?
    var fontSize: Double?
    var width: Double?
    var color: String?
    var paper: String?
    var visible: Bool?
    var maxHeight: Double?
    var cropZoom: Double?
    var cropX: Double?
    var cropY: Double?
    var frameStyle: String?
    var materialID: UUID?
}
nonisolated struct DiaryAIPlan: Codable, Sendable {
    var schemaVersion: Int
    var contextID: UUID
    var baseDigest: String
    var summary: String
    var operations: [DiaryAIOperation]
}
nonisolated struct DiaryAIToolCall: Sendable { var id: String; var name: String; var arguments: String }
nonisolated struct DiaryAIModelReply: Sendable {
    var calls: [DiaryAIToolCall]
    var text: String
    var continuation: Data
    var inputTokens: Int?
    var outputTokens: Int?
}
nonisolated struct DiaryAIToolResult: Sendable { var callID: String; var text: String; var images: [DiaryAIImage] = [] }
nonisolated struct DiaryAIDraft: Sendable {
    var id: UUID
    var revision: Int
    var preview: Data
    var archive: Data
    var summary: String
    var warnings: [String]
}
nonisolated struct DiaryAIToolArguments: Codable {
    var contextID: UUID?
    var objectIDs: [UUID]?
    var view: String?
    var rect: CGRect?
    var plan: DiaryAIPlan?
    var draftRevision: Int?
}

@MainActor protocol DiaryAIModelClient {
    func respond(prompt: String?, images: [DiaryAIImage], continuation: Data?, results: [DiaryAIToolResult]) async throws -> DiaryAIModelReply
}
@MainActor protocol DiaryAIEditorBridge: AnyObject {
    var storageKey: String { get }
    var scopeTitle: String { get }
    var canvasSize: CGSize? { get }
    var selectionAvailable: Bool { get }
    var objectChoices: [DiaryAIObject] { get }
    var gesturesActive: Bool { get }
    func capture(_ request: DiaryAIRequest) async throws -> DiaryAIContext
    func originalPreview() async throws -> Data
    func initialImages(_ request: DiaryAIRequest) async throws -> [DiaryAIImage]
    func inspect(_ arguments: DiaryAIToolArguments) async throws -> [DiaryAIImage]
    func propose(_ plan: DiaryAIPlan) async throws -> DiaryAIDraft
    func restore(_ archive: Data) throws -> DiaryAIDraft
    func apply() throws
    func discard()
}

extension DiaryAIEditorBridge { var canvasSize: CGSize? { nil } }
