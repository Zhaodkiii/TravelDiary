import Foundation

extension String {
    /// 将文本转为无声调拉丁拼音（用于搜索匹配），与 Health 端 `toPinyin()` 行为一致。
    func toPinyinForSearch() -> String {
        let mutableString = NSMutableString(string: self) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return (mutableString as String).replacingOccurrences(of: " ", with: "")
    }

    /// 提取每个字符拼音首字母，用于症状/疾病等中文词条的首字母搜索。
    func toPinyinInitialsForSearch() -> String {
        var initials = ""
        for character in self {
            let piece = String(character)
            let pinyin = piece.toPinyinForSearch().lowercased()
            guard let first = pinyin.first, first.isLetter else { continue }
            initials.append(first)
        }
        return initials
    }
}
