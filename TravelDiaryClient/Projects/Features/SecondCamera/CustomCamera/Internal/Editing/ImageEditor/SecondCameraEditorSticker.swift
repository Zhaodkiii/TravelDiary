//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@preconcurrency import UIKit

final class SecondCameraEditorLayerContainerView: UIView {
    let contentLayer: CALayer
    init(contentLayer: CALayer) {
        self.contentLayer = contentLayer
        super.init(frame: .zero)
        layer.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.frame = CGRect(origin: self.frame.origin, size: self.frame.size)
    }
}

// MARK: - SecondCameraEditorSticker

public enum SecondCameraEditorSticker {
    case regular(SecondCameraStickerInfo)
    case story(StorySticker)

    // MARK: StorySticker

    public enum StorySticker {
        case clockDigital(DigitalClockStyle)
        case clockAnalog(AnalogClockStyle)

        @MainActor
        func previewView() -> UIView {
            switch self {
            case .clockDigital(let digitalClockStyle):
                let label = UILabel()
                label.attributedText = digitalClockStyle.attributedString(date: Date())
                label.adjustsFontSizeToFitWidth = true
                return label
            case .clockAnalog(let clockStyle):
                let clockLayer = clockStyle.drawClock(date: Date())
                return SecondCameraEditorLayerContainerView(contentLayer: clockLayer)
            }
        }

        /// A list of story sticker configurations to display in the sticker picker.
        ///
        /// Contains one of each story sticker with each one's default configuration.
        static var pickerStickers: [StorySticker] {
            [
                .clockDigital(.white),
                .clockAnalog(.arabic),
            ]
        }
    }
}

// MARK: DigitalClockStyle

extension SecondCameraEditorSticker.StorySticker {
        nonisolated public enum DigitalClockStyle: CaseIterable {
        case white
        case black
        case light
        case dark
        case amber

        nonisolated private var foregroundColor: UIColor {
            switch self {
            case .white, .light, .dark:
                return .secondCameraEditor_white
            case .black:
                return .secondCameraEditor_black
            case .amber:
                return .init(rgbHex: 0xFF7629)
            }
        }

        nonisolated var backgroundColor: UIColor? {
            switch self {
            case .white, .black:
                return nil
            case .light:
                return .secondCameraEditor_whiteAlpha40
            case .dark:
                return .secondCameraEditor_blackAlpha40
            case .amber:
                return .secondCameraEditor_blackAlpha60
            }
        }

        nonisolated func attributedString(
            date: Date,
            scaleFactor: CGFloat = 1.0,
        ) -> NSAttributedString {
            let is12HourTime = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") ?? true
            let timeFormat = is12HourTime ? "h:mm" : "HH:mm"
            let amPMFormat = is12HourTime ? " a" : nil

            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = timeFormat
            let timeString = timeFormatter.string(from: date)
            let timeFont = UIFont.digitalClockFont(withPointSize: 96 * scaleFactor)
            let timeAttributedString = NSAttributedString(
                string: timeString,
                attributes: [
                    .font: timeFont,
                    .foregroundColor: self.foregroundColor,
                ],
            )

            if let amPMFormat {
                let amPMFormatter = DateFormatter()
                amPMFormatter.dateFormat = amPMFormat
                let amPMString = amPMFormatter.string(from: date)
                let amPMFont = UIFont.regularFont(ofSize: 24 * scaleFactor)
                let amPMAttributedString = NSAttributedString(
                    string: amPMString,
                    attributes: [
                        .font: amPMFont,
                        .foregroundColor: self.foregroundColor,
                    ],
                )
                return timeAttributedString + amPMAttributedString
            }

            return timeAttributedString
        }

        nonisolated func nextStyle() -> DigitalClockStyle {
            switch self {
            case .white:
                return .black
            case .black:
                return .light
            case .light:
                return .dark
            case .dark:
                return .amber
            case .amber:
                return .white
            }
        }

        nonisolated func stickerWithNextStyle() -> SecondCameraEditorSticker {
            return .story(.clockDigital(self.nextStyle()))
        }
    }
}

// MARK: AnalogClockStyle

extension SecondCameraEditorSticker.StorySticker {
    nonisolated public enum AnalogClockStyle: CaseIterable {
        case arabic
        case baton
        case explorer
        case diver

        nonisolated var backgroundImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver.pdf")
            }
        }

        @MainActor
        func drawClock(date: Date) -> CALayer {
            return SecondCameraEditorAnalogClockLayer(style: self, date: date)
        }

        nonisolated var hourHandImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic-hour.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton-hour.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer-hour.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-hour.pdf")
            }
        }

        nonisolated var hourHandHeight: CGFloat {
            switch self {
            case .arabic:
                return 1 / 3
            case .baton:
                return 0.35
            case .explorer:
                return 149 / 600
            case .diver:
                return 139 / 600
            }
        }

        nonisolated var hourHandOffset: CGFloat {
            switch self {
            case .arabic:
                return 0.72
            case .baton:
                return 16 / 21
            case .explorer:
                return 1
            case .diver:
                return 141 / 139
            }
        }

        nonisolated var minuteHandImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic-minute.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton-minute.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer-minute.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-minute.pdf")
            }
        }

        nonisolated var minuteHandHeight: CGFloat {
            switch self {
            case .arabic:
                return 280 / 600
            case .baton:
                return 308 / 600
            case .explorer:
                return 229 / 600
            case .diver:
                return 268 / 600
            }
        }

        nonisolated var minuteHandOffset: CGFloat {
            switch self {
            case .arabic:
                return 4 / 5
            case .baton:
                return 129 / 154
            case .explorer:
                return 1
            case .diver:
                return 1
            }
        }

        nonisolated var centerImage: UIImage? {
            switch self {
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-center.pdf")
            case .arabic, .baton, .explorer:
                return nil
            }
        }

        nonisolated func nextStyle() -> AnalogClockStyle {
            switch self {
            case .arabic:
                return .baton
            case .baton:
                return .explorer
            case .explorer:
                return .diver
            case .diver:
                return .arabic
            }
        }

        nonisolated func stickerWithNextStyle() -> SecondCameraEditorSticker {
            return .story(.clockAnalog(self.nextStyle()))
        }
    }
}

// MARK: - SecondCameraEditorAnalogClockLayer

nonisolated final class SecondCameraEditorAnalogClockLayer: CALayer {
    typealias Style = SecondCameraEditorSticker.StorySticker.AnalogClockStyle

    nonisolated(unsafe) private let clockStyle: Style
    nonisolated(unsafe) private let date: Date
    nonisolated(unsafe) private let background: CALayer
    nonisolated(unsafe) private let hourHand: CALayer
    nonisolated(unsafe) private let minuteHand: CALayer
    nonisolated(unsafe) private let center: CALayer?

    nonisolated override var frame: CGRect {
        didSet {
            updateSublayerFrames()
        }
    }

    nonisolated init(style: Style, date: Date) {
        self.clockStyle = style
        self.date = date

        let backgroundView = UIImageView()
        backgroundView.image = style.backgroundImage
        background = backgroundView.layer

        let hourHandImageView = UIImageView()
        hourHandImageView.image = style.hourHandImage
        hourHandImageView.contentMode = .scaleAspectFit
        hourHand = hourHandImageView.layer

        let minuteHandImageView = UIImageView()
        minuteHandImageView.image = style.minuteHandImage
        minuteHandImageView.contentMode = .scaleAspectFit
        minuteHand = minuteHandImageView.layer

        center = style.centerImage.map { image in
            let view = UIImageView()
            view.image = image
            return view.layer
        }

        super.init()
        addSublayer(background)
        addSublayer(hourHand)
        addSublayer(minuteHand)
        if let center {
            addSublayer(center)
        }
    }

    nonisolated required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated private func updateSublayerFrames() {
        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat(dateComponents.minute ?? 0)
        let hours = CGFloat(dateComponents.hour ?? 0) + minutes / 60
//        let minutes = CGFloat.random(in: 0..<60)
//        let hours = CGFloat.random(in: 0..<12)

        background.frame.size = self.frame.size
        transfrom(
            clockHandLayer: hourHand,
            time: hours / 12,
            height: clockStyle.hourHandHeight,
            offset: clockStyle.hourHandOffset,
        )
        transfrom(
            clockHandLayer: minuteHand,
            time: minutes / 60,
            height: clockStyle.minuteHandHeight,
            offset: clockStyle.minuteHandOffset,
        )
        if let center {
            let size: CGFloat = 42 / 600 * self.frame.height
            center.frame = CGRect(
                origin: .init(
                    x: self.frame.width / 2 - size / 2,
                    y: self.frame.height / 2 - size / 2,
                ),
                size: .square(size),
            )
        }
    }

    nonisolated private func transfrom(
        clockHandLayer hand: CALayer,
        time: CGFloat,
        height: CGFloat,
        offset: CGFloat,
    ) {
        hand.setAffineTransform(.identity)
        hand.frame.size.height = self.frame.height * height
        hand.frame.origin = .init(
            x: self.frame.width / 2 - hand.frame.size.width / 2,
            y: self.frame.height / 2 - hand.frame.size.height / 2,
        )

        hand.anchorPoint = .init(x: 0.5, y: offset)
        hand.setAffineTransform(
            .init(translationX: 0, y: -hand.frame.height * (offset - 0.5))
                .rotated(by: time * 2 * .pi),
        )
    }

}
