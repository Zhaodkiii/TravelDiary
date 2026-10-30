import SwiftUI

struct DiaryPhotoFramePicker: View {
    @ObservedObject var session: DiaryEditorSession
    let photoID: UUID
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView { DiaryPhotoFrameGrid(session: session, photoID: photoID, onSaved: { dismiss() }).padding() }
                .navigationTitle("相框")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(session.busy) } }
        }.presentationDetents([.large]).interactiveDismissDisabled(session.busy)
    }
}

struct DiaryPhotoFrameGrid: View {
    @ObservedObject var session: DiaryEditorSession
    var photoID: UUID?
    var query = ""
    var onSaved: (() -> Void)? = nil
    @State private var style = 0
    @State private var roughness = 0.4
    @State private var border = 0.06
    @State private var shadow = 0.2
    @State private var paperColor = 0
    @State private var seed = 1
    @State private var applying = false
    @State private var error: String?
    @State private var loaded = false
    private let colors: [Color] = [Color(white: 0.97), Color(red: 0.94, green: 0.91, blue: 0.84), Color(red: 0.84, green: 0.91, blue: 0.96), Color(red: 0.91, green: 0.85, blue: 0.87), Color(red: 0.84, green: 0.9, blue: 0.83)]
    private let colorNames = ["灰白", "米色", "浅蓝", "浅粉", "浅绿"]
    private var targetID: UUID? { photoID ?? session.selectedPhotos.first?.id }
    private var photo: DiaryEditorSession.ManagedPhoto? { session.managedPhotos.first { $0.id == targetID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            preview
            Picker("样式", selection: $style) {
                Text("无框").tag(-1)
                ForEach(0..<3) { Text(DiaryPhotoFrameCatalog.names[$0]).tag($0) }
            }.pickerStyle(.segmented)
            if style >= 0 {
                VStack(alignment: .leading, spacing: 16) {
                    if style == 0 {
                        control("手撕程度", value: $roughness, range: 0...1)
                        Button { seed = Int.random(in: 1...999999) } label: { Label("换一个形状", systemImage: "shuffle") }.font(.subheadline)
                    }
                    control("边宽", value: $border, range: 0.02...0.16)
                    control("阴影", value: $shadow, range: 0...1)
                    Text("纸张颜色").font(.subheadline.weight(.medium))
                    HStack(spacing: 18) {
                        ForEach(0..<colors.count, id: \.self) { index in
                            Button { paperColor = index } label: {
                                Circle().fill(colors[index]).frame(width: 36, height: 36)
                                    .overlay(Circle().strokeBorder(paperColor == index ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: paperColor == index ? 3 : 1))
                                    .overlay { if paperColor == index { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.primary) } }
                            }.buttonStyle(.plain).accessibilityLabel(colorNames[index]).accessibilityAddTraits(paperColor == index ? .isSelected : [])
                        }
                    }
                }.padding().background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            Button(action: apply) {
                HStack { Spacer(); if applying { ProgressView() }; Text(applying ? "正在保存…" : "保存相框"); Spacer() }.padding(.vertical, 6)
            }.buttonStyle(.borderedProminent).disabled(applying || session.busy || photo == nil || photo?.locked == true)
            Text("调整仅用于预览，保存后可在画布撤销。").font(.caption).foregroundStyle(.secondary)
        }.onAppear(perform: restore).disabled(applying)
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 4) {
            HStack { Text(title); Spacer(); Text("\(Int(value.wrappedValue * 100))%").monospacedDigit().foregroundStyle(.secondary) }.font(.subheadline)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
    private var preview: some View {
        GeometryReader { geometry in
            let item = generated
            let ratio = Double(photo?.layer.size.width ?? 4) / max(1, Double(photo?.layer.size.height ?? 3))
            let outerRatio = ratio * item.opening.height / item.opening.width
            let width = min(geometry.size.width - 32, 220 * outerRatio)
            let height = width / outerRatio
            ZStack {
                if let id = photo?.layer.assetID, let image = session.images[id] {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: width * item.opening.width, height: height * item.opening.height).clipped()
                        .position(x: width * item.opening.midX, y: height * item.opening.midY)
                }
                if style >= 0, let image = item.image { Image(uiImage: image).resizable().frame(width: width, height: height) }
            }.frame(width: width, height: height).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 244).background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("当前照片与相框预览")
    }
    private var generated: DiaryPhotoFrameCatalog.Item {
        let size = photo?.layer.size ?? CGSize(width: 4, height: 3)
        return DiaryPhotoFrameCatalog.generated(style: max(0, style), roughness: roughness, width: border,
            shade: shadow, color: paperColor, seed: seed, ratio: Double(size.width / max(1, size.height)))
    }
    private func restore() {
        guard !loaded, let photo else { return }; loaded = true
        guard let frame = session.document.objects[photo.ownerID]?.layers.last(where: { $0.frameTargetID == photo.id }) else { style = -1; return }
        let p = frame.photoFrameCatalogID?.split(separator: "|").map(String.init) ?? []
        guard p.count == 8, p[0] == "generated" else { return }
        style = min(2, max(0, Int(p[1]) ?? 0)); roughness = min(1, max(0, Double(p[2]) ?? 0.4))
        border = min(0.16, max(0.02, Double(p[3]) ?? 0.06)); shadow = min(1, max(0, Double(p[4]) ?? 0.2))
        paperColor = min(4, max(0, Int(p[5]) ?? 0)); seed = Int(p[6]) ?? 1
    }
    private func apply() {
        guard let id = targetID else { return }
        let item = style < 0 ? nil : generated
        applying = true; error = nil
        Task { @MainActor in
            let success = await session.applyPhotoFrame(item, to: id)
            applying = false
            if success { onSaved?() } else { error = session.errorMessage ?? "相框未能保存，请重试。" }
        }
    }
}
