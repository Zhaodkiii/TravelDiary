import SwiftUI
import UIKit

struct PrintRegionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: RegionPickerModel
    let onConfirm: (RegionSelection) -> Void
    init(dataset: RegionDataset, address: PrintAddress, onConfirm: @escaping (RegionSelection) -> Void) {
        _model=State(initialValue:RegionPickerModel(dataset:dataset,province:address.province_code,city:address.city_code,district:address.district_code))
        self.onConfirm=onConfirm
    }
    var body: some View {
        VStack(spacing:12) {
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Text("请选择所在地区").font(.headline)
                Spacer()
                Button("确定") {
                    guard let selection=model.selection else { return }
                    onConfirm(selection);dismiss()
                }.disabled(model.selection==nil)
            }.padding(.horizontal,20).padding(.top,20)
            RegionWheel(model:$model).frame(height:220)
            Text(model.selection?.city?.selectable_leaf == true ? "此城市不设区县，请在详细地址中填写街道和门牌号。" : "请选择省、市及区县，确认后保存。")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }.padding(.bottom,20).presentationDetents([.height(340)]).presentationDragIndicator(.visible)
    }
}

private struct RegionWheel: UIViewRepresentable {
    @Binding var model: RegionPickerModel
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIPickerView {
        let picker=UIPickerView();picker.delegate=context.coordinator;picker.dataSource=context.coordinator
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent=self
        picker.reloadAllComponents()
        let ids=[model.provinceID,model.cityID,model.districtID]
        for component in 0..<3 {
            let rows=context.coordinator.rows(component)
            if let row=rows.firstIndex(where:{$0.id==ids[component]}) { picker.selectRow(row,inComponent:component,animated:false) }
        }
    }
    final class Coordinator: NSObject, UIPickerViewDelegate, UIPickerViewDataSource {
        var parent: RegionWheel
        init(_ parent: RegionWheel) { self.parent=parent }
        func rows(_ component: Int) -> [RegionPickerOption] {
            switch component { case 0: parent.model.provinces;case 1: parent.model.cities;default: parent.model.districts }
        }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { rows(component).count }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { max(1,pickerView.bounds.width/3-4) }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 58 }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label=(view as? UILabel) ?? UILabel()
            let values=rows(component)
            label.text=values.indices.contains(row) ? values[row].title : ""
            label.font=UIFont.preferredFont(forTextStyle:.body);label.adjustsFontForContentSizeCategory=true
            label.numberOfLines=2;label.textAlignment = .center;label.adjustsFontSizeToFitWidth=true;label.minimumScaleFactor=0.7
            label.accessibilityLabel=(["省份","城市","区县"][component])+"，"+(label.text ?? "")
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let values=rows(component);guard values.indices.contains(row) else { return }
            parent.model.select(values[row].id,component:component)
            pickerView.reloadAllComponents()
        }
    }
}
