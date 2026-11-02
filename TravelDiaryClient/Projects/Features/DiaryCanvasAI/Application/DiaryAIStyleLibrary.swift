import Foundation

struct DiaryAIStyle: Identifiable {
    let id: String
    let name: String
    let detail: String
    let rules: String
    var imageName: String { "AIStyle-" + (["editorial": "story", "headline": "lively", "notes": "vintage"][id] ?? id) }
}
enum DiaryAIStyleLibrary {
    static let styles: [DiaryAIStyle] = [
        .init(id: "editorial", name: "纸刊叙事", detail: "主标题 · 引题 · 照片旁注", rules: "安排主标题、引题、两处与照片对应的旁注和结语，约50至100字；标题大、正文轻，纸卡最多两种，保留照片主次与留白，不写无依据日期地名。"),
        .init(id: "headline", name: "大字主题", detail: "醒目短标题 · 手写补记", rules: "4至10字醒目短标题主动按语义断行，正文约标题字号一半；加引题、照片旁注和短结语，标题可用马善政，正文从可用字体中选清楚的手写体；少量强调色和手撕纸承托，不把每句话都做成大标题。"),
        .init(id: "notes", name: "旅行札记", detail: "记事段落 · 票根标签", rules: "主标题加2至3处照片记录、短结语，总量约60至110字；照片旁注写可见细节，标签短、段落轻。沿用默认blueTape或选已有牛皮纸、划线纸组合，同页最多两种纸卡，避免装饰压过照片。"),

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
