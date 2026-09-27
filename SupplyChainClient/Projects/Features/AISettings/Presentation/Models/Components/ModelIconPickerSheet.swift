import SwiftUI

/// 公共图标选择器：对齐 AI_HLY 的网格图标页，用于模型/智能体的图标选择。
struct ModelIconPickerSheet: View {
    @Binding var selectedIcon: String
    let icons: [String]

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 70), spacing: 14)]

    init(selectedIcon: Binding<String>, icons: [String] = ModelIconCatalog.availableIcons) {
        _selectedIcon = selectedIcon
        self.icons = icons
    }

    var body: some View {
        CompatibleNavigationContainer {
            pickerContent
        }
    }

    private var pickerContent: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                        dismiss()
                    } label: {
                        iconCell(symbol: icon, isSelected: selectedIcon == icon)
                    }
//                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle(L10n.text("ai_settings.models.edit.icon_picker_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.cancel")) {
                    dismiss()
                }
            }
        }
    }

    private func iconCell(symbol: String, isSelected: Bool) -> some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .foregroundColor(.gray)
            .frame(width: 50, height: 50)
            .padding()
            .cornerRadius(10)
            .overlay(
                Group {
                    if selectedIcon == symbol {
                        selectionGradient
                            .mask(
                            Image(systemName: symbol)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 50, height: 50)
                        )
                    }
                }
            )
    }

    private var selectionGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
