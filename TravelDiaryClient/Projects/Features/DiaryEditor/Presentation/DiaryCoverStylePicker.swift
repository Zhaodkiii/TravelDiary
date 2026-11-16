import SwiftUI

struct DiaryCoverStylePicker: View {
    let book: DiaryBook
    let store: DiaryDocumentStore
    let openEditor: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: DiaryDefaultCoverStyle = .linen
    @State private var applying = false
    @State private var errorMessage: String?

    private var cover: DiaryPageEntry? { book.effectiveCover }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ViewThatFits {
                        HStack(alignment: .top, spacing: 12) { styles }
                        VStack(spacing: 16) { styles }
                    }
                    if cover != nil, cover?.defaultCover == nil {
                        Text("应用样式会把原封面移到最近删除。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                    Button(cover == nil ? "添加封面" : "应用样式") {
                        Task { await apply() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button(book.coverDraft == nil ? "自由制作封面" : "继续制作封面") {
                        dismiss()
                        openEditor()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .disabled(applying)
            }
            .navigationTitle(cover == nil ? "添加封面" : "更换封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.disabled(applying)
                }
            }
            .overlay { if applying { ProgressView("正在保存封面…") } }
        }
        .interactiveDismissDisabled(applying)
        .onAppear { selection = cover?.defaultCover?.style ?? .linen }
    }

    private var styles: some View {
        ForEach(DiaryDefaultCoverStyle.allCases) { style in
            Button { selection = style } label: {
                VStack(spacing: 8) {
                    ZStack {
                        Color(red: 0.97, green: 0.93, blue: 0.85)
                        if let url = style.resource(preview: true), let image = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                        Text(book.title)
                            .font(.system(.caption, design: .serif, weight: .semibold))
                            .foregroundStyle(Color(red: 0.22, green: 0.18, blue: 0.12))
                            .lineLimit(3)
                            .minimumScaleFactor(0.65)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .offset(y: -16)
                    }
                    .frame(width: 98, height: 140)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(selection == style ? Color.accentColor : .clear, lineWidth: 3)
                    }
                    Text(style.title).font(.footnote)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(style.title)
            .accessibilityAddTraits(selection == style ? .isSelected : [])
        }
    }

    private func apply() async {
        applying = true
        defer { applying = false }
        do {
            try await store.applyDefaultCover(selection, expectedCover: cover)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
