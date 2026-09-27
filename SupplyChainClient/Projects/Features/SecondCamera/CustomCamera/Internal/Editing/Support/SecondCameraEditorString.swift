//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

nonisolated(unsafe) private let bidiLeftToRightIsolate: Unicode.Scalar = "\u{2066}"
nonisolated(unsafe) private let bidiRightToLeftIsolate: Unicode.Scalar = "\u{2067}"
nonisolated(unsafe) private let bidiFirstStrongIsolate: Unicode.Scalar = "\u{2068}"
nonisolated(unsafe) private let bidiLeftToRightEmbedding: Unicode.Scalar = "\u{202A}"
nonisolated(unsafe) private let bidiRightToLeftEmbedding: Unicode.Scalar = "\u{202B}"
nonisolated(unsafe) private let bidiLeftToRightOverride: Unicode.Scalar = "\u{202D}"
nonisolated(unsafe) private let bidiRightToLeftOverride: Unicode.Scalar = "\u{202E}"
nonisolated(unsafe) private let bidiPopDirectionalFormatting: Unicode.Scalar = "\u{202C}"
nonisolated(unsafe) private let bidiPopDirectionalIsolate: Unicode.Scalar = "\u{2069}"
nonisolated(unsafe) private let bidiControlCharacterSet: CharacterSet = [
    bidiLeftToRightIsolate,
    bidiRightToLeftIsolate,
    bidiFirstStrongIsolate,
    bidiLeftToRightEmbedding,
    bidiRightToLeftEmbedding,
    bidiLeftToRightOverride,
    bidiRightToLeftOverride,
    bidiPopDirectionalFormatting,
    bidiPopDirectionalIsolate,
]

nonisolated(unsafe) private let nonPrintingCharacterSet = {
    var characterSet = CharacterSet.whitespacesAndNewlines
    characterSet.formUnion(CharacterSet.controlCharacters)
    characterSet.formUnion(bidiControlCharacterSet)
    // Left-to-right and Right-to-left marks.
    characterSet.insert(charactersIn: "\u{200E}\u{200F}")
    return characterSet
}()

// 0x202D and 0x202E are the unicode ordering letters
// and can be used to control the rendering of text.
// They could be used to construct misleading attachment
// filenames that appear to have a different file extension,
// for example.
nonisolated(unsafe) private let unsafeFilenameCharacterSet: CharacterSet = [bidiLeftToRightOverride, bidiRightToLeftOverride]

public struct SecondCameraEditorFilteredFilename {
    public let rawValue: String
    nonisolated public init(rawValue: String) {
        self.rawValue = rawValue.secondCameraEditor_filterFilename()
    }
}

extension String {

    nonisolated private func sanitized() -> String {
        // There was a sanitizer cache in the objc code. This should be linear in the length
        // of the string so unless we're calling this over and over and over again for the
        // same strings the cache doesn't seem very useful and the right place to fix things
        // is to not call this over and over again.
        StringSanitizer.sanitize(self)
    }

    /// - Warning: Only exposed for testing. Do not use.
    nonisolated func secondCameraEditor_filterUnsafeFilenameCharacters() -> String {
        StringSanitizer.sanitize(self) { c in
            c.unicodeScalars.contains { s in
                unsafeFilenameCharacterSet.contains(s)
            }
        }
    }

    nonisolated public func secondCameraEditor_stripped() -> String {
        if unicodeScalars.allSatisfy(nonPrintingCharacterSet.contains) {
            // If string has no printing characters, consider it empty.
            return ""
        } else {
            return trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A version of the string that only contains digits.
    ///
    /// Handles non-ASCII digits. If you only want ASCII digits, see `asciiDigitsOnly`.
    ///
    /// ```
    /// "1x2x3".digitsOnly
    /// // => "123"
    /// "١23".digitsOnly
    /// // => "١23"
    /// "1️⃣23".digitsOnly
    /// // => "123"
    /// ```
    nonisolated public func secondCameraEditor_digitsOnly() -> String {
        String(unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    nonisolated public func secondCameraEditor_hasAnyASCII() -> Bool {
        contains(where: \.isASCII)
    }

    nonisolated public func secondCameraEditor_isOnlyASCII() -> Bool {
        allSatisfy(\.isASCII)
    }

    /// Trims and filters a string for display
    nonisolated public func secondCameraEditor_filterStringForDisplay() -> String {
        secondCameraEditor_stripped().sanitized().secondCameraEditor_ensureBalancedBidiControlCharacters()
    }

    nonisolated public var secondCameraEditor_filterForDisplay: String { secondCameraEditor_filterStringForDisplay() }

    nonisolated public func secondCameraEditor_filterFilename() -> String {
        secondCameraEditor_stripped().sanitized().secondCameraEditor_filterUnsafeFilenameCharacters()
    }

    nonisolated public func secondCameraEditor_withoutBidiControlCharacters() -> String {
        // TODO: This may not be the right behavior. Investigate if it's supposed to remove all or just trim.
        trimmingCharacters(in: bidiControlCharacterSet)
    }

    nonisolated public func secondCameraEditor_ensureBalancedBidiControlCharacters() -> String {
        var isolateStartsCount = 0
        var isolatePopCount = 0
        var formattingStartsCount = 0
        var formattingPopCount = 0

        for c in unicodeScalars {
            switch c {
            case bidiLeftToRightIsolate, bidiRightToLeftIsolate, bidiFirstStrongIsolate:
                isolateStartsCount += 1
            case bidiPopDirectionalIsolate:
                isolatePopCount += 1
            case bidiLeftToRightEmbedding, bidiRightToLeftEmbedding, bidiLeftToRightOverride, bidiRightToLeftOverride:
                formattingStartsCount += 1
            case bidiPopDirectionalFormatting:
                formattingPopCount += 1
            default:
                break
            }
        }

        if isolateStartsCount == isolatePopCount, formattingStartsCount == formattingPopCount {
            return self
        }

        var balancedString = ""

        // If we have too many isolate pops, prepend FSI to balance
        while isolatePopCount > isolateStartsCount {
            balancedString += String(bidiFirstStrongIsolate)
            isolateStartsCount += 1
        }

        // If we have too many formatting pops, prepend LRE to balance
        while formattingPopCount > formattingStartsCount {
            balancedString += String(bidiLeftToRightEmbedding)
            formattingStartsCount += 1
        }

        balancedString += self

        // If we have too many formatting starts, append PDF to balance
        while formattingStartsCount > formattingPopCount {
            balancedString += String(bidiPopDirectionalFormatting)
            formattingPopCount += 1
        }

        // If we have too many isolate starts, append PDI to balance
        while isolateStartsCount > isolatePopCount {
            balancedString += String(bidiPopDirectionalIsolate)
            isolatePopCount += 1
        }

        return balancedString
    }

    public func secondCameraEditor_bidirectionallyBalancedAndIsolated() -> String {
        // We're already isolated, nothing to do here.
        if let first = unicodeScalars.first, let last = unicodeScalars.last, first == bidiFirstStrongIsolate, last == bidiPopDirectionalIsolate {
            return self
        }

        return String(bidiFirstStrongIsolate) + secondCameraEditor_ensureBalancedBidiControlCharacters() + String(bidiPopDirectionalIsolate)
    }
}

private enum SecondCameraEditorStringError: Error {
    case invalidCharacterShift
}

private let selectorOffset: UInt32 = 17

public extension String {
    func secondCameraEditor_caesar(shift: UInt32) throws -> String {
        let shiftedScalars: [UnicodeScalar] = try unicodeScalars.map { c in
            guard let shiftedScalar = UnicodeScalar((c.value + shift) % 127) else {
                throw SecondCameraEditorStringError.invalidCharacterShift
            }
            return shiftedScalar
        }
        return String(String.UnicodeScalarView(shiftedScalars))
    }

    var secondCameraEditor_encodedForSelector: String? {
        guard let shifted = try? self.secondCameraEditor_caesar(shift: selectorOffset) else { return nil }
        return Data(shifted.utf8).base64EncodedString()
    }

    var secondCameraEditor_decodedForSelector: String? {
        guard let data = Data(base64Encoded: self),
              let shifted = String(data: data, encoding: .utf8) else { return nil }
        return try? shifted.secondCameraEditor_caesar(shift: 127 - selectorOffset)
    }
}
