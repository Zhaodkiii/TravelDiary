import Foundation

let defaultRegions: [PhoneRegion] = [
    // 东亚
    .init(name: L10n.text("auth.region.cn"), dial: "+86", flag: "🇨🇳", countryCode: "CN"),
    .init(name: L10n.text("auth.region.hk"), dial: "+852", flag: "🇭🇰", countryCode: "HK"),
    .init(name: L10n.text("auth.region.tw"), dial: "+886", flag: "🇹🇼", countryCode: "TW"),
    .init(name: L10n.text("auth.region.jp"), dial: "+81", flag: "🇯🇵", countryCode: "JP"),
    .init(name: L10n.text("auth.region.kr"), dial: "+82", flag: "🇰🇷", countryCode: "KR"),
    .init(name: L10n.text("auth.region.mo"), dial: "+853", flag: "🇲🇴", countryCode: "MO"),

    // 东南亚
    .init(name: L10n.text("auth.region.sg"), dial: "+65", flag: "🇸🇬", countryCode: "SG"),
    .init(name: L10n.text("auth.region.my"), dial: "+60", flag: "🇲🇾", countryCode: "MY"),
    .init(name: L10n.text("auth.region.th"), dial: "+66", flag: "🇹🇭", countryCode: "TH"),
    .init(name: L10n.text("auth.region.id"), dial: "+62", flag: "🇮🇩", countryCode: "ID"),
    .init(name: L10n.text("auth.region.ph"), dial: "+63", flag: "🇵🇭", countryCode: "PH"),
    .init(name: L10n.text("auth.region.vn"), dial: "+84", flag: "🇻🇳", countryCode: "VN"),

    // 欧美
    .init(name: L10n.text("auth.region.us"), dial: "+1", flag: "🇺🇸", countryCode: "US"),
    .init(name: L10n.text("auth.region.ca"), dial: "+1", flag: "🇨🇦", countryCode: "CA"),
    .init(name: L10n.text("auth.region.uk"), dial: "+44", flag: "🇬🇧", countryCode: "GB"),
    .init(name: L10n.text("auth.region.de"), dial: "+49", flag: "🇩🇪", countryCode: "DE"),
    .init(name: L10n.text("auth.region.fr"), dial: "+33", flag: "🇫🇷", countryCode: "FR"),
    .init(name: L10n.text("auth.region.it"), dial: "+39", flag: "🇮🇹", countryCode: "IT"),
    .init(name: L10n.text("auth.region.es"), dial: "+34", flag: "🇪🇸", countryCode: "ES"),
    .init(name: L10n.text("auth.region.pt"), dial: "+351", flag: "🇵🇹", countryCode: "PT"),
    .init(name: L10n.text("auth.region.ru"), dial: "+7", flag: "🇷🇺", countryCode: "RU"),

    // 澳洲 / 新西兰
    .init(name: L10n.text("auth.region.au"), dial: "+61", flag: "🇦🇺", countryCode: "AU"),
    .init(name: L10n.text("auth.region.nz"), dial: "+64", flag: "🇳🇿", countryCode: "NZ"),

    // 中东 / 南亚
    .init(name: L10n.text("auth.region.in"), dial: "+91", flag: "🇮🇳", countryCode: "IN"),
    .init(name: L10n.text("auth.region.ae"), dial: "+971", flag: "🇦🇪", countryCode: "AE"),
    .init(name: L10n.text("auth.region.sa"), dial: "+966", flag: "🇸🇦", countryCode: "SA"),
    .init(name: L10n.text("auth.region.il"), dial: "+972", flag: "🇮🇱", countryCode: "IL"),

    // 其他常用
    .init(name: L10n.text("auth.region.ch"), dial: "+41", flag: "🇨🇭", countryCode: "CH"),
    .init(name: L10n.text("auth.region.se"), dial: "+46", flag: "🇸🇪", countryCode: "SE"),
    .init(name: L10n.text("auth.region.no"), dial: "+47", flag: "🇳🇴", countryCode: "NO"),
    .init(name: L10n.text("auth.region.dk"), dial: "+45", flag: "🇩🇰", countryCode: "DK"),
    .init(name: L10n.text("auth.region.ie"), dial: "+353", flag: "🇮🇪", countryCode: "IE")
]
