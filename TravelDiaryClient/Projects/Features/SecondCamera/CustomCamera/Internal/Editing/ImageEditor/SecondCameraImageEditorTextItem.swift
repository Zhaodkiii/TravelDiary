//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

final class SecondCameraImageEditorTextItem: SecondCameraImageEditorItem, SecondCameraImageEditorTransformable, @unchecked Sendable {

    let text: String

    let color: SecondCameraColorPickerBarColor

    let decorationStyle: SecondCameraMediaTextView.DecorationStyle

    let textStyle: SecondCameraMediaTextView.TextStyle

    let fontSize: CGFloat
    static let defaultFontSize: CGFloat = 36
    var font: UIFont {
        SecondCameraMediaTextView.font(for: textStyle, withPointSize: fontSize)
    }

    var textForegroundColor: UIColor {
        switch decorationStyle {
        case .none, .whiteBackground: return color.color

        case .coloredBackground:
            let backgroundColor = color.color
            return backgroundColor.isCloseToColor(.white) ? .black : .white

        case .outline, .underline: return .white
        }
    }

    var textBackgroundColor: UIColor? {
        switch decorationStyle {
        case .none, .underline, .outline: return nil

        case .whiteBackground:
            let textColor = color.color
            return textColor.isCloseToColor(.white) ? .black : .white

        case .coloredBackground: return color.color
        }
    }

    var textDecorationColor: UIColor? {
        switch decorationStyle {
        case .none, .whiteBackground, .coloredBackground: return nil
        case .outline, .underline: return color.color
        }
    }

    // In order to render the text at a consistent size
    // in very differently sized contexts (canvas in
    // portrait, landscape, in the crop tool, before and
    // after cropping, while rendering output),
    // we need to scale the font size to reflect the
    // view width.
    //
    // We use the image's rendering width as the reference value,
    // since we want to be consistent with regard to the image's
    // content.
    let fontReferenceImageWidth: CGFloat

    let unitCenter: SecondCameraImageEditorSample

    // Leave some margins against the edge of the image.
    static let kDefaultUnitWidth: CGFloat = 0.9

    // The max width of the text as a fraction of the image width.
    //
    // This provides continuity of text layout before/after cropping.
    //
    // NOTE: When you scale the text with with a pinch gesture, that
    // affects _scaling_, not the _unit width_, since we don't want
    // to change how the text wraps when scaling.
    let unitWidth: CGFloat

    // 0 = no rotation.
    // CGFloat.pi * 0.5 = rotation 90 degrees clockwise.
    let rotationRadians: CGFloat

    static let kMaxScaling: CGFloat = 4.0

    static let kMinScaling: CGFloat = 0.5

    let scaling: CGFloat

    init(
        text: String,
        color: SecondCameraColorPickerBarColor,
        fontSize: CGFloat,
        textStyle: SecondCameraMediaTextView.TextStyle = .regular,
        decorationStyle: SecondCameraMediaTextView.DecorationStyle = .none,
        fontReferenceImageWidth: CGFloat,
        unitCenter: SecondCameraImageEditorSample = SecondCameraImageEditorSample(x: 0.5, y: 0.5),
        unitWidth: CGFloat = SecondCameraImageEditorTextItem.kDefaultUnitWidth,
        rotationRadians: CGFloat = 0.0,
        scaling: CGFloat = 1.0,
    ) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.textStyle = textStyle
        self.decorationStyle = decorationStyle
        self.fontReferenceImageWidth = fontReferenceImageWidth
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling

        super.init(itemType: .text)
    }

    init(
        itemId: String,
        text: String,
        color: SecondCameraColorPickerBarColor,
        fontSize: CGFloat,
        textStyle: SecondCameraMediaTextView.TextStyle,
        decorationStyle: SecondCameraMediaTextView.DecorationStyle,
        fontReferenceImageWidth: CGFloat,
        unitCenter: SecondCameraImageEditorSample,
        unitWidth: CGFloat,
        rotationRadians: CGFloat,
        scaling: CGFloat,
    ) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
        self.textStyle = textStyle
        self.decorationStyle = decorationStyle
        self.fontReferenceImageWidth = fontReferenceImageWidth
        self.unitCenter = unitCenter
        self.unitWidth = unitWidth
        self.rotationRadians = rotationRadians
        self.scaling = scaling

        super.init(itemId: itemId, itemType: .text)
    }

    class func empty(
        withColor color: SecondCameraColorPickerBarColor,
        textStyle: SecondCameraMediaTextView.TextStyle,
        decorationStyle: SecondCameraMediaTextView.DecorationStyle,
        unitWidth: CGFloat,
        fontReferenceImageWidth: CGFloat,
        scaling: CGFloat,
        rotationRadians: CGFloat,
    ) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            text: "",
            color: color,
            fontSize: SecondCameraImageEditorTextItem.defaultFontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(withText newText: String, color newColor: SecondCameraColorPickerBarColor) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: newText,
            color: newColor,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(unitCenter: CGPoint) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(scaling: CGFloat, rotationRadians: CGFloat) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(unitWidth: CGFloat) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(fontSize: CGFloat) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(color: SecondCameraColorPickerBarColor) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    func copy(textStyle: SecondCameraMediaTextView.TextStyle, decorationStyle: SecondCameraMediaTextView.DecorationStyle) -> SecondCameraImageEditorTextItem {
        return SecondCameraImageEditorTextItem(
            itemId: itemId,
            text: text,
            color: color,
            fontSize: fontSize,
            textStyle: textStyle,
            decorationStyle: decorationStyle,
            fontReferenceImageWidth: fontReferenceImageWidth,
            unitCenter: unitCenter,
            unitWidth: unitWidth,
            rotationRadians: rotationRadians,
            scaling: scaling,
        )
    }

    override func outputScale() -> CGFloat {
        return scaling
    }

    static func ==(left: SecondCameraImageEditorTextItem, right: SecondCameraImageEditorTextItem) -> Bool {
        return left.text == right.text &&
            left.color == right.color &&
            left.textStyle == right.textStyle &&
            left.decorationStyle == right.decorationStyle &&
            left.fontSize.secondCameraEditor_fuzzyEquals(right.fontSize) &&
            left.fontReferenceImageWidth.secondCameraEditor_fuzzyEquals(right.fontReferenceImageWidth) &&
            left.unitCenter.secondCameraEditor_fuzzyEquals(right.unitCenter) &&
            left.unitWidth.secondCameraEditor_fuzzyEquals(right.unitWidth) &&
            left.rotationRadians.secondCameraEditor_fuzzyEquals(right.rotationRadians) &&
            left.scaling.secondCameraEditor_fuzzyEquals(right.scaling)
    }
}
