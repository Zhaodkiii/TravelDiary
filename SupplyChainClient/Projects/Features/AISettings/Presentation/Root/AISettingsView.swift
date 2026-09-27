import SwiftUI

struct AISettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    var body: some View {
        List {
            Section(L10n.text("ai_settings.section.model")) {
                MainNavigationLink {
                    APIKeysSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.api_keys"),
                        subtitle: L10n.text("ai_settings.row.api_keys.subtitle"),
                        icon: "key.2.on.ring"
                    )
                }

                MainNavigationLink {
                    ModelsSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.models"),
                        subtitle: L10n.text("ai_settings.row.models.subtitle"),
                        icon: "square.stack.3d.up"
                    )
                }

                MainNavigationLink {
                    AIModelPreferencesView(
                        viewModel: viewModel.makeScenarioModelPreferencesViewModel()
                    )
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.default_model_config"),
                        subtitle: L10n.text("ai_settings.row.default_model_config.subtitle"),
                        icon: "slider.horizontal.3"
                    )
                }
            }

            Section(L10n.text("ai_settings.section.tools")) {
                MainNavigationLink {
                    SmallTasksSettingsView(viewModel: viewModel)
                } label: {
                    SettingNavRow(
                        title: "小任务",
                        subtitle: "维护本地小任务并关联到模型",
                        icon: "checklist"
                    )
                }

                // 当前版本 功能不完善 展示关闭入口
                MainNavigationLink {
                    AISearchToolSettingsView(viewModel: viewModel)
                        .hidesMainTabBarWhenPushed()
                } label: {
                    SettingNavRow(
                        title: L10n.text("ai_settings.row.search_tools"),
                        subtitle: L10n.text("ai_settings.row.search_tools.subtitle"),
                        icon: "wrench.and.screwdriver"
                    )
                }
            }

            // 当前版本 功能不完善 ，暂时关闭
//            Section(L10n.text("ai_settings.section.personalization")) {
//                NavigationLink {
//                    PromptRepoSettingsView(
//                        promptRepo: $viewModel.snapshot.promptRepo,
//                        onPersist: {
//                            await viewModel.persistPromptRepoNow()
//                        }
//                    )
//                        .hidesMainTabBarWhenPushed()
//                } label: {
//                    SettingNavRow(
//                        title: L10n.text("ai_settings.row.prompt_repo"),
//                        subtitle: L10n.text("ai_settings.row.prompt_repo.subtitle"),
//                        icon: "tray.full"
//                    )
//                }
//
//                NavigationLink {
//                    MemoryArchiveSettingsView(viewModel: viewModel.makeMemoryArchiveSettingsViewModel())
//                        .hidesMainTabBarWhenPushed()
//                } label: {
//                    SettingNavRow(
//                        title: L10n.text("ai_settings.row.memory_archive"),
//                        subtitle: L10n.text("ai_settings.row.memory_archive.subtitle"),
//                        icon: "archivebox"
//                    )
//                }
//
//                NavigationLink {
//                    TranslationDicSettingsView(translationDic: $viewModel.snapshot.translationDic)
//                        .hidesMainTabBarWhenPushed()
//                } label: {
//                    SettingNavRow(
//                        title: L10n.text("ai_settings.row.translation_dic"),
//                        subtitle: L10n.text("ai_settings.row.translation_dic.subtitle"),
//                        icon: "character.book.closed"
//                    )
//                }
//            }
        }
        .navigationTitle(L10n.text("ai_settings.title"))
    
        .task {
            await viewModel.load()
        }
        .alert(L10n.text("common.operation_failed"), isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { presented in
                if presented == false {
                    viewModel.clearError()
                }
            }
        )) {
            Button(L10n.text("common.ok")) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
     
    }
}

private struct SettingNavRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
