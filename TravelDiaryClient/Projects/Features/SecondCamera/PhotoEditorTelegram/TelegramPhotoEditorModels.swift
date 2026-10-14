import SwiftUI
import UIKit

/// Photo-only adaptation of Telegram-iOS MediaEditorValues and Drawing entities.
/// Account, story, chat, audio and video state intentionally stays outside this component.
enum TelegramPhotoEditorTool: String, CaseIterable, Identifiable {
    case adjustments, curves, crop, blur, draw, text, sticker

    var id: Self { self }

    var title: String {
        return switch self {
        case .adjustments: "调整"
        case .curves: "曲线"
        case .crop: "裁剪"
        case .blur: "模糊"
        case .draw: "绘制"
        case .text: "文字"
        case .sticker: "贴纸"
        }
    }

    var systemImage: String {
        switch self {
        case .adjustments: "slider.horizontal.3"
        case .curves: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .crop: "crop.rotate"
        case .blur: "drop.halffull"
        case .draw: "pencil.tip"
        case .text: "textformat"
        case .sticker: "face.smiling"
        }
    }
}

struct TelegramPhotoAdjustments: Equatable {
    var enhance: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var warmth: Double = 0
    var fade: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    var vignette: Double = 0
    var grain: Double = 0
    var sharpen: Double = 0

    static let neutral = TelegramPhotoAdjustments()
}

enum TelegramPhotoCurveChannel: String, CaseIterable, Identifiable {
    case all, red, green, blue
    var id: Self { self }

    var title: String {
        switch self {
        case .all: "RGB"
        case .red: "红"
        case .green: "绿"
        case .blue: "蓝"
        }
    }

    var color: Color {
        switch self {
        case .all: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }
}

struct TelegramPhotoCurve: Equatable {
    var blacks: Double = 0
    var shadows: Double = 0.25
    var midtones: Double = 0.5
    var highlights: Double = 0.75
    var whites: Double = 1

    static let neutral = TelegramPhotoCurve()
    var values: [Double] { [blacks, shadows, midtones, highlights, whites] }
}

struct TelegramPhotoCurves: Equatable {
    var all = TelegramPhotoCurve.neutral
    var red = TelegramPhotoCurve.neutral
    var green = TelegramPhotoCurve.neutral
    var blue = TelegramPhotoCurve.neutral

    static let neutral = TelegramPhotoCurves()

    subscript(channel: TelegramPhotoCurveChannel) -> TelegramPhotoCurve {
        get {
            switch channel {
            case .all: all
            case .red: red
            case .green: green
            case .blue: blue
            }
        }
        set {
            switch channel {
            case .all: all = newValue
            case .red: red = newValue
            case .green: green = newValue
            case .blue: blue = newValue
            }
        }
    }
}

enum TelegramPhotoCropPreset: String, CaseIterable, Identifiable {
    case original, square, portrait, story, landscape, classic
    var id: Self { self }

    var title: String {
        switch self {
        case .original: "原始"
        case .square: "1:1"
        case .portrait: "4:5"
        case .story: "9:16"
        case .landscape: "16:9"
        case .classic: "3:2"
        }
    }

    func aspectRatio(for imageSize: CGSize, quarterTurns: Int) -> CGFloat {
        let turns = ((quarterTurns % 4) + 4) % 4
        let size = turns.isMultiple(of: 2) ? imageSize : CGSize(width: imageSize.height, height: imageSize.width)
        return switch self {
        case .original: size.width / max(size.height, 1)
        case .square: 1
        case .portrait: 4.0 / 5.0
        case .story: 9.0 / 16.0
        case .landscape: 16.0 / 9.0
        case .classic: 3.0 / 2.0
        }
    }
}

enum TelegramPhotoBlurMode: String, CaseIterable, Identifiable {
    case off, radial, linear, portrait
    var id: Self { self }

    var title: String {
        switch self {
        case .off: "关闭"
        case .radial: "径向"
        case .linear: "线性"
        case .portrait: "人像"
        }
    }
}

struct TelegramPhotoBlur: Equatable {
    var mode: TelegramPhotoBlurMode = .off
    var intensity: Double = 0.5
    var position = CGPoint(x: 0.5, y: 0.5)
    var size: Double = 0.24
    var falloff: Double = 0.12
    var rotation: Double = 0

    static let off = TelegramPhotoBlur()
}

enum TelegramPhotoDrawingTool: String, CaseIterable, Identifiable {
    case pen, marker, pencil, monoline, fountain, eraser
    var id: Self { self }

    var title: String {
        switch self {
        case .pen: "钢笔"
        case .marker: "马克笔"
        case .pencil: "铅笔"
        case .monoline: "单线"
        case .fountain: "墨水笔"
        case .eraser: "橡皮"
        }
    }
}

enum TelegramDrawingCanvasAction: Equatable {
    case none
    case undo(Int)
    case redo(Int)
}

struct TelegramPhotoEditorColor: Identifiable, Equatable {
    let id: String
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var color: Color { Color(red: red, green: green, blue: blue) }
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    static let palette: [TelegramPhotoEditorColor] = [
        .init(id: "white", red: 1, green: 1, blue: 1),
        .init(id: "black", red: 0.05, green: 0.05, blue: 0.06),
        .init(id: "red", red: 1, green: 0.22, blue: 0.25),
        .init(id: "orange", red: 1, green: 0.55, blue: 0.12),
        .init(id: "yellow", red: 1, green: 0.86, blue: 0.18),
        .init(id: "green", red: 0.22, green: 0.83, blue: 0.46),
        .init(id: "cyan", red: 0.2, green: 0.82, blue: 0.92),
        .init(id: "blue", red: 0.18, green: 0.58, blue: 1),
        .init(id: "purple", red: 0.67, green: 0.39, blue: 1),
        .init(id: "pink", red: 1, green: 0.32, blue: 0.68),
    ]
}

enum TelegramPhotoTextStyle: String, CaseIterable, Identifiable {
    case regular, filled, outline
    var id: Self { self }
    var title: String {
        switch self {
        case .regular: "普通"
        case .filled: "底色"
        case .outline: "描边"
        }
    }
}

enum TelegramPhotoTextFont: String, CaseIterable, Identifiable {
    case system, rounded, serif, monospaced
    var id: Self { self }
    var title: String {
        switch self {
        case .system: "默认"
        case .rounded: "圆体"
        case .serif: "衬线"
        case .monospaced: "等宽"
        }
    }

    func font(size: CGFloat) -> UIFont {
        switch self {
        case .system: .systemFont(ofSize: size, weight: .bold)
        case .rounded: UIFont(descriptor: UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.rounded) ?? UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor, size: size)
        case .serif: UIFont(descriptor: UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor.withDesign(.serif) ?? UIFont.systemFont(ofSize: size, weight: .bold).fontDescriptor, size: size)
        case .monospaced: .monospacedSystemFont(ofSize: size, weight: .bold)
        }
    }
}

struct TelegramPhotoTextOverlay: Identifiable, Equatable {
    let id: UUID
    var text: String
    var color: TelegramPhotoEditorColor
    var normalizedPosition: CGPoint
    var scale: CGFloat
    var rotation: Double
    var style: TelegramPhotoTextStyle
    var font: TelegramPhotoTextFont

    init(id: UUID = UUID(), text: String, color: TelegramPhotoEditorColor, normalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5), scale: CGFloat = 1, rotation: Double = 0, style: TelegramPhotoTextStyle = .regular, font: TelegramPhotoTextFont = .system) {
        self.id = id
        self.text = text
        self.color = color
        self.normalizedPosition = normalizedPosition
        self.scale = scale
        self.rotation = rotation
        self.style = style
        self.font = font
    }
}

struct TelegramPhotoStickerOverlay: Identifiable, Equatable {
    let id: UUID
    var content: String
    var normalizedPosition: CGPoint
    var scale: CGFloat
    var rotation: Double

    init(id: UUID = UUID(), content: String, normalizedPosition: CGPoint = CGPoint(x: 0.5, y: 0.5), scale: CGFloat = 1, rotation: Double = 0) {
        self.id = id
        self.content = content
        self.normalizedPosition = normalizedPosition
        self.scale = scale
        self.rotation = rotation
    }
}
