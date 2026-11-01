import Foundation

struct DiaryAIStyle: Identifiable {
    let id: String
    let name: String
    let detail: String
    let rules: String
    var imageName: String { "AIStyle-" + id }
}
enum DiaryAIStyleLibrary {
    static let styles: [DiaryAIStyle] = [
        .init(id: "mountain", name: "山野手记", detail: "深绿手写 · 大小错落", rules: "主照片与小照片形成大小对比，深绿标题，手写短句，装饰依附照片边缘，不规则但有呼吸感。"),
        .init(id: "vintage", name: "复古票根", detail: "暖纸色 · 旅行记事", rules: "暖棕文字，标签式旁注，轻微叠贴和倾斜，保留旅行记事感。"),
        .init(id: "minimal", name: "清爽留白", detail: "少装饰 · 明确主次", rules: "留出大面积空白，明确一张主照片，文字简洁，少量装饰，不平均分配所有照片。"),
        .init(id: "gentle", name: "温柔日常", detail: "柔和配色 · 细腻短句", rules: "柔和暖色、圆润手写，轻量纸片和少量旋转，温暖克制。"),
        .init(id: "lively", name: "活力出游", detail: "轻快倾斜 · 尺寸对比", rules: "明显但不夸张的大小对比，轻微倾斜，明快文字，保留留白和阅读顺序。"),
        .init(id: "story", name: "照片故事", detail: "主照片 · 纪实旁注", rules: "主照片突出人物，局部旁注连接照片，少装饰，叙事文字不虚构日期人物和经历。")
    ]
    static func brief(_ name: String) -> String {
        if name == "保持当前风格" { return "延续现有字体、配色、装饰与背景；不强行改变主题。" }
        if name == "自动匹配" { return styles.map { "\($0.name)：\($0.rules)" }.joined(separator: "\n") + "\n选择适合当前图片的风格，在总结中说明。" }
        return styles.first { $0.name == name }?.rules ?? "延续现有风格"
    }
}
