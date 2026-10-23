import SwiftUI

/// 与作品使用同一版式和绘制器；示意插图仅供选样，永远不进入用户草稿。
struct DiaryAlbumDesignPicker: View {
    let model: DiaryAlbumComposer
    var contentHeightChanged: ((CGFloat) -> Void)? = nil
    @State private var position: Int? = 0
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DiaryPresetTemplateCarousel(count: DiaryAlbumTheme.allCases.count, position: $position, maximumCardWidth: 380, cardWidthFraction: 0.76) { index in
                    let theme = DiaryAlbumTheme.allCases[index]
                    Button { model.change { $0.applyTheme(theme) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            DiaryAlbumDesignSample(theme: theme, paletteID: theme == model.draft.theme ? model.draft.paletteID : nil)
                                .padding(10).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme == model.draft.theme ? DiaryLibraryStyle.accent : .clear, lineWidth: 2))
                            HStack { Text(theme.title).font(.headline); if theme == model.draft.theme { Image(systemName: "checkmark.circle.fill") } }
                            Text(theme.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                        }
                    }.buttonStyle(.plain).accessibilityAddTraits(theme == model.draft.theme ? .isSelected : [])
                }.frame(height: min(380, geometry.size.width * 0.76) * 0.75 + 80)
                DiaryAlbumPalettePicker(theme: model.draft.theme, selected: model.draft.paletteID) { id in model.change { $0.applyPalette(id) } }
                HStack {
                    Menu {
                        ForEach(DiaryPagePreset.allCases) { preset in
                            Button(preset.albumTitle) { model.change { $0.size = preset.rawValue } }
                        }
                    } label: { Label((DiaryPagePreset(rawValue: model.draft.size) ?? .b5).albumTitle, systemImage: "rectangle.portrait") }
                        .disabled(!model.draft.pages.isEmpty)
                    Spacer()
                    Text("照片决定页数").foregroundStyle(.secondary)
                }.font(.caption)
                if model.restored || !model.draft.photos.isEmpty {
                    Label("已保留 \(model.draft.photos.count) 张照片，可继续制作", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if height > 0 { contentHeightChanged?(height) }
                }
        }
        .onAppear { position = DiaryAlbumTheme.allCases.firstIndex(of: model.draft.theme) }
        }
    }
}
struct DiaryAlbumPalettePicker: View {
    let theme: DiaryAlbumTheme
    let selected: String?
    let select: (String) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Text("配色").font(.caption).foregroundStyle(.secondary)
                ForEach(theme.palettes) { palette in
                    Button { select(palette.id) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Color(uiColor: DiaryPageRenderer.color(palette.paper)))
                                .overlay(Circle().stroke(.gray.opacity(0.4)))
                                .overlay(alignment: .bottomTrailing) { Circle().fill(Color(uiColor: DiaryPageRenderer.color(palette.accent))).frame(width: 7, height: 7) }
                                .frame(width: 19, height: 19)
                            Text(palette.title)
                            if theme.palette(selected).id == palette.id { Image(systemName: "checkmark").font(.caption2) }
                        }.font(.caption).padding(.horizontal, 10).frame(minHeight: 44)
                            .background(theme.palette(selected).id == palette.id ? DiaryLibraryStyle.accent.opacity(0.1) : DiaryLibraryStyle.surface, in: Capsule())
                    }.buttonStyle(.plain).accessibilityAddTraits(theme.palette(selected).id == palette.id ? .isSelected : [])
                }
            }
        }.scrollIndicators(.hidden)
    }
}
struct DiaryAlbumDesignSample: View {
    let theme: DiaryAlbumTheme
    let paletteID: String?
    @State private var previews: [UIImage] = []
    var body: some View {
        HStack(spacing: 8) {
            if previews.count == 5 {
                Image(uiImage: previews[0]).resizable().scaledToFit().frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    spread(1, 2); spread(3, 4)
                }.frame(maxWidth: .infinity)
            } else { ProgressView().frame(maxWidth: .infinity) }
        }.aspectRatio(4.0 / 3, contentMode: .fit)
            .task(id: theme.rawValue + (paletteID ?? "0")) { previews = DiaryAlbumSampleRenderer.render(theme: theme, paletteID: paletteID) }
            .accessibilityLabel("\(theme.title)封面和跨页版式示意")
    }
    private func spread(_ a: Int, _ b: Int) -> some View {
        HStack(spacing: 1) {
            Image(uiImage: previews[a]).resizable().scaledToFit()
            Image(uiImage: previews[b]).resizable().scaledToFit()
        }.shadow(color: .black.opacity(0.10), radius: 2, y: 2)
    }
}

@MainActor enum DiaryAlbumSampleRenderer {
    private static var cache: [String: [UIImage]] = [:]
    static func render(theme: DiaryAlbumTheme, paletteID: String?) -> [UIImage] {
        let key = theme.rawValue + (paletteID ?? "0")
        if let value = cache[key] { return value }
        var draft = DiaryAlbumDraft(); draft.theme = theme; draft.paletteID = paletteID
        draft.title = theme == .zine ? "ON THE\nROAD" : theme == .editorial ? "沿途" : "山海之间"
        let samples = (0..<8).map { index in
            DiaryAlbumPhoto(filename: "", pixelSize: CGSize(width: index.isMultiple(of: 3) ? 600 : 900, height: 700), selectionOrder: index, fingerprint: "sample-\(index)")
        }
        draft.photos = samples
        var images: [UUID: UIImage] = [:], assets: [UUID: DiaryAsset] = [:]
        for (index, photo) in samples.enumerated() {
            images[photo.id] = landscape(index: index, size: photo.pixelSize)
            assets[photo.id] = DiaryAsset(id: photo.id, path: "sample", pixelSize: photo.pixelSize)
        }
        draft.pages = [DiaryAlbumPage(role: .cover, title: draft.title, theme: theme, paletteID: paletteID, placements: [DiaryAlbumPlacement(photoID: samples[0].id)])]
        for (index, count) in [1, 2, 3, 4].enumerated() {
            draft.pages.append(DiaryAlbumPage(theme: theme, layout: theme.layout(at: index, count: count), paletteID: paletteID,
                dateLabel: "OCTOBER · 2026", placements: samples.prefix(count).map { DiaryAlbumPlacement(photoID: $0.id) }))
        }
        let result = draft.pages.map { page in
            let document = DiaryAlbumDocumentBuilder.document(page: page, draft: draft, assets: assets)
            let format = UIGraphicsImageRendererFormat(); format.scale = 220 / draft.pageSize.width; format.opaque = true
            return UIGraphicsImageRenderer(size: draft.pageSize, format: format).image { ctx in
                DiaryPageRenderer.draw(document, images: images, in: ctx.cgContext, cacheObjects: false)
            }
        }
        cache[key] = result
        return result
    }
    /// 无网络依赖的山海插图，选样页面明确标为版式示意。
    private static func landscape(index: Int, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 0.6
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            let sky = [0xAEC3C6,0xD8BE9E,0xA8B7A0,0xC3C9D2][index % 4] as UInt32
            c.setFillColor(DiaryPageRenderer.color(DiaryAlbumPalette.color(sky)).cgColor); c.fill(CGRect(origin: .zero, size: size))
            c.setFillColor(UIColor(red: 0.98, green: 0.87, blue: 0.62, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: size.width * 0.65, y: size.height * 0.13, width: size.width * 0.17, height: size.width * 0.17))
            for band in 0..<3 {
                c.setFillColor(DiaryPageRenderer.color(DiaryAlbumPalette.color([0x7F9690,0x516E67,0x314C49][band])).cgColor)
                c.beginPath(); c.move(to: CGPoint(x: 0, y: size.height * (0.48 + Double(band) * 0.12)))
                c.addLine(to: CGPoint(x: size.width * 0.3, y: size.height * (0.25 + Double(band) * 0.2)))
                c.addLine(to: CGPoint(x: size.width * 0.7, y: size.height * (0.55 + Double(band) * 0.1)))
                c.addLine(to: CGPoint(x: size.width, y: size.height * 0.4))
                c.addLine(to: CGPoint(x: size.width, y: size.height)); c.addLine(to: CGPoint(x: 0, y: size.height)); c.closePath(); c.fillPath()
            }
        }
    }
}
