import Foundation
import UIKit

nonisolated struct SupportPage<T: Decodable & Sendable>: Decodable, Sendable {
    let results: [T]
    let next_cursor: String?
}
nonisolated struct HelpCategory: Codable, Identifiable, Sendable {
    var id: String { code }
    let code: String; let name: String; let sort: Int; let active: Bool
}
nonisolated struct HelpArticle: Codable, Identifiable, Sendable {
    let id: String; let title: String; let body: String; let summary: String; let category: String
    let updated_at: String?
}
nonisolated struct HelpServiceConfig: Codable, Sendable {
    struct Kind: Codable, Identifiable, Sendable { var id: String { code }; let code: String; let name: String }
    let accepting: Bool; let pause_message: String; let service_hours: String; let contact: String; let types: [Kind]; let revision: Int
    var submission_limits: FeedbackSubmissionLimits? = nil
}
nonisolated struct FeedbackTicket: Codable, Identifiable, Sendable {
    let id: String; let number: String; let title: String; let kind: String; let status: String; let revision: Int
    let public_sequence: Int; let read_sequence: Int; let unread: Bool; let allowed_actions: [String]
    let created_at: String; let last_public_activity_at: String
    var statusTitle: String { ["submitted":"已提交","processing":"处理中","waiting_user":"待补充","resolved":"已答复","closed":"已结束"][status] ?? "状态待更新" }
}
nonisolated struct FeedbackAttachment: Codable, Identifiable, Sendable { let id: String; let mime: String; let size: Int }
nonisolated struct FeedbackMessage: Codable, Identifiable, Sendable {
    let id: String; let body: String; let author_type: String; let sequence: Int?; let created_at: String; let redacted: Bool
    let attachments: [FeedbackAttachment]
}
nonisolated struct FeedbackPhoto: Codable, Identifiable, Sendable {
    var id = UUID(); var bytes: Data; var attachmentID: String?; var uploadedAt: Date?
}
nonisolated struct FeedbackDraft: Codable, Sendable {
    var title = ""; var description = ""; var kind = "usage"; var contact = ""
    var articleID: String?; var relatedType = ""; var relatedID = ""; var previousID: String?
    var relatedTitle: String? = nil
    var photos: [FeedbackPhoto] = []; var requestID = UUID().uuidString
    var isEmpty: Bool { title.isEmpty && description.isEmpty && contact.isEmpty && photos.isEmpty }
}
nonisolated struct SupportRoute: Hashable { let id: String }
nonisolated struct HelpFailure: LocalizedError { let message: String; init(_ message: String) { self.message = message }; var errorDescription: String? { message } }

@MainActor enum AppVersionInformation {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知" }
    static var title: String { "\(version) (\(build))" }
    static var environment: [String: String] { ["app": Bundle.main.bundleIdentifier ?? "", "version": version, "build": build, "os": UIDevice.current.systemVersion, "device": UIDevice.current.model, "language": Locale.preferredLanguages.first ?? "zh-Hans"] }
    static var copiedText: String { "TravelDiary \(title)\niOS \(UIDevice.current.systemVersion)" }
}

nonisolated enum HelpBodyBlock: Identifiable, Equatable {
    case text(Int,String)
    case image(Int,String,String)
    var id: Int { switch self { case .text(let id,_), .image(let id,_,_):return id } }
    static func parse(_ text: String) -> [HelpBodyBlock] {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(support-image:([0-9a-fA-F-]{36})\)"#) else { return [.text(0,text)] }
        let ns = text as NSString;let matches = regex.matches(in:text,range:NSRange(location:0,length:ns.length))
        var blocks: [HelpBodyBlock] = [];var position = 0
        for match in matches {
            if match.range.location > position { blocks.append(.text(blocks.count,ns.substring(with:NSRange(location:position,length:match.range.location-position)))) }
            let identifier = ns.substring(with:match.range(at:2))
            if UUID(uuidString:identifier) != nil { blocks.append(.image(blocks.count,identifier,ns.substring(with:match.range(at:1)))) }
            position = match.range.location+match.range.length
        }
        if position < ns.length { blocks.append(.text(blocks.count,ns.substring(from:position))) }
        return blocks
    }
}

nonisolated func supportCharacterCount(_ text: String) -> Int { text.unicodeScalars.count }
