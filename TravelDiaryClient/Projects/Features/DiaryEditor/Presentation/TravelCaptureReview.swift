import SwiftUI
import UIKit

/// 采集素材的准备页；完成后才提交到通用图层编辑器。
struct TravelCaptureReview: View {
    let original: UIImage
    let submitting: Bool
    let submissionError: String?
    let onNext: (UIImage, String, DiaryPhotoFrameCatalog.Item?) -> Void
    let onClose: () -> Void
    @State private var kind = "照片"
    @State private var backgroundZoom: CGFloat = 1
    @State private var backgroundOffset = CGSize.zero
    @State private var frameStyle = 1
    @State private var border = 0.06
    @State private var subjects: [StickerSubject] = []
    @State private var selectedSubject: Int?
    @State private var whiteBorder = true
    @State private var extracting = false
    @State private var error: String?
    @State private var extraction: Task<Void, Never>?
    private var frame: DiaryPhotoFrameCatalog.Item? {
        guard frameStyle >= 0 else { return nil }
        return DiaryPhotoFrameCatalog.generated(style: frameStyle, width: border,
            ratio: Double(original.size.width / max(1, original.size.height)))
    }
    private var sticker: UIImage? {
        guard let subject = subjects.first(where: { $0.id == selectedSubject }) else { return nil }
        return StickerImageProcessor.render(subject.image, style: whiteBorder ? "白边" : "原样", color: .white, thickness: 3)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("用途", selection: $kind) {
                        Text("背景").tag("背景"); Text("照片").tag("照片"); Text("贴纸").tag("贴纸")
                    }.pickerStyle(.segmented)
                    if kind == "背景" {
                        TravelBackgroundCropView(image: original, zoom: $backgroundZoom, offset: $backgroundOffset)
                        Text("完整跨页 · 4370 × 3130").font(.headline)
                        Text("拖动调整位置，双指缩放取景").font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $backgroundZoom, in: 1...8).accessibilityLabel("背景缩放")
                        HStack {
                            Button("左移") { backgroundOffset.width -= 0.02 }
                            Button("右移") { backgroundOffset.width += 0.02 }
                            Button("上移") { backgroundOffset.height -= 0.02 }
                            Button("下移") { backgroundOffset.height += 0.02 }
                        }.buttonStyle(.bordered)
                        Button("重置取景") { backgroundZoom = 1; backgroundOffset = .zero }
                    } else if kind == "照片" {
                        framePreview
                        Picker("相框", selection: $frameStyle) {
                            Text("无框").tag(-1)
                            ForEach(0..<3) { Text(DiaryPhotoFrameCatalog.names[$0]).tag($0) }
                        }.pickerStyle(.segmented)
                        if frameStyle >= 0 { Text("边框宽度"); Slider(value: $border, in: 0.02...0.16) }
                        Text("相框使用现有手帐相框，进入编辑器后仍可更换。").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ZStack {
                            Color(uiColor: .systemGray4)
                            if let sticker { Image(uiImage: sticker).resizable().scaledToFit().padding(20) }
                            else { Image(uiImage: original).resizable().scaledToFit().opacity(0.45) }
                            if extracting { ProgressView("正在提取主体…").padding().background(.regularMaterial, in: Capsule()) }
                        }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                        if !subjects.isEmpty {
                            ScrollView(.horizontal) {
                                HStack {
                                    ForEach(subjects) { subject in
                                        Button { selectedSubject = subject.id } label: {
                                            Image(uiImage: subject.image).resizable().scaledToFit().frame(width: 70, height: 70).padding(6)
                                                .background(selectedSubject == subject.id ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                        }.accessibilityLabel("主体 \(subject.id)")
                                    }
                                }
                            }
                            Toggle("白色描边", isOn: $whiteBorder)
                        } else if !extracting {
                            Button("重新提取主体") { extract() }
                            Button("改为照片") { kind = "照片" }
                        }
                        Text("选择要保留的主体，预览透明贴纸后进入手帐。").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = error ?? submissionError { Text(error).foregroundStyle(.red).font(.callout) }
                    Button {
                        if kind == "背景" { onNext(TravelBackgroundCrop.render(original, zoom: backgroundZoom, offset: backgroundOffset), kind, nil) }
                        else if kind == "照片" { onNext(original, kind, frame) }
                        else if let sticker { onNext(sticker, "透明贴纸", nil) }
                    } label: {
                        HStack { if submitting { ProgressView() }; Text(submitting ? "正在加入…" : "下一步").frame(maxWidth: .infinity) }.padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent)
                        .disabled(submitting || extracting || (kind == "贴纸" && selectedSubject == nil))
                }.padding(20)
            }
            .navigationTitle("照片预览").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onClose).disabled(submitting) } }
            .disabled(submitting)
            .onChange(of: kind) { _, value in
                error = nil
                if value == "贴纸", subjects.isEmpty { extract() }
            }
            .onDisappear { extraction?.cancel() }
        }.interactiveDismissDisabled(submitting)
    }
    private var framePreview: some View {
        GeometryReader { geometry in
            let opening = frame?.opening ?? CGRect(x: 0, y: 0, width: 1, height: 1)
            let ratio = original.size.width / max(1, original.size.height) * opening.height / opening.width
            let width = min(geometry.size.width, 300 * ratio)
            let height = width / ratio
            ZStack {
                Image(uiImage: original).resizable().scaledToFill()
                    .frame(width: width * opening.width, height: height * opening.height).clipped()
                    .position(x: width * opening.midX, y: height * opening.midY)
                if let image = frame?.image { Image(uiImage: image).resizable().frame(width: width, height: height) }
            }.frame(width: width, height: height).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(height: 320).background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 16))
    }
    private func extract() {
        guard !extracting else { return }
        extracting = true; error = nil
        let image = original
        extraction = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { try StickerImageProcessor.subjects(image) }.value
                guard !Task.isCancelled else { extracting = false; return }
                subjects = result; selectedSubject = result.first?.id
                if result.isEmpty { error = "暂时没能分离主体，可以重试或改为照片。" }
            } catch { self.error = "提取主体失败，请重试或改为照片。" }
            extracting = false
        }
    }
}
