import SwiftUI

struct PrintAddressEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PrintAddress
    @State private var attemptedSave = false
    let regions: [String]
    let onSave: (PrintAddress) -> Void
    init(address: PrintAddress, regions: [String], onSave: @escaping (PrintAddress) -> Void) {
        _draft = State(initialValue: address); self.regions = regions; self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("收件人") {
                    TextField("收件人姓名", text: $draft.name).textContentType(.name)
                    if attemptedSave && (draft.trimmed.name.isEmpty || draft.trimmed.name.count > 60) {
                        issue("请填写 1–60 个字的收件人姓名")
                    }
                    TextField("手机号码", text: $draft.phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    if attemptedSave && !draft.phoneValid {
                        issue("请填写有效的联系电话，7–20 位，可包含国家区号")
                    }
                }
                Section {
                    Picker("配送地区", selection: $draft.region) {
                        Text("请选择配送地区").tag("")
                        ForEach(regions, id: \.self) { Text($0).tag($0) }
                    }
                    if attemptedSave && !regions.contains(draft.region) { issue("请选择支持配送的地区") }
                    TextField("市、区、街道及门牌号", text: $draft.detail, axis: .vertical)
                        .textContentType(.fullStreetAddress).lineLimit(3...6)
                    if attemptedSave && (draft.trimmed.detail.isEmpty || draft.trimmed.detail.count > 240) {
                        issue("请填写完整详细地址，最多 240 个字")
                    }
                } header: { Text("收货地址") } footer: { Text("请在详细地址中填写完整的市、区、街道和门牌号，确保可以准确送达。") }
            }.navigationTitle("编辑收货地址").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            attemptedSave = true
                            guard draft.complete, regions.contains(draft.region) else { return }
                            onSave(draft.trimmed); dismiss()
                        }
                    }
                }
        }.tint(DiaryLibraryStyle.accent)
    }
    private func issue(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.red) }
}
