//
// Signal Camera - Text attachment models (simplified from Signal)
//

import UIKit

public struct SecondCameraEditorLinkPreviewDraft {
    public let url: URL
    public let title: String?
    public let isForwarded: Bool

    public init(url: URL, title: String? = nil, isForwarded: Bool = false) {
        self.url = url
        self.title = title
        self.isForwarded = isForwarded
    }
}

public struct SecondCameraEditorLinkPreview {
    public var urlString: String?
    public var title: String?

    public init(urlString: String? = nil, title: String? = nil) {
        self.urlString = urlString
        self.title = title
    }
}

public protocol SecondCameraEditorLinkPreviewState {}

public struct SecondCameraEditorLinkPreviewDraftState: SecondCameraEditorLinkPreviewState {
    public let linkPreviewDraft: SecondCameraEditorLinkPreviewDraft
    public init(linkPreviewDraft: SecondCameraEditorLinkPreviewDraft) {
        self.linkPreviewDraft = linkPreviewDraft
    }
}

public struct SecondCameraEditorCallLink {
    public init?(url: URL) { nil }
}

public struct SecondCameraUnsentTextAttachment {
    public let body: SecondCameraEditorStyleOnlyMessageBody?
    public let textStyle: SecondCameraTextAttachment.TextStyle
    public let textForegroundColor: UIColor
    public let textBackgroundColor: UIColor?
    public let background: SecondCameraTextAttachment.Background
    public let linkPreviewDraft: SecondCameraEditorLinkPreviewDraft?

    public var textContent: SecondCameraTextAttachment.TextContent {
        SecondCameraTextAttachment.textContent(body: body, textStyle: textStyle)
    }

    public init(
        body: SecondCameraEditorStyleOnlyMessageBody?,
        textStyle: SecondCameraTextAttachment.TextStyle,
        textForegroundColor: UIColor,
        textBackgroundColor: UIColor?,
        background: SecondCameraTextAttachment.Background,
        linkPreviewDraft: SecondCameraEditorLinkPreviewDraft?
    ) {
        self.body = body
        self.textStyle = textStyle
        self.textForegroundColor = textForegroundColor
        self.textBackgroundColor = textBackgroundColor
        self.background = background
        self.linkPreviewDraft = linkPreviewDraft
    }
}

public struct SecondCameraEditorStyleOnlyMessageBody {
    public let text: String
    public var isEmpty: Bool { text.isEmpty }

    public init(plaintext: String) {
        self.text = plaintext
    }
}

public struct SecondCameraTextAttachment {
    public enum TextStyle: Int, Codable, Equatable {
        case regular = 0
        case bold = 1
        case serif = 2
        case script = 3
        case condensed = 4
    }

    public enum TextContent {
        case empty
        case styled(body: String, style: TextStyle)
        case styledRanges(SecondCameraEditorStyleOnlyMessageBody)
    }

    public enum Background {
        case color(UIColor)
        case gradient(Gradient)

        public struct Gradient {
            public let colors: [UIColor]
            public let locations: [CGFloat]
            public let angle: UInt32

            public init(colors: [UIColor], locations: [CGFloat], angle: UInt32) {
                self.colors = colors
                self.locations = locations
                self.angle = angle
            }

            public init(colors: [UIColor]) {
                let locations: [CGFloat] = colors.enumerated().map { CGFloat($0.offset) / CGFloat(max(colors.count - 1, 1)) }
                self.init(colors: colors, locations: locations, angle: 180)
            }
        }
    }

    public static func textContent(body: SecondCameraEditorStyleOnlyMessageBody?, textStyle: TextStyle) -> TextContent {
        guard let body, !body.isEmpty else { return .empty }
        return .styled(body: body.text, style: textStyle)
    }
}

public enum SecondCameraEditorLinkPreviewHelper {
    public static func displayDomain(forUrl url: URL) -> String {
        url.host ?? url.absoluteString
    }
}
