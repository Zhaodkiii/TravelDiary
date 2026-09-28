//
// Signal Camera - SecondCameraEditorTextHelper (from Signal)
//

import Foundation

public enum SecondCameraEditorTextHelper {
    public static func shouldChangeCharactersInRange(
        with existingString: String?,
        editingRange: NSRange,
        replacementString: String,
        maxByteCount: Int? = nil,
        maxUnicodeScalarCount: Int? = nil,
        maxGlyphCount: Int? = nil,
    ) -> (shouldChange: Bool, changedString: String?) {
        func hasValidLength(_ string: String) -> Bool {
            if let maxByteCount, string.utf8.count > maxByteCount { return false }
            if let maxUnicodeScalarCount, string.unicodeScalars.count > maxUnicodeScalarCount { return false }
            if let maxGlyphCount, string.secondCameraEditor_glyphCount > maxGlyphCount { return false }
            return true
        }

        let existingString = existingString ?? ""
        let notFilteredForDisplay = (existingString as NSString).replacingCharacters(in: editingRange, with: replacementString)
        let filteredForDisplay = notFilteredForDisplay.secondCameraEditor_filterStringForDisplay()

        if hasValidLength(notFilteredForDisplay), hasValidLength(filteredForDisplay) {
            return (true, nil)
        }

        if replacementString.count < 2 {
            return (false, nil)
        }

        var acceptableSubstring = ""
        for char in replacementString {
            var maybeAcceptableSubstring = acceptableSubstring
            maybeAcceptableSubstring.append(char)
            let newFilteredString = (existingString as NSString)
                .replacingCharacters(in: editingRange, with: maybeAcceptableSubstring)
                .secondCameraEditor_filterStringForDisplay()
            if hasValidLength(newFilteredString) {
                acceptableSubstring = maybeAcceptableSubstring
            } else {
                break
            }
        }

        let changedString = (existingString as NSString).replacingCharacters(in: editingRange, with: acceptableSubstring)
        return (false, changedString)
    }
}

public extension String {
    var secondCameraEditor_glyphCount: Int {
        (self as NSString).length
    }
}
