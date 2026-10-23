import Foundation
import CoreGraphics

/// 制作意图独立于预设包：结构、主题、版式可分别调整，最终仍生成普通可编辑文档。
nonisolated enum DiaryAlbumStructure: String, Codable, CaseIterable, Identifiable, Sendable {
    case travel, everyday, annual, memory
    var id: Self { self }
    var title: String { switch self { case .travel: "旅行记录"; case .everyday: "日常精选"; case .annual: "年度回忆"; case .memory: "纪念相册" } }
    var groupsByDate: Bool { self == .travel || self == .annual }
}
nonisolated struct DiaryAlbumPalette: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let paperHex: UInt32
    let inkHex: UInt32
    let accentHex: UInt32
    var paper: DiaryColor { Self.color(paperHex) }
    var ink: DiaryColor { Self.color(inkHex) }
    var accent: DiaryColor { Self.color(accentHex) }
    static func color(_ hex: UInt32) -> DiaryColor {
        DiaryColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
nonisolated enum DiaryAlbumTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal, magazine, film, scrapbook, zine, editorial
    var id: Self { self }
    var title: String { switch self { case .minimal: "极简留白"; case .magazine: "旅行杂志"; case .film: "胶片复古"; case .scrapbook: "手帐拼贴"; case .zine: "独立 Zine"; case .editorial: "影像刊物" } }
    var detail: String { switch self { case .minimal: "白底与留白，让照片成为主角"; case .magazine: "清晰标题、栏目与主次排版"; case .film: "暖白或炭黑纸面，细边框与照片编号"; case .scrapbook: "暖纸、纸卡与轻微错落"; case .zine: "大字号、强对比与不对称构图"; case .editorial: "大幅摄影与安静的细字图注" } }
    var palettes: [DiaryAlbumPalette] {
        let values: [(String, UInt32, UInt32, UInt32)]
        switch self {
        case .minimal: values = [("纯白",0xFFFFFF,0x30302E,0x656962),("暖白",0xF7F4EE,0x34312D,0x8A684D),("浅灰",0xECEDEB,0x303432,0x52655C)]
        case .magazine: values = [("编辑白",0xFAF8F3,0x252823,0x9C4F34),("砂米",0xE9E1D3,0x302A23,0x74533D),("雾灰",0xE7EBE9,0x23312C,0x355B4A)]
        case .film: values = [("暖白",0xF2EBDD,0x352C24,0x805A35),("炭黑",0x222220,0xF3EBDD,0xC4A16D),("旧纸",0xDED1BA,0x30271E,0x76502C)]
        case .scrapbook: values = [("暖纸",0xF3E7D3,0x49352A,0x9C5942),("奶油",0xFAF2E3,0x42362A,0x8E6646),("鼠尾草",0xE3E7DC,0x303D31,0x5C7159)]
        case .zine: values = [("黑白",0xF5F3EB,0x191919,0x191919),("酸黄",0xF5F3EB,0x191919,0xD9EF37),("钴蓝",0xF5F3EB,0x191919,0x244AE0)]
        case .editorial: values = [("柔白",0xF4F3EF,0x343432,0x6F746D),("石灰",0xE3E1DC,0x33332F,0x73715F),("墨黑",0x191B1D,0xF2F0E9,0xB4B8B5)]
        }
        return values.enumerated().map { index, value in DiaryAlbumPalette(id: String(index), title: value.0, paperHex: value.1, inkHex: value.2, accentHex: value.3) }
    }
    func palette(_ id: String?) -> DiaryAlbumPalette { palettes.first { $0.id == id } ?? palettes[0] }
    var paper: DiaryColor { palette(nil).paper }
    var ink: DiaryColor { palette(nil).ink }
    func layout(at index: Int, count: Int) -> DiaryAlbumLayout {
        if count == 1 { return (self == .zine || self == .editorial) && index % 3 == 1 ? .fullBleed : .adaptive }
        switch self {
        case .minimal, .film: return index.isMultiple(of: 2) ? .adaptive : .grid
        case .magazine, .scrapbook: return count >= 3 ? .hero : .adaptive
        case .zine: return count >= 3 ? .hero : .story
        case .editorial: return .adaptive
        }
    }
}
nonisolated enum DiaryAlbumDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case large, balanced, compact
    var id: Self { self }
    var title: String { switch self { case .large: "大图 · 1–2 张/页"; case .balanced: "均衡 · 2–4 张/页"; case .compact: "紧凑 · 4–6 张/页" } }
    var capacity: Int { switch self { case .large: 2; case .balanced: 4; case .compact: 6 } }
}
nonisolated enum DiaryAlbumLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case adaptive, grid, hero, story, fullBleed
    var id: Self { self }
    var title: String { switch self { case .adaptive: "适配横竖"; case .grid: "规则拼图"; case .hero: "主图突出"; case .story: "图文留白"; case .fullBleed: "单图满版" } }
}
nonisolated enum DiaryAlbumPageRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case cover, introduction, chapter, photos, ending, blank
    var id: Self { self }
    var title: String { switch self { case .cover: "封面"; case .introduction: "扉页／序言"; case .chapter: "章节页"; case .photos: "照片页"; case .ending: "结束页"; case .blank: "空白页" } }
}
nonisolated struct DiaryAlbumPhoto: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var filename: String
    var pixelSize: CGSize
    var date: Date?
    var selectionOrder: Int
    var fingerprint: String
}
nonisolated struct DiaryAlbumPlacement: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var photoID: UUID
    var zoom: Double = 1
    /// 相对于可裁切余量的归一化偏移，换尺寸时不产生越界。
    var offsetX: Double = 0
    var offsetY: Double = 0
}
nonisolated struct DiaryAlbumPage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var role: DiaryAlbumPageRole = .photos
    var title = ""
    var caption = ""
    var theme: DiaryAlbumTheme = .minimal
    var layout: DiaryAlbumLayout = .adaptive
    var paletteID: String? = nil
    var dateLabel: String? = nil
    var locked = false
    var spreadID: UUID? = nil
    var spreadSide: String? = nil
    var placements: [DiaryAlbumPlacement] = []
}
nonisolated struct DiaryAlbumDraft: Codable, Equatable, Sendable {
    var id = UUID()
    var title = "我的旅行相册"
    var structure: DiaryAlbumStructure = .travel
    var theme: DiaryAlbumTheme = .minimal
    var density: DiaryAlbumDensity = .balanced
    var paletteID: String? = nil
    var size = DiaryPagePreset.b5.rawValue
    var groupByDate = true
    var reuseCoverPhoto = true
    var photos: [DiaryAlbumPhoto] = []
    var pages: [DiaryAlbumPage] = []
    var pageSize: CGSize { (DiaryPagePreset(rawValue: size) ?? .b5).size }
    var unassigned: [DiaryAlbumPhoto] {
        let used = Set(pages.filter { $0.role != .cover }.flatMap { $0.placements.map(\.photoID) })
        return photos.filter { !used.contains($0.id) }
    }
    mutating func sortPhotos(byDate: Bool) {
        photos.sort {
            if byDate, $0.date != $1.date {
                if let a = $0.date, let b = $1.date { return a < b }
                return $0.date != nil
            }
            return $0.selectionOrder < $1.selectionOrder
        }
    }
    /// 只给未分配的照片分页；从不挤掉现有页面、文字或裁切。
    mutating func appendUnassigned(calendar: Calendar = .current) {
        let remaining = unassigned
        var groups: [(String, [DiaryAlbumPhoto])] = []
        for photo in remaining {
            let label: String
            if groupByDate, let date = photo.date {
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                label = structure == .annual ? "\(parts.year ?? 0) 年 \(parts.month ?? 0) 月" : "\(parts.year ?? 0).\(parts.month ?? 0).\(parts.day ?? 0)"
            } else { label = "" }
            if groups.last?.0 == label { groups[groups.count - 1].1.append(photo) }
            else { groups.append((label, [photo])) }
        }
        var additions: [DiaryAlbumPage] = []
        for (label, group) in groups {
            var offset = 0
            while offset < group.count {
                let rhythmIndex = pages.filter { $0.role == .photos }.count + additions.count
                let rhythm: [Int]
                switch density {
                case .large: rhythm = theme == .editorial ? [1, 1, 2] : [1, 2]
                case .balanced: rhythm = theme == .film ? [2, 4, 1] : theme == .editorial ? [1, 2, 1, 3] : [1, 2, 4, 3]
                case .compact: rhythm = [4, 6, 5]
                }
                var amount = min(rhythm[rhythmIndex % rhythm.count], group.count - offset)
                // 末尾两页尽量均衡，但保留有意设计的大图页。
                if group.count - offset - amount == 1 && amount > 2 { amount -= 1 }
                let batch = Array(group[offset..<offset + amount]); offset += amount
                additions.append(DiaryAlbumPage(theme: theme, layout: theme.layout(at: rhythmIndex, count: batch.count),
                    paletteID: paletteID, dateLabel: label.isEmpty ? nil : label,
                    placements: batch.map { DiaryAlbumPlacement(photoID: $0.id) }))
            }
        }
        let insertion = pages.firstIndex { $0.role == .ending } ?? pages.count
        pages.insert(contentsOf: additions, at: insertion)
    }
    mutating func generate() {
        guard pages.isEmpty else { appendUnassigned(); return }
        let cover = reuseCoverPhoto ? photos.first.map { [DiaryAlbumPlacement(photoID: $0.id)] } ?? [] : []
        pages = [DiaryAlbumPage(role: .cover, title: title, theme: theme, paletteID: paletteID, placements: cover)]
        appendUnassigned()

    }
    mutating func applyTheme(_ value: DiaryAlbumTheme) {
        theme = value
        paletteID = nil
        for index in pages.indices where !pages[index].locked {
            pages[index].theme = value; pages[index].paletteID = nil
            if pages[index].spreadID == nil { pages[index].layout = value.layout(at: index, count: pages[index].placements.count) }
        }
    }
    mutating func applyPalette(_ id: String) {
        paletteID = id
        for index in pages.indices where !pages[index].locked { pages[index].paletteID = id }
    }
    /// 改密度只重排未锁定、没有手写文字或裁切的普通照片页。
    /// 手动精修页、跨页和复制页保持不变；原照片顺序用于重新分页。
    mutating func repaginate(_ value: DiaryAlbumDensity) {
        density = value
        let counts = Dictionary(pages.filter { $0.role != .cover }.flatMap { $0.placements.map { ($0.photoID, 1) } }, uniquingKeysWith: +)
        pages.removeAll { page in
            page.role == .photos && !page.locked && page.spreadID == nil && page.title.isEmpty && page.caption.isEmpty
                && page.placements.allSatisfy { $0.zoom == 1 && $0.offsetX == 0 && $0.offsetY == 0 && counts[$0.photoID] == 1 }
        }
        appendUnassigned()
    }
    mutating func normalizeSpreads() {
        for pair in Set(pages.compactMap(\.spreadID)) {
            let indexes = pages.indices.filter { pages[$0].spreadID == pair }
            let valid = indexes.count == 2 && indexes[1] == indexes[0] + 1
                && pages[indexes[0]].spreadSide == "left" && pages[indexes[1]].spreadSide == "right"
                && indexes.allSatisfy { pages[$0].layout == .fullBleed && pages[$0].placements.count == 1 }
                && pages[indexes[0]].placements.first?.photoID == pages[indexes[1]].placements.first?.photoID
            if !valid {
                for index in indexes { pages[index].spreadID = nil; pages[index].spreadSide = nil }
            }
        }
    }
    mutating func rearrange() {
        // 保留每页的文字、页序和照片归属，只重新选择未锁定页面的版式。
        for index in pages.indices where !pages[index].locked {
            if pages[index].spreadID == nil { pages[index].layout = pages[index].theme.layout(at: index, count: pages[index].placements.count) }
        }
    }
    /// 一张照片横跨两页，按整幅跨页计算裁切，避免两页各自放大导致画面不连续。
    mutating func makeSpread(photoID: UUID) {
        guard let photo = photos.first(where: { $0.id == photoID }),
              !pages.contains(where: { $0.locked && $0.placements.contains(where: { $0.photoID == photoID }) }) else { return }
        for index in pages.indices where pages[index].role != .cover {
            pages[index].placements.removeAll { $0.photoID == photoID }
        }
        let scale = max(2 * pageSize.width / photo.pixelSize.width, pageSize.height / photo.pixelSize.height)
        let base = max(pageSize.width / photo.pixelSize.width, pageSize.height / photo.pixelSize.height)
        let offset = pageSize.width / max(1, photo.pixelSize.width * scale - pageSize.width)
        let pair = UUID()
        let spread = ["left", "right"].enumerated().map { index, side in
            DiaryAlbumPage(theme: theme, layout: .fullBleed, paletteID: paletteID, spreadID: pair, spreadSide: side,
                placements: [DiaryAlbumPlacement(photoID: photoID, zoom: Double(scale / base), offsetX: Double(offset) * (index == 0 ? 1 : -1))])
        }
        pages.insert(contentsOf: spread, at: pages.firstIndex(where: { $0.role == .ending }) ?? pages.count)
    }
    /// 拖动到照片上交换，拖到页面空白处移动；封面复用不参与正文移动。
    mutating func movePhoto(_ photoID: UUID, to pageID: UUID, replacing targetID: UUID? = nil, sourcePageID: UUID? = nil) {
        guard let destination = pages.firstIndex(where: { $0.id == pageID }), !pages[destination].locked,
              pages[destination].spreadID == nil,
              [.photos, .blank, .cover].contains(pages[destination].role),
              photos.contains(where: { $0.id == photoID }) else { return }
        let contentSourceID = pages.first(where: { $0.id == sourcePageID })?.role == .cover ? nil : sourcePageID
        let source = pages.indices.first { (contentSourceID == nil || pages[$0].id == contentSourceID) && pages[$0].role != .cover && pages[$0].placements.contains { $0.photoID == photoID } }
        if let source, (pages[source].locked || pages[source].spreadID != nil), pages[destination].role != .cover { return }
        if let targetID, let target = pages[destination].placements.firstIndex(where: { $0.photoID == targetID }) {
            if targetID == photoID { return }
            if source != destination && pages[destination].placements.contains(where: { $0.photoID == photoID }) { return }
            if let source, let slot = pages[source].placements.firstIndex(where: { $0.photoID == photoID }), pages[destination].role != .cover {
                let a = pages[source].placements[slot]
                pages[source].placements[slot] = pages[destination].placements[target]
                pages[destination].placements[target] = a
            } else { pages[destination].placements[target] = DiaryAlbumPlacement(photoID: photoID) }
        } else {
            guard pages[destination].placements.count < (pages[destination].role == .cover ? 1 : 6),
                  !pages[destination].placements.contains(where: { $0.photoID == photoID }) else { return }
            if let source, pages[destination].role != .cover { pages[source].placements.removeAll { $0.photoID == photoID } }
            pages[destination].placements.append(DiaryAlbumPlacement(photoID: photoID))
            if pages[destination].layout == .fullBleed && pages[destination].placements.count > 1 { pages[destination].layout = .adaptive }
        }
    }
}

/// 预览、裁切和最终文档共用归一化版式，不维护两套相似但不同的坐标。
nonisolated enum DiaryAlbumGeometry {
    static func frames(page: DiaryAlbumPage, photos: [DiaryAlbumPhoto]) -> [CGRect] {
        let n = page.placements.count
        guard n > 0 else { return [] }
        if n == 1 && page.layout == .fullBleed && page.role == .photos { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        if page.role == .cover {
            switch page.theme {
            case .zine: return [CGRect(x: 0.04, y: 0.28, width: 0.96, height: 0.67)]
            case .editorial: return [CGRect(x: 0.14, y: 0.28, width: 0.72, height: 0.52)]
            case .magazine: return [CGRect(x: 0.06, y: 0.24, width: 0.88, height: 0.68)]
            default: return [CGRect(x: 0.08, y: 0.25, width: 0.84, height: 0.59)]
            }
        }
        let top: CGFloat = page.title.isEmpty ? 0.06 : 0.16
        let bottom: CGFloat = page.layout == .story || !page.caption.isEmpty ? 0.25 : 0.07
        let margin: CGFloat = page.theme == .editorial ? 0.11 : page.theme == .zine ? 0.04 : 0.07
        let area = CGRect(x: margin, y: top, width: 1 - 2 * margin, height: 1 - top - bottom)
        if n == 1 { return [page.theme == .editorial ? area.insetBy(dx: 0, dy: 0.08) : area] }
        if n == 2 && page.theme == .zine && page.layout != .grid {
            return [CGRect(x: 0.04, y: top, width: 0.61, height: area.height * 0.72),
                    CGRect(x: 0.56, y: top + area.height * 0.47, width: 0.40, height: area.height * 0.53)]
        }
        let gap: CGFloat = 0.025
        if page.layout == .hero && n >= 3 {
            let hero = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height * 0.53)
            let rest = CGRect(x: area.minX, y: hero.maxY + gap, width: area.width, height: area.maxY - hero.maxY - gap)
            return [hero] + grid(count: n - 1, columns: n <= 4 ? n - 1 : 3, area: rest, gap: gap)
        }
        let allLandscape = page.placements.allSatisfy { placement in
            guard let photo = photos.first(where: { $0.id == placement.photoID }) else { return false }
            return photo.pixelSize.width > photo.pixelSize.height
        }
        let columns = n == 2 && page.layout == .adaptive && allLandscape ? 1 : (page.theme == .film && n >= 5 ? 3 : 2)
        return grid(count: n, columns: columns, area: area, gap: gap)
    }
    private static func grid(count: Int, columns: Int, area: CGRect, gap: CGFloat) -> [CGRect] {
        let rows = Int(ceil(Double(count) / Double(columns)))
        let h = (area.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
        return (0..<count).map { i in
            let row = i / columns, col = i % columns
            let inRow = min(columns, count - row * columns)
            let w = (area.width - CGFloat(inRow - 1) * gap) / CGFloat(inRow)
            return CGRect(x: area.minX + CGFloat(col) * (w + gap), y: area.minY + CGFloat(row) * (h + gap), width: w, height: h)
        }
    }
}
