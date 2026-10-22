import SwiftUI

struct CustomizationFormSteps: View {
    let selection: CustomizationFormStep
    let onSelect: (CustomizationFormStep) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let columns = typeSize.isAccessibilitySize ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(CustomizationFormStep.allCases) { step in
                Button { onSelect(step) } label: {
                    VStack(spacing: 4) {
                        Text("\(step.rawValue + 1) · \(step.title)").font(.footnote.weight(selection == step ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 36)
                        Capsule().fill(selection == step ? DiaryLibraryStyle.accent : DiaryLibraryStyle.line).frame(height: 2)
                    }
                    .foregroundStyle(selection == step ? DiaryLibraryStyle.accent : DiaryLibraryStyle.secondary)
                }.frame(minHeight: 44).buttonStyle(.plain).accessibilityAddTraits(selection == step ? [.isSelected] : [])
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("填写步骤")
    }
}

struct CustomizationStoryFields: View {
    @Binding var fields: [String: String]
    var focus: FocusState<String?>.Binding
    let issue: CustomizationFormIssue?
    @State private var moreExpanded = false
    @State private var styleExpanded = false
    @State private var customCategorySelected = false
    private let categories = ["旅行", "亲子", "爱情", "生日"]
    private var hasCustomCategory: Bool {
        customCategorySelected || (!(fields["category"] ?? "").isEmpty && !categories.contains(fields["category"] ?? ""))
    }
    private var customCategory: Binding<String> {
        Binding(get: { fields["category"] == "其他" ? "" : fields["category"] ?? "" },
                set: { fields["category"] = $0.isEmpty ? "其他" : $0 })
    }
    private let styles = ["清新留白", "旅行拼贴", "复古胶片"]
    private func field(_ key: String) -> Binding<String> {
        Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("这本手帐想记住什么？").font(.title2.weight(.semibold))
                Text("写下旅途、人物，或一个最想留下的瞬间。")
                    .font(.subheadline).foregroundStyle(DiaryLibraryStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                input("手帐名称", key: "title", placeholder: "例如：我们的云南旅行", limit: 60)
                input("想记录的故事", key: "description", placeholder: "去了哪里，和谁一起，哪个瞬间最想留下来？", limit: 3000, multiline: true)
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 10) {
                optionalTitle("场景")
                categoryGrid
                if hasCustomCategory {
                    TextField("例如：毕业纪念、朋友聚会", text: customCategory,
                              prompt: Text("例如：毕业纪念、朋友聚会").foregroundStyle(DiaryLibraryStyle.secondary.opacity(0.8)))
                        .textFieldStyle(.plain).focused(focus, equals: "category")
                        .padding(12).frame(minHeight: 44)
                        .background(DiaryLibraryStyle.background, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("其他场景")
                }
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 16) {
                DisclosureGroup(isExpanded: $styleExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("选择文字风格偏好，也可以直接告诉我们。选项不代表最终成品模板。")
                            .font(.caption).foregroundStyle(DiaryLibraryStyle.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { styleChoices }
                            VStack(alignment: .leading, spacing: 8) { styleChoices }
                        }
                        TextField("也可以写下自己的风格偏好", text: field("style"), axis: .vertical)
                            .textFieldStyle(.plain).focused(focus, equals: "style")
                            .padding(12).frame(minHeight: 44)
                            .background(DiaryLibraryStyle.background, in: RoundedRectangle(cornerRadius: 10))
                    }.padding(.top, 12)
                } label: { optionalTitle("风格偏好") }
                Divider()
                DisclosureGroup(isExpanded: $moreExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                        input("重要文字", key: "important_text", placeholder: "必须保留的姓名、日期或短句", multiline: true, optional: true)
                        input("故事顺序与页数偏好", key: "story_order", placeholder: "可以留空，由制作方安排；页数以受理后沟通为准", multiline: true, optional: true)
                        input("不希望出现的内容", key: "avoid", placeholder: "例如：不使用某张照片作封面", limit: 500, multiline: true, optional: true)
                    }.padding(.top, 16)
                } label: { optionalTitle("重要文字与其他要求") }
            }.padding(16).background(DiaryLibraryStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .onAppear {
            moreExpanded = ["important_text", "story_order", "avoid"].contains { !(fields[$0] ?? "").isEmpty }
            styleExpanded = !(fields["style"] ?? "").isEmpty
        }
        .onChange(of: issue) { _, value in if value?.field == "avoid" { moreExpanded = true } }
    }
    private var categoryGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { categoryChoices }
            VStack(alignment: .leading, spacing: 8) { categoryChoices }
        }
    }
    @ViewBuilder private var categoryChoices: some View {
        ForEach(categories + ["其他"], id: \.self) { name in
            let selected = name == "其他" ? hasCustomCategory : fields["category"] == name
            DiaryLibraryChip(title: name, selected: selected, compact: true) {
                if name == "其他" {
                    customCategorySelected = !selected
                    fields["category"] = selected ? "" : "其他"
                } else {
                    customCategorySelected = false
                    fields["category"] = selected ? "" : name
                }
            }
        }
    }
    @ViewBuilder private var styleChoices: some View {
        ForEach(styles, id: \.self) { name in
            let selected = (fields["style"] ?? "").components(separatedBy: "、")
            DiaryLibraryChip(title: name, selected: selected.contains(name), compact: true) {
                var values = selected.filter { !$0.isEmpty }
                if values.contains(name) { values.removeAll { $0 == name } }
                else if values.count < 3 { values.append(name) }
                fields["style"] = values.joined(separator: "、")
            }
        }
    }
    private func optionalTitle(_ title: String) -> some View {
        HStack(spacing: 6) { Text(title).font(.subheadline.weight(.medium)); Text("选填").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
    }
    private func input(_ label: String, key: String, placeholder: String, limit: Int? = nil, multiline: Bool = false, optional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                if optional { Text("选填").font(.caption).foregroundStyle(DiaryLibraryStyle.secondary) }
                Spacer()
                if let limit {
                    Text("\(fields[key, default: ""].count)/\(limit)").font(.caption.monospacedDigit())
                        .foregroundStyle(fields[key, default: ""].count > limit ? Color.red : DiaryLibraryStyle.secondary)
                }
            }
            TextField(placeholder, text: field(key), prompt: Text(placeholder).foregroundStyle(DiaryLibraryStyle.secondary.opacity(0.8)), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 3...7 : 1...2)
                .focused(focus, equals: key).accessibilityLabel(label)
                .padding(12).background(DiaryLibraryStyle.background, in: RoundedRectangle(cornerRadius: 10))
            if issue?.field == key { Text(issue?.message ?? "").font(.caption).foregroundStyle(.red) }
        }
    }
}
