import SwiftUI

struct SettingsView: View {
    @ObservedObject var accountManagementViewModel: AccountManagementViewModel
    @ObservedObject var aiSettingsViewModel: AISettingsViewModel
    let session: UserSession
    let onAccountEntryTap: () -> Void

    var body: some View {
        List {
            Section(L10n.text("settings.section.account", fallback: "账户")) {
                Button(action: onAccountEntryTap) {
                    HStack {
                        Label(
                            L10n.text("settings.account_management", fallback: "账户管理"),
                            systemImage: "person.crop.circle"
                        )
                        Spacer()
                        Text(accountTrailingText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityHint(
                    session.isDeviceAccount
                        ? L10n.text(
                            "settings.account.device_not_linked.accessibility_hint",
                            fallback: "打开登录页，将游客账户升级为正式账户"
                        )
                        : L10n.text("settings.account_management", fallback: "账户管理")
                )
            }

            Section("实物印制") {
                MainNavigationLink { PrintOrdersScreen(owner: String(session.accountID)) } label: {
                    Label("我的印制订单", systemImage: "shippingbox")
                }
            }

            Section(L10n.text("settings.section.ai", fallback: "AI")) {
                MainNavigationLink {
                    AISettingsView(viewModel: aiSettingsViewModel)
                } label: {
                    HStack {
                        Label(
                            L10n.text("settings.ai_scenarios", fallback: "AI 场景"),
                            systemImage: "cpu"
                        )
                        Spacer()
                        Text(L10n.text("settings.ai_scenarios.subtitle", fallback: "模型与能力"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(L10n.text("settings.title", fallback: "设置"))
    }

    private var accountTrailingText: String {
        if session.isDeviceAccount {
            return L10n.text("settings.account.device_not_linked", fallback: "未登录")
        }
        if session.displayName.isEmpty == false {
            return session.displayName
        }
        return session.email
    }
}
