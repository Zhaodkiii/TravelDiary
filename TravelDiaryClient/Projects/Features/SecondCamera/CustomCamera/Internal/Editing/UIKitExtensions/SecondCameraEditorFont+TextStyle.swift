import UIKit

extension UIFont {

    // MARK: - Dynamic Type

    nonisolated class var dynamicTypeTitle1: UIFont { UIFont.preferredFont(forTextStyle: .title1, compatibleWith: .current) }
    nonisolated class var dynamicTypeTitle2: UIFont { UIFont.preferredFont(forTextStyle: .title2, compatibleWith: .current) }
    nonisolated class var dynamicTypeTitle3: UIFont { UIFont.preferredFont(forTextStyle: .title3, compatibleWith: .current) }
    nonisolated class var dynamicTypeHeadline: UIFont { UIFont.preferredFont(forTextStyle: .headline, compatibleWith: .current) }
    nonisolated class var dynamicTypeBody: UIFont { UIFont.preferredFont(forTextStyle: .body, compatibleWith: .current) }
    nonisolated class var dynamicTypeCallout: UIFont { UIFont.preferredFont(forTextStyle: .callout, compatibleWith: .current) }
    nonisolated class var dynamicTypeSubheadline: UIFont { UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: .current) }
    nonisolated class var dynamicTypeFootnote: UIFont { UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: .current) }
    nonisolated class var dynamicTypeCaption1: UIFont { UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: .current) }
    nonisolated class var dynamicTypeCaption2: UIFont { UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: .current) }

    // MARK: - Dynamic Type Clamped

    nonisolated(unsafe) private static var _scMaxPointSizeMap: [UIFont.TextStyle: CGFloat] = [
        .title1: 34, .title2: 28, .title3: 26, .headline: 23, .body: 23,
        .callout: 22, .subheadline: 21, .footnote: 19, .caption1: 18, .caption2: 17, .largeTitle: 40,
    ]

    nonisolated private class func preferredFontClamped(forTextStyle textStyle: UIFont.TextStyle) -> UIFont {
        let defaultTraitCollection = UITraitCollection(preferredContentSizeCategory: .large)
        let unscaledFont = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: defaultTraitCollection)
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        guard let maxPointSize = _scMaxPointSizeMap[textStyle] else {
            return metrics.scaledFont(for: unscaledFont)
        }
        return metrics.scaledFont(for: unscaledFont, maximumPointSize: maxPointSize, compatibleWith: .current)
    }

    nonisolated class var dynamicTypeLargeTitle1Clamped: UIFont { preferredFontClamped(forTextStyle: .largeTitle) }
    nonisolated class var dynamicTypeTitle1Clamped: UIFont { preferredFontClamped(forTextStyle: .title1) }
    nonisolated class var dynamicTypeTitle2Clamped: UIFont { preferredFontClamped(forTextStyle: .title2) }
    nonisolated class var dynamicTypeTitle3Clamped: UIFont { preferredFontClamped(forTextStyle: .title3) }
    nonisolated class var dynamicTypeHeadlineClamped: UIFont { preferredFontClamped(forTextStyle: .headline) }
    nonisolated class var dynamicTypeBodyClamped: UIFont { preferredFontClamped(forTextStyle: .body) }
    nonisolated class var dynamicTypeCalloutClamped: UIFont { preferredFontClamped(forTextStyle: .callout) }
    nonisolated class var dynamicTypeSubheadlineClamped: UIFont { preferredFontClamped(forTextStyle: .subheadline) }
    nonisolated class var dynamicTypeFootnoteClamped: UIFont { preferredFontClamped(forTextStyle: .footnote) }
    nonisolated class var dynamicTypeCaption1Clamped: UIFont { preferredFontClamped(forTextStyle: .caption1) }
    nonisolated class var dynamicTypeCaption2Clamped: UIFont { preferredFontClamped(forTextStyle: .caption2) }

    // MARK: - Named font helpers

    nonisolated class func regularFont(ofSize size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .regular)
    }

    nonisolated class func semiboldFont(ofSize size: CGFloat) -> UIFont {
        .systemFont(ofSize: size, weight: .semibold)
    }

    nonisolated class func monospacedDigitFont(ofSize size: CGFloat) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// 7-segment digital clock font (Hatsuishi-UPM800). Supports numbers, `.`, and `:`.
    nonisolated class func digitalClockFont(withPointSize pointSize: CGFloat) -> UIFont {
        let fontDescriptor = UIFontDescriptor(fontAttributes: [.name: "Hatsuishi-UPM800"])
        return UIFont(descriptor: fontDescriptor, size: pointSize)
    }

    // MARK: - Trait modifiers

    nonisolated func italic() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitItalic) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }

    nonisolated func medium() -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.medium]
        let descriptor = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: descriptor, size: 0)
    }

    nonisolated func semibold() -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        let descriptor = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: descriptor, size: 0)
    }

    nonisolated func bold() -> UIFont {
        let traits = [UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]
        let descriptor = fontDescriptor.addingAttributes([.traits: traits])
        return UIFont(descriptor: descriptor, size: 0)
    }

    nonisolated func monospaced() -> UIFont {
        .monospacedDigitFont(ofSize: pointSize)
    }
}

extension UIFont {
    nonisolated public class func secondCameraEditorFont(
        for textStyle: SecondCameraTextAttachment.TextStyle,
        withPointSize pointSize: CGFloat
    ) -> UIFont {
        let primaryFontName: String
        var fontNamesOrDescriptors: [Any]

        switch textStyle {
        case .regular:
            primaryFontName = "Inter-Regular_Medium"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Regular",
                "PingFangHK-Regular",
                "PingFangTC-Regular",
                "PingFangSC-Regular",
                "HiraginoSans-W3",
                UIFont.systemFont(ofSize: 10, weight: .regular).fontDescriptor,
            ]
        case .bold:
            primaryFontName = "Inter-Regular_Black"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Semibold",
                "PingFangHK-Semibold",
                "PingFangTC-Semibold",
                "PingFangSC-Semibold",
                "HiraginoSans-W7",
                UIFont.systemFont(ofSize: 10, weight: .bold).fontDescriptor,
            ]
        case .serif:
            primaryFontName = "EBGaramond-Regular"
            fontNamesOrDescriptors = [
                "DevanagariSangamMN",
                "PingFangHK-Ultralight",
                "PingFangTC-Ultralight",
                "PingFangSC-Ultralight",
                "GeezaPro",
                "HiraMinProN-W3",
            ]
            if let fontDescriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits(.classModernSerifs)
            {
                fontNamesOrDescriptors.append(fontDescriptor)
            }
        case .script:
            primaryFontName = "Parisienne-Regular"
            fontNamesOrDescriptors = [
                "AmericanTypewriter-Semibold",
                "DevanagariSangamMN-Bold",
                "PingFangHK-Thin",
                "PingFangTC-Thin",
                "PingFangSC-Thin",
                "GeezaPro-Bold",
                "HiraMinProN-W6",
            ]
            if let fontDescriptor = UIFontDescriptor
                .preferredFontDescriptor(withTextStyle: .body)
                .withSymbolicTraits(.classModernSerifs)?
                .withSymbolicTraits(.traitBold)
            {
                fontNamesOrDescriptors.append(fontDescriptor)
            }
        case .condensed:
            primaryFontName = "BarlowCondensed-Medium"
            fontNamesOrDescriptors = [
                "KohinoorDevanagari-Light",
                "PingFangHK-Light",
                "PingFangTC-Light",
                "PingFangSC-Light",
                "HiraMaruProN-W4",
                UIFont.systemFont(ofSize: 10, weight: .black).fontDescriptor,
            ]
        }

        let cascadeList: [UIFontDescriptor] = fontNamesOrDescriptors.compactMap { fontNameOrDescriptor in
            if let fontDescriptor = fontNameOrDescriptor as? UIFontDescriptor {
                return fontDescriptor
            }
            if let fontName = fontNameOrDescriptor as? String {
                return UIFontDescriptor(fontAttributes: [.name: fontName])
            }
            secondCameraEditorFailDebug("Not a String or UIFontDescriptor.")
            return nil
        }

        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: primaryFontName,
            .cascadeList: cascadeList,
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
