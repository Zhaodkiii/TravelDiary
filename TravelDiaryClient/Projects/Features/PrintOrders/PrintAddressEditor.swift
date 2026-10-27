import SwiftUI

struct PrintAddressEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PrintAddress
    @State private var attemptedSave = false
    @State private var choosingRegion = false
    @State private var pickerDataset: RegionDataset?
    @ObservedObject private var regionRepository = RegionRepository.shared
    @FocusState private var inputFocused: Bool
    let regions: [String]
    let onSave: (PrintAddress) -> Void
    init(address: PrintAddress, regions: [String], onSave: @escaping (PrintAddress) -> Void) {
        _draft = State(initialValue: address); self.regions = regions; self.onSave = onSave
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("收件人") {
                    TextField("收件人姓名", text: $draft.name).textContentType(.name).focused($inputFocused)
                    if attemptedSave && (draft.trimmed.name.isEmpty || draft.trimmed.name.count > 60) {
                        issue("请填写 1–60 个字的收件人姓名")
                    }
                    TextField("手机号码", text: $draft.phone).keyboardType(.phonePad).textContentType(.telephoneNumber).focused($inputFocused)
                    if attemptedSave && !draft.phoneValid {
                        issue("请填写有效的联系电话，7–20 位，可包含国家区号")
                    }
                }
                Section {
                    Button {
                        inputFocused=false
                        pickerDataset=regionRepository.dataset
                        choosingRegion=pickerDataset != nil
                    } label: {
                        HStack {
                            Text("所在地区").foregroundStyle(.primary)
                            Spacer()
                            Text(draft.hasAdministrativeRegion ? draft.regionDisplayName : "请选择省 / 市 / 区")
                                .foregroundStyle(draft.hasAdministrativeRegion ? .primary : .secondary)
                                .multilineTextAlignment(.trailing)
                            Image(systemName:"chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical,8)
                    }.disabled(regionRepository.dataset==nil)
                    if attemptedSave && !draft.hasAdministrativeRegion { issue("请选择所在地区") }
                    if let dataset=regionRepository.dataset, draft.hasAdministrativeRegion && !draft.regionExists(in:dataset) {
                        issue("原地区已调整，请重新选择所在地区；下方详细地址已保留")
                    }
                    if draft.hasAdministrativeRegion && !regions.contains(draft.region) { issue("所选地区暂不支持配送，请更换地区") }
                    if !draft.hasAdministrativeRegion && !draft.detail.isEmpty {
                        Text("请补选省市区，并检查下方原地址是否重复包含地区名称。").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("街道、小区、楼栋及门牌号", text: $draft.detail, axis: .vertical)
                        .textContentType(.fullStreetAddress).focused($inputFocused).lineLimit(3...6)
                    if attemptedSave && draft.submissionAddress(structured:regionRepository.supportsStructuredAddress).detail.count > 240 {
                        issue("完整地址超过 240 个字，请精简详细地址")
                    }
                    if attemptedSave && (draft.trimmed.detail.isEmpty || draft.trimmed.detail.count > 240) {
                        issue("请填写完整详细地址，最多 240 个字")
                    }
                } header: { Text("收货地址") } footer: { Text("目前支持中国大陆配送。请选择所在地区，并填写街道、小区和门牌号。") }
                if let error=regionRepository.error {
                    Section {
                        Text(regionRepository.dataset==nil ? error : "地区更新暂不可用，当前本地数据仍可选择。").font(.caption).foregroundStyle(.secondary)
                        Button("重试更新地区") { Task { await regionRepository.checkForUpdates(force:true) } }.disabled(regionRepository.updating)
                    }
                }
            }.navigationTitle("编辑收货地址").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            attemptedSave = true
                            guard draft.complete, let dataset=regionRepository.dataset, draft.regionExists(in:dataset), regions.contains(draft.region) else { return }
                            guard draft.submissionAddress(structured:regionRepository.supportsStructuredAddress).detail.count<=240 else { return }
                            draft.formatted_address=nil
                            onSave(draft.trimmed); dismiss()
                        }
                    }
                }
        }.tint(DiaryLibraryStyle.accent)
            .task { await regionRepository.checkForUpdates() }
            .sheet(isPresented:$choosingRegion) {
                if let pickerDataset {
                    PrintRegionPicker(dataset:pickerDataset,address:draft) { selection in
                        draft.select(selection,shippingRegions:regions)
                    }
                }
            }
    }
    private func issue(_ text: String) -> some View { Text(text).font(.caption).foregroundStyle(.red) }
}
