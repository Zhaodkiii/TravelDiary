import SwiftUI
import PhotosUI

extension View {
    func feedbackPaperCard() -> some View {
        background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(DiaryLibraryStyle.line.opacity(0.65), lineWidth: 0.75))
    }
}

struct FeedbackPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 52)
            .foregroundStyle(scheme == .dark ? Color.black.opacity(0.85) : .white)
            .background(DiaryLibraryStyle.accent.opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.6), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FeedbackCategoryButton: View {
    let kind: HelpServiceConfig.Kind
    let selected: Bool
    let action: () -> Void
    private var icon: String {
        ["usage": "questionmark.bubble", "suggestion": "lightbulb", "error": "exclamationmark.bubble",
         "order": "shippingbox", "other": "ellipsis.bubble"][kind.code] ?? "bubble.left"
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : icon).font(.caption)
                Text(kind.name).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 46).padding(.horizontal, 7)
            .foregroundStyle(selected ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
            .background(selected ? DiaryLibraryStyle.accent.opacity(0.10) : DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? DiaryLibraryStyle.accent.opacity(0.55) : DiaryLibraryStyle.line.opacity(0.7), lineWidth: selected ? 1 : 0.75))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct FeedbackInlineNotice: View {
    let message: String
    let symbol: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: symbol).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action { Button(actionTitle, action: action).font(.subheadline.weight(.semibold)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .foregroundStyle(DiaryLibraryStyle.accent)
        .background(DiaryLibraryStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

struct FeedbackScreenshotGrid: View {
    @Binding var photos: [FeedbackPhoto]
    @Binding var selection: [PhotosPickerItem]
    var maximum = 6
    var disabled = false
    var uploading: UUID? = nil
    var showAdd = true
    @State private var preview: FeedbackPhoto?
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 140), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                thumbnail(photo, index: index)
            }
            if showAdd && photos.count < maximum {
                PhotosPicker(selection: $selection, maxSelectionCount: maximum - photos.count, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "plus").font(.title2.weight(.light))
                        Text(photos.isEmpty ? "添加截图" : "继续添加").font(.caption)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(DiaryLibraryStyle.accent)
                    .background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(DiaryLibraryStyle.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                    .aspectRatio(1, contentMode: .fit)
                }.buttonStyle(.plain).disabled(disabled).accessibilityLabel("添加截图，最多 \(maximum) 张")
            }
        }
        .sheet(item: $preview) { photo in
            NavigationStack {
                ScrollView {
                    if let image = UIImage(data: photo.bytes) { Image(uiImage: image).resizable().scaledToFit().padding() }
                }
                .background(DiaryLibraryStyle.background).navigationTitle("截图预览").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { preview = nil } } }
            }.tint(DiaryLibraryStyle.accent)
        }
    }
    private func thumbnail(_ photo: FeedbackPhoto, index: Int) -> some View {
        GeometryReader { geometry in
            Button { preview = photo } label: {
                Group {
                    if let image = UIImage(data: photo.bytes) { Image(uiImage: image).resizable().scaledToFill() }
                    else { DiaryLibraryStyle.line }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain).accessibilityLabel("预览第 \(index + 1) 张截图")
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if uploading == photo.id { ProgressView().tint(.white).controlSize(.mini) }
                    else if photo.attachmentID != nil { Image(systemName: "checkmark") }
                    Text(uploading == photo.id ? "上传中" : photo.attachmentID == nil ? "截图 \(index + 1)" : "已就绪")
                }
                .font(.caption2.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.6), in: Capsule()).padding(6)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                Button { photos.removeAll { $0.id == photo.id } } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).disabled(disabled).accessibilityLabel("移除第 \(index + 1) 张截图")
            }
        }.aspectRatio(1, contentMode: .fit)
    }
}

// Existing reply forms reuse the compact, previewable grid without a second add control.
struct FeedbackPhotoRows: View {
    @Binding var photos: [FeedbackPhoto]
    var disabled = false
    var body: some View {
        FeedbackScreenshotGrid(photos: $photos, selection: .constant([]), disabled: disabled, showAdd: false)
    }
}

struct FeedbackEnvironmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var fields: [(String, String)] {
        [("应用版本", AppVersionInformation.title), ("系统版本", "iOS \(UIDevice.current.systemVersion)"),
         ("设备类型", UIDevice.current.model), ("语言", Locale.preferredLanguages.first ?? "zh-Hans")]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("为定位问题，附带以下基础信息", systemImage: "checkmark.shield").font(.headline)
                    VStack(spacing: 16) { ForEach(fields, id: \.0) { field in LabeledContent(field.0, value: field.1) } }.padding(18).feedbackPaperCard()
                    Text("不会自动上传运行日志、手帐正文、原照片或位置。你主动选择的截图会随反馈一起发送，请先检查其中的私人信息。")
                        .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
                }.padding(24)
            }
            .background(DiaryLibraryStyle.background).foregroundStyle(DiaryLibraryStyle.ink)
            .navigationTitle("随反馈附带的信息").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(DiaryLibraryStyle.accent).presentationDetents([.medium, .large])
    }
}

struct FeedbackSubmissionSuccess: View {
    let ticket: FeedbackTicket
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 58, weight: .light))
                .foregroundStyle(DiaryLibraryStyle.accent).padding(.top, 28).accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("反馈已送达").font(.system(.title, design: .serif).weight(.semibold))
                Text("谢谢你愿意告诉我们。\n后续回复会出现在“我的反馈”中。")
                    .font(.body).foregroundStyle(DiaryLibraryStyle.secondary).multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 14) {
                Label(ticket.title, systemImage: "bubble.left").font(.headline)
                Divider()
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("反馈编号").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                        Text(ticket.number).font(.system(.caption2, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.75).textSelection(.enabled)
                    }
                    Spacer()
                    Button { UIPasteboard.general.string = ticket.number } label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("复制反馈编号")
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).feedbackPaperCard()
        }.frame(maxWidth: .infinity).accessibilityIdentifier("feedback.success")
    }
}
