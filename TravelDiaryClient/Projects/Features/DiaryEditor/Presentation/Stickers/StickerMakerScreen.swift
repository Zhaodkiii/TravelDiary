import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct StickerMakerScreen: View {
    var addsToCanvas: Bool
    var onSaved: (PersonalSticker, Data) async -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accountLoginContext) private var accountLoginContext
    @State private var showingLogin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var subjects: [StickerSubject] = []
    @State private var selected: Int?
    @State private var stage = 0
    @State private var style = "白边"
    @State private var thickness = 2
    @State private var colorIndex = 1
    @State private var darkPreview = false
    @State private var checkerPreview = false
    @State private var pan: CGSize = .zero
    @State private var showSettings = false
    @State private var busy = false
    @State private var error: String?
    @State private var original: UIImage?
    @State private var rendered: UIImage?
    @State private var identity = UUID()
    @State private var plan: PersonalStickerUpload?
    @State private var uploaded = false
    @State private var confirmExit = false
    @State private var task: Task<Void, Never>?
    @State private var zoom: CGFloat = 1
    private let colors: [UIColor] = [.white, UIColor(red: 0.18, green: 0.22, blue: 0.25, alpha: 1),
        UIColor(red: 0.80, green: 0.46, blue: 0.40, alpha: 1), UIColor(red: 0.48, green: 0.59, blue: 0.52, alpha: 1),
        UIColor(red: 0.77, green: 0.66, blue: 0.46, alpha: 1), UIColor(red: 0.60, green: 0.55, blue: 0.68, alpha: 1),
        UIColor(red: 0.45, green: 0.60, blue: 0.67, alpha: 1)]
    private let colorNames = ["白色", "炭灰", "珊瑚", "绿色", "沙金", "雾紫", "湖蓝"]
    private var image: UIImage? { subjects.first { $0.id == selected }?.image }
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if busy { ProgressView(stage == 0 ? "正在寻找主体…" : "正在保存…").padding() }
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal).accessibilityAddTraits(.updatesFrequently)
                    if showSettings { Button("前往设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.frame(minHeight: 44) }
                }
                if stage == 0 {
                    Spacer()
                    if let original { Image(uiImage: original).resizable().scaledToFit().padding() }
                    else { ContentUnavailableView("把小物变成贴纸", systemImage: "scissors", description: Text("留下旅途中喜欢的东西")) }
                    Spacer()
                    sourceButtons
                    if original != nil && !busy { Button("重试识别") { if let original { analyze(original) } }.frame(minHeight: 44) }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if stage == 1, let original {
                                GeometryReader { geometry in
                                    let ratio = min(geometry.size.width / original.size.width, geometry.size.height / original.size.height)
                                    let size = CGSize(width: original.size.width * ratio, height: original.size.height * ratio)
                                    ZStack {
                                        Image(uiImage: original).resizable().scaledToFit().opacity(0.65)
                                        ForEach(subjects) { subject in
                                            let box = subject.bounds
                                            Button { selected = subject.id } label: {
                                                RoundedRectangle(cornerRadius: 8).stroke(selected == subject.id ? Color.accentColor : .white, lineWidth: selected == subject.id ? 3 : 1)
                                                    .background(selected == subject.id ? Color.accentColor.opacity(0.08) : .clear)
                                                    .overlay(alignment: .topTrailing) { if selected == subject.id { Image(systemName: "checkmark.circle.fill").padding(4) } }
                                            }
                                            .frame(width: max(44, box.width * size.width), height: max(44, box.height * size.height))
                                            .position(x: (geometry.size.width - size.width) / 2 + box.midX * size.width,
                                                      y: (geometry.size.height - size.height) / 2 + box.midY * size.height)
                                            .accessibilityLabel("主体 \(subject.id)")
                                        }
                                    }
                                }.frame(height: 300)
                            } else if let preview = rendered {
                                Image(uiImage: preview).resizable().scaledToFit().padding(24)
                                    .scaleEffect(zoom).offset(pan).frame(height: 300).clipped()
                                    .background {
                                        if checkerPreview { StickerCheckerboard() }
                                        else { (darkPreview ? Color(white: 0.2) : Color.white.opacity(0.75)) }
                                    }.clipShape(RoundedRectangle(cornerRadius: 24))
                                    .onTapGesture(count: 2) { zoom = 1; pan = .zero }
                                    .simultaneousGesture(DragGesture().onChanged { pan = CGSize(width: min(150, max(-150, $0.translation.width)), height: min(150, max(-150, $0.translation.height))) })
                                    .gesture(MagnifyGesture().onChanged { zoom = min(3, max(1, $0.magnification)) })
                            }
                            HStack {
                                Button(darkPreview ? "切换浅底" : "切换深底") { darkPreview.toggle() }
                                Button("棋盘格") { checkerPreview.toggle() }
                                Button("适合屏幕") { zoom = 1; pan = .zero }
                            }.font(.callout).frame(minHeight: 44)
                            if stage == 1 {
                                Text("点一下，选择想留下的物体").foregroundStyle(.secondary)
                                ScrollView(.horizontal) {
                                    HStack {
                                        ForEach(subjects) { subject in
                                            Button { selected = subject.id } label: {
                                                Image(uiImage: subject.image).resizable().scaledToFit().frame(width: 88, height: 88).padding(6)
                                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected == subject.id ? Color.accentColor : .clear, lineWidth: 3))
                                                    .overlay(alignment: .topTrailing) { if selected == subject.id { Image(systemName: "checkmark.circle.fill") } }
                                            }.accessibilityLabel("主体 \(subject.id)").accessibilityAddTraits(selected == subject.id ? [.isSelected] : [])
                                        }
                                    }.padding(4)
                                }
                                sourceButtons
                            } else {
                                Text("样式").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                                ViewThatFits {
                                    HStack { styleButtons }
                                    VStack { styleButtons }
                                }
                                if style == "彩边" || style == "虚线" {
                                    ScrollView(.horizontal) {
                                        HStack {
                                            ForEach(colors.indices, id: \.self) { index in
                                                Button { colorIndex = index; updatePreview() } label: {
                                                    Circle().fill(Color(uiColor: colors[index])).frame(width: 32, height: 32).padding(6)
                                                        .overlay { Circle().stroke(colorIndex == index ? Color.primary : .clear, lineWidth: 2) }
                                                        .overlay { if colorIndex == index { Image(systemName: "checkmark").foregroundStyle(index == 0 ? .black : .white) } }
                                                }.accessibilityLabel(colorNames[index]).accessibilityAddTraits(colorIndex == index ? [.isSelected] : [])
                                            }
                                        }.padding(3)
                                    }
                                }
                                if style != "原样" {
                                    Picker("描边粗细", selection: $thickness) { Text("细").tag(1); Text("中").tag(2); Text("粗").tag(3) }
                                        .pickerStyle(.segmented).onChange(of: thickness) { _, _ in updatePreview() }
                                }
                            }
                        }.padding(20).disabled(busy)
                    }
                    Button {
                        if stage == 1 { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { stage = 2; updatePreview() } } else { save() }
                    } label: {
                        Text(stage == 1 ? "制作贴纸" : busy ? "正在保存…" : addsToCanvas ? "保存并添加" : "保存贴纸")
                            .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
                    }.buttonStyle(.borderedProminent).padding(.horizontal, 20).padding(.bottom, 12).disabled(busy || image == nil)
                }
            }
            .background(DiaryLibraryStyle.background)
            .navigationTitle(stage == 0 ? "制作一张贴纸" : stage == 1 ? "选择主体" : "制作贴纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(stage == 2 ? "返回" : "关闭") {
                        if stage == 2 { stage = 1; zoom = 1 }
                        else if busy && stage == 0 { task?.cancel(); busy = false; original = nil }
                        else if original != nil { confirmExit = true } else { dismiss() }
                    }.disabled(busy && stage != 0)
                }
            }
            .interactiveDismissDisabled(original != nil || busy)
            .confirmationDialog("贴纸还未保存", isPresented: $confirmExit, titleVisibility: .visible) {
                Button("放弃", role: .destructive) { task?.cancel(); dismiss() }
                Button("继续制作", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                StickerCameraPicker { image in showCamera = false; if let image { analyze(image) } }
                    .ignoresSafeArea()
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                task?.cancel()
                task = Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                        guard !Task.isCancelled else { return }; analyze(image)
                    } catch { self.error = "无法读取照片，请重新选择" }
                }
            }
            .sheet(isPresented: $showingLogin) {
                if let accountLoginContext { LoginView(viewModel: accountLoginContext.viewModel, mode: .upgradeDeviceAccount) }
            }
            .onChange(of: accountLoginContext?.isDeviceAccount) { _, value in
                if value == false { showingLogin = false }
            }
            .onDisappear { task?.cancel() }
        }.tint(DiaryLibraryStyle.accent)
    }
    private var styleButtons: some View {
        ForEach(["原样", "白边", "彩边", "虚线"], id: \.self) { value in
            Button { style = value; updatePreview() } label: {
                VStack(spacing: 6) {
                    if let image {
                        Image(uiImage: StickerImageProcessor.render(StickerImageProcessor.thumbnail(image), style: value, color: value == "白边" ? .white : colors[colorIndex], thickness: thickness))
                            .resizable().scaledToFit().frame(width: 48, height: 48)
                    }
                    Label(value, systemImage: style == value ? "checkmark.circle.fill" : "circle").font(.caption)
                }.frame(minHeight: 76)
            }.buttonStyle(.bordered).accessibilityAddTraits(style == value ? [.isSelected] : [])
        }
    }
    private var sourceButtons: some View {
        HStack(spacing: 20) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("拍照制作", systemImage: "camera") {
                    Task {
                        let allowed: Bool
                        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
                        else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
                        if allowed { showCamera = true } else { showSettings = true; error = "相机权限未开启，可从相册选择，或前往系统设置开启相机权限" }
                    }
                }.frame(minHeight: 44)
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("从相册选择", systemImage: "photo") }.frame(minHeight: 44)
        }.padding().disabled(busy)
    }
    private func analyze(_ input: UIImage) {
        task?.cancel(); original = input; busy = true; stage = 0; error = nil; subjects = []; selected = nil
        task = Task {
            do {
                let results = try await Task.detached(priority: .userInitiated) { try StickerImageProcessor.subjects(input) }.value
                guard !Task.isCancelled else { return }
                subjects = results
                selected = results.min { a, b in
                    hypot(a.bounds.midX - 0.5, a.bounds.midY - 0.5) < hypot(b.bounds.midX - 0.5, b.bounds.midY - 0.5)
                }?.id
                busy = false
                if results.isEmpty { error = "没有找到清晰主体，试试靠近一点或换个背景" }
                else { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { stage = 1 } }
            } catch { guard !Task.isCancelled else { return }; busy = false; self.error = "未能提取主体，请重试或换一张照片" }
        }
    }
    private func updatePreview() {
        guard let image else { return }
        rendered = StickerImageProcessor.render(image, style: style, color: style == "白边" ? .white : colors[colorIndex], thickness: thickness)
        identity = UUID(); plan = nil; uploaded = false; error = nil
    }
    private func save() {
        if accountLoginContext?.isDeviceAccount == true { showingLogin = true; return }
        guard let data = rendered?.pngData(), data.count <= 10 * 1024 * 1024 else { error = "图片过大，请换一张照片"; return }
        let owner = MaterialCatalogRepository.shared.owner
        busy = true; error = nil
        task = Task {
            do {
                if plan == nil || !uploaded { plan = try await PersonalStickerService.request("uploads/", body: ["uuid": identity.uuidString.lowercased(), "byteSize": String(data.count)]) }
                guard let plan else { throw URLError(.badServerResponse) }
                if !uploaded { try await PersonalStickerService.upload(data, plan: plan); uploaded = true }
                guard owner == MaterialCatalogRepository.shared.owner else { throw CancellationError() }
                let sticker: PersonalSticker = try await PersonalStickerService.request("stickers/", body: ["imageObjectKey": plan.imageObjectKey, "token": plan.token])
                guard !Task.isCancelled, owner == MaterialCatalogRepository.shared.owner else { throw CancellationError() }
                await onSaved(sticker, data); dismiss()
            } catch { busy = false; self.error = "没有保存成功，请检查登录状态和网络后重试" }
        }
    }
}

private struct StickerCameraPicker: UIViewControllerRepresentable {
    var completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        picker.cameraOverlayView = overlay()
        return picker
    }
    private func overlay() -> UIView {
        let view = StickerCameraGuide(frame: UIScreen.main.bounds)
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion(info[.originalImage] as? UIImage) }
    }
}

private final class StickerCameraGuide: UIView {
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        let box = CGRect(x: bounds.width * 0.12, y: bounds.height * 0.22, width: bounds.width * 0.76, height: bounds.height * 0.42)
        let path = UIBezierPath(); let length: CGFloat = 30
        for (point, dx, dy) in [(CGPoint(x: box.minX, y: box.minY), CGFloat(1), CGFloat(1)),
                                 (CGPoint(x: box.maxX, y: box.minY), CGFloat(-1), CGFloat(1)),
                                 (CGPoint(x: box.minX, y: box.maxY), CGFloat(1), CGFloat(-1)),
                                 (CGPoint(x: box.maxX, y: box.maxY), CGFloat(-1), CGFloat(-1))] {
            path.move(to: CGPoint(x: point.x, y: point.y + dy * length)); path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + dx * length, y: point.y))
        }
        UIColor.white.withAlphaComponent(0.85).setStroke(); path.lineWidth = 3; path.lineCapStyle = .round; path.stroke()
        let text = "把想留下的小物放进框里" as NSString
        text.draw(in: CGRect(x: box.minX, y: box.maxY + 16, width: box.width, height: 44), withAttributes: [
            .font: UIFont.preferredFont(forTextStyle: .callout), .foregroundColor: UIColor.white])
    }
}

private struct StickerCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 16
            for y in 0...Int(size.height / side) {
                for x in 0...Int(size.width / side) {
                    context.fill(Path(CGRect(x: CGFloat(x) * side, y: CGFloat(y) * side, width: side, height: side)),
                                 with: .color((x + y).isMultiple(of: 2) ? Color(white: 0.9) : .white))
                }
            }
        }.accessibilityHidden(true)
    }
}
