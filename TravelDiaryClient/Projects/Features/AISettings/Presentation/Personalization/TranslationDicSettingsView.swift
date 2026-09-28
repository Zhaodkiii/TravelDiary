import SwiftUI

struct TranslationDicSettingsView: View {
    @Binding var translationDic: [TranslationDic]

    var body: some View {
        List {
            ForEach($translationDic) { $item in
                Section(item.sourceText.isEmpty ? L10n.text("ai_settings.translation_item") : item.sourceText) {
                    TextField(L10n.text("ai_settings.field.source_text"), text: $item.sourceText)
                    TextField(L10n.text("ai_settings.field.target_text"), text: $item.targetText)
                    TextField(L10n.text("ai_settings.field.note"), text: $item.note)
                }
            }
            .onDelete { translationDic.remove(atOffsets: $0) }

            Button(L10n.text("ai_settings.action.add_translation")) {
                translationDic.append(
                    TranslationDic(
                        sourceText: "",
                        targetText: "",
                        note: "",
                        timestamp: Date()
                    )
                )
            }
        }
        .navigationTitle(L10n.text("ai_settings.row.translation_dic"))
    }
}
