import SwiftUI

/// 仅改变当前跨页的只读预览；品牌图层不作为可操作的预览分类。
struct DiaryPreviewContentPanel: View {
    @Binding var hiddenCategories: Set<DiaryLayerSemanticKind>
    var affectsImport = false
    private let categories: [DiaryLayerSemanticKind] = [.background, .photo, .paper, .text, .illustration]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { categoryButton($0) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { categoryButton($0).fixedSize(horizontal: true, vertical: false) }
                    }
                }
            }
//            HStack(spacing: 8) {
//                Text(affectsImport ? "仅添加已开启的图层分类" : "仅影响预览，添加时保留完整内容")
//                    .font(.caption2).foregroundStyle(DiaryLibraryStyle.secondary)
//                    .fixedSize(horizontal: false, vertical: true)
//                Spacer(minLength: 0)
//                Button("恢复") { hiddenCategories.removeAll() }
//                    .font(.caption.weight(.medium))
//                    .foregroundStyle(DiaryLibraryStyle.accent)
//                    .frame(minWidth: 44, minHeight: 44)
//                    .disabled(hiddenCategories.isEmpty)
//            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("预览内容")
    }

    private func categoryButton(_ category: DiaryLayerSemanticKind) -> some View {
        let visible = !hiddenCategories.contains(category)
        return Button {
            if visible { hiddenCategories.insert(category) }
            else { hiddenCategories.remove(category) }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if category == .text {
                            Text("T").font(.system(size: 16, weight: .medium, design: .serif))
                        } else {
                            Image(systemName: symbol(category)).font(.system(size: 15))
                        }
                    }.frame(width: 24, height: 18)
                    if !visible {
                        Image(systemName: "minus.circle.fill").font(.system(size: 8))
                            .offset(x: 4, y: 2)
                    }
                }
                Text(affectsImport && category == .paper ? "卡纸" : category.title).fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(visible ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
            .background(visible ? DiaryLibraryStyle.accent.opacity(0.09) : DiaryLibraryStyle.surface,
                        in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(
                visible ? DiaryLibraryStyle.accent.opacity(0.12) : DiaryLibraryStyle.line.opacity(0.6), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityValue(visible ? "显示" : "隐藏")
        .accessibilityHint(visible ? "轻点关闭此类内容" : "轻点开启此类内容")
        .accessibilityAddTraits(visible ? [.isSelected] : [])
    }

    private func symbol(_ category: DiaryLayerSemanticKind) -> String {
        switch category {
        case .background: "square.dashed.inset.filled"
        case .photo: "photo"
        case .paper: "rectangle.on.rectangle"
        case .text: "textformat"
        case .illustration: "sparkles"
        case .branding: "seal"
        }
    }
}

#Preview("预览内容") {
    @Previewable @State var hidden: Set<DiaryLayerSemanticKind> = [.photo]
    DiaryPreviewContentPanel(hiddenCategories: $hidden)
        .padding(24).background(DiaryLibraryStyle.background)
}
