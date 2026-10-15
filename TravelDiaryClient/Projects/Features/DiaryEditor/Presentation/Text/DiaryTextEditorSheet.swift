import SwiftUI
import UIKit

/// 整个弹窗维护草稿，完成时只提交一次文档修改。
struct DiaryTextEditorSheet: View {
    @ObservedObject var session: DiaryEditorSession
    let layer: DiaryLayer?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var size: CGFloat
    @State private var font: DiaryFontReference?
    @State private var category = ""
    @State private var search = ""
    @State private var ready = false
    @State private var error: String?
    @State private var saving = false
    @State private var committed = false

    init(session: DiaryEditorSession, layer: DiaryLayer?) {
        self.session = session; self.layer = layer
        _text = State(initialValue: layer?.text ?? "")
        _size = State(initialValue: layer?.fontSize ?? 36)
        _font = State(initialValue: layer?.font)
    }
    private var changed: Bool { text != (layer?.text ?? "") || size != (layer?.fontSize ?? 36) || font != layer?.font }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    DiaryTextInputView(text: $text, font: (ready ? DiaryFontCatalog.shared.font(font, size: size) : UIFont.systemFont(ofSize: size)))
                    if text.isEmpty {
                        Text("记录此刻的心情…").font(Font((ready ? DiaryFontCatalog.shared.font(font, size: size) : UIFont.systemFont(ofSize: size))))
                            .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false)
                    }
                }.frame(minHeight: 120, maxHeight: 200)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Text("字体：\(DiaryFontCatalog.shared.entry(font)?.displayName ?? "原字体暂不可用")").lineLimit(1)
                    Spacer()
                    Button("收起键盘") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }.font(.caption)
                HStack {
                    Text("字号 \(Int(size))")
                    Slider(value: $size, in: min(18, layer?.fontSize ?? 36)...max(90, layer?.fontSize ?? 36), step: 1)
                }
                if ready, let warning = DiaryFontCatalog.shared.warning(font, text: text) {
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                }
                Picker("字体分类", selection: $category) {
                    Text("全部").tag("")
                    Text("手写").tag("handwriting")
                    Text("毛笔书法").tag("calligraphy")
                    Text("标题装饰").tag("display")
                }.pickerStyle(.segmented)
                TextField("搜索字体", text: $search).textFieldStyle(.roundedBorder)
                if ready {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(DiaryFontCatalog.shared.entries.filter {
                                (category.isEmpty || $0.category == category) && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search))
                            }) { entry in
                                Button {
                                    font = entry.reference
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(entry.displayName).font(.caption)
                                            Text("山川与日常 Aa 123").font(Font(DiaryFontCatalog.shared.font(entry.reference, size: 22)))
                                            if let message = DiaryFontCatalog.shared.failures[entry.id] { Text(message).font(.caption) }
                                        }
                                        Spacer()
                                        if (font ?? .system) == entry.reference { Image(systemName: "checkmark") }
                                    }.foregroundStyle(.primary)
                                }.disabled(!DiaryFontCatalog.shared.available(entry.reference)).id(entry.id)
                            }
                        }.listStyle(.plain)
                            .onAppear { proxy.scrollTo((font ?? .system).id, anchor: .center) }
                    }
                } else { ProgressView() }
                if let failure = DiaryFontCatalog.shared.failures["catalog"] { Text(failure).font(.caption) }
            }.padding().disabled(saving || committed)
                .navigationTitle("文字编辑").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(committed ? "关闭" : "取消") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(committed ? "重试保存" : "完成") {
                            guard !saving else { return }
                            if !committed {
                                guard session.applyTextEdit(targetID: layer?.id, text: text, fontSize: size, font: font) else {
                                    error = session.errorMessage ?? "暂时无法保存文字，请重试。"; return
                                }
                                committed = true
                            }
                            saving = true
                            Task {
                                do { try await session.save(); dismiss() }
                                catch { self.error = "文字已保留在当前编辑器中，写入失败：" + error.localizedDescription }
                                saving = false
                            }
                        }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.busy || saving)
                    }
                }
                .alert("文字编辑", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("确定") { error = nil }
                } message: { Text(error ?? "") }
        }.presentationDetents([.large]).interactiveDismissDisabled(changed || saving)
            .task {
                DiaryFontCatalog.shared.prepare()
                await DiaryFontCatalog.shared.prewarm(DiaryFontCatalog.shared.entries.map(\.reference))
                if !Task.isCancelled { ready = true }
            }
    }
}

/// 改字体只修改属性，保留光标和滚动位置；中文组合输入期间延迟样式应用。
private struct DiaryTextInputView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear; view.delegate = context.coordinator
        view.isEditable = true; view.isSelectable = true; view.allowsEditingTextAttributes = false
        view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        view.text = text
        context.coordinator.applyStyle(view)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.markedTextRange == nil else { return }
        if view.text != text { view.text = text }
        context.coordinator.applyStyle(view)
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DiaryTextInputView
        var applying = false
        init(_ parent: DiaryTextInputView) { self.parent = parent }
        func applyStyle(_ view: UITextView) {
            guard !applying, view.markedTextRange == nil else { return }
            applying = true
            defer { applying = false }
            let selection = view.selectedRange; let offset = view.contentOffset
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineHeightMultiple = 1.2
            let attrs: [NSAttributedString.Key: Any] = [.font: parent.font, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
            view.textStorage.setAttributes(attrs, range: NSRange(location: 0, length: view.textStorage.length))
            view.typingAttributes = attrs
            view.selectedRange = selection; view.setContentOffset(offset, animated: false)
        }
        func textViewDidChange(_ textView: UITextView) {
            guard !applying else { return }
            parent.text = textView.text
            applyStyle(textView)
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            // 输入法结束组合后，异步应用用户最新选择，避免在委托中递归更改选区。
            if !applying { DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, textView.font != self.parent.font else { return }
                self.applyStyle(textView)
            } }
        }
    }
}
