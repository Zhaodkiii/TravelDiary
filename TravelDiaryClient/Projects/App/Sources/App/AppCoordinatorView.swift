import SwiftUI

struct AppCoordinatorView: View {
    let dependencies: AppCoordinatorDependencies
    @StateObject private var networkMonitor = NetworkPathMonitor()
    @StateObject private var lifecycle: AppLifecycleCoordinator

    init(dependencies: AppCoordinatorDependencies) {
        self.dependencies = dependencies
        _lifecycle = StateObject(wrappedValue: dependencies.lifecycle)
    }

    var body: some View {
        ZStack {
            sessionContent
            if networkMonitor.hasEvaluatedPath, !networkMonitor.isSatisfied {
                NetworkGateView(monitor: networkMonitor)
            }
        }
        .task {
            networkMonitor.start()
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        switch lifecycle.sessionState {
        case .loading:
            AppLaunchScreenView()
                .task(id: "\(networkMonitor.hasEvaluatedPath)-\(networkMonitor.isSatisfied)") {
                    await lifecycle.bootstrapLaunchAfterNetworkEvaluation(
                        networkHasEvaluated: networkMonitor.hasEvaluatedPath,
                        networkSatisfied: networkMonitor.isSatisfied
                    )
                }
        case .signedOut:
            SignedOutAuthCoordinatorView(dependencies: dependencies)
        case .signedIn(let session):
            if lifecycle.preparedAccountID == session.accountID {
                SupportMainCoordinatorView(session: session, dependencies: dependencies)
            } else {
                AppLaunchScreenView()
            }
        }
    }
}

private struct SignedOutAuthCoordinatorView: View {
    let dependencies: AppCoordinatorDependencies
    @StateObject private var viewModel: LoginViewModel

    init(dependencies: AppCoordinatorDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: dependencies.makeLoginViewModel())
    }

    var body: some View {
        LoginView(viewModel: viewModel)
            .task {
                await dependencies.lifecycle.handleSignedOutTask()
            }
    }
}

struct AppLaunchScreenView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.tr("app.launching", fallback: "启动中…"))
                .foregroundStyle(.secondary)
        }
    }
}

struct SupportMainCoordinatorView: View {
    let session: UserSession
    let dependencies: AppCoordinatorDependencies

    @StateObject private var accountViewModel: AccountManagementViewModel
    @StateObject private var aiSettingsViewModel: AISettingsViewModel
    @StateObject private var upgradeLoginViewModel: LoginViewModel
    @State private var showsDeviceAccountUpgradeSheet = false
    @State private var selectedTab: SupportRootTab = .diaryEditor
    @State private var path = NavigationPath()

    init(session: UserSession, dependencies: AppCoordinatorDependencies) {
        self.session = session
        self.dependencies = dependencies
        _accountViewModel = StateObject(wrappedValue: dependencies.makeAccountManagementViewModel())
        _aiSettingsViewModel = StateObject(wrappedValue: dependencies.makeAISettingsViewModel(session.accountID))
        _upgradeLoginViewModel = StateObject(wrappedValue: dependencies.makeLoginViewModel())
    }

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $selectedTab) {
//                HomeDashboardView(
//                    session: session,
//                    authRepository: dependencies.authRepository
//                )
//                .tabItem {
//                    Label(L10n.tr("home.title", fallback: "首页"), systemImage: "house")
//                }
//                .tag(SupportRootTab.healthHome)
//
//                PhotoEditorHomeView()
//                    .tabItem {
//                        Label("照片编辑", systemImage: "photo.badge.pencil")
//                    }
//                    .tag(SupportRootTab.photoEditor)

                DiaryEditorHomeView(ownerID: String(session.accountID))
                    .id(session.accountID)
                    .tabItem {
                        Label("手帐", systemImage: "book.pages")
                    }
                    .tag(SupportRootTab.diaryEditor)

                NavigationStack {
                    DiaryPresetLibraryScreen(ownerID: String(session.accountID))
                }
                .id(session.accountID)
                .tabItem {
                    Label("预设", systemImage: "books.vertical")
                }
                .tag(SupportRootTab.diaryPresets)

//                SecondCameraHomeView()
//                    .tabItem {
//                        Label(SecondCameraEditorL10n.Home.tabTitle, systemImage: "camera.fill")
//                    }
//                    .tag(SupportRootTab.secondCamera)

                SettingsView(
                    accountManagementViewModel: accountViewModel,
                    aiSettingsViewModel: aiSettingsViewModel,
                    session: session,
                    onAccountEntryTap: handleAccountEntryTap
                )
                .tabItem {
                    Label(L10n.tr("tab.settings", fallback: "设置"), systemImage: "gearshape.fill")
                }
                .tag(SupportRootTab.settings)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { tabToolbar }
            .navigationDestination(for: AccountRoute.self) { _ in
                AccountManagementView(viewModel: accountViewModel, session: session)
            }
        }
        .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
            NavigationStack {
                LoginView(viewModel: upgradeLoginViewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.text("common.close", fallback: "关闭")) {
                                showsDeviceAccountUpgradeSheet = false
                            }
                        }
                    }
            }
        }
        .onChange(of: session.isDeviceAccount) { isDeviceAccount in
            if isDeviceAccount == false {
                showsDeviceAccountUpgradeSheet = false
            }
        }
    }

    @ToolbarContentBuilder
    private var tabToolbar: some ToolbarContent {
        switch selectedTab {
        case .healthHome:
            ToolbarItem(placement: .principal) {
                tabTitle(L10n.tr("home.title", fallback: "首页"))
            }
        case .photoEditor:
            ToolbarItem(placement: .principal) {
                tabTitle("照片编辑")
            }
        case .diaryEditor:
            ToolbarItem(placement: .principal) {
                tabTitle("我的")
            }
        case .diaryPresets:
            ToolbarItem(placement: .principal) {
                tabTitle("预设")
            }
        case .secondCamera:
            // The camera deliberately presents an immersive, navigation-bar-free surface.
            ToolbarItem(placement: .automatic) {
                EmptyView()
            }
        case .settings:
            ToolbarItem(placement: .principal) {
                tabTitle(L10n.text("settings.title", fallback: "设置"))
            }
        }
    }

    private func tabTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func handleAccountEntryTap() {
        if session.isDeviceAccount {
            showsDeviceAccountUpgradeSheet = true
        } else {
            path.append(AccountRoute.management)
        }
    }
}

private enum SupportRootTab: Hashable {
    case healthHome
    case photoEditor
    case diaryEditor
    case diaryPresets
    case secondCamera
    case settings
}

private enum AccountRoute: Hashable {
    case management
}

private struct HomeDashboardView: View {
    let session: UserSession
    let authRepository: AuthRepository

    var body: some View {
        Form {
            Section(L10n.tr("home.account", fallback: "账户")) {
                LabeledContent(L10n.tr("home.account_id", fallback: "账号 ID"), value: "\(session.accountID)")
                LabeledContent(
                    L10n.tr("home.sign_in_method", fallback: "登录方式"),
                    value: session.signInMethod.rawValue
                )
                if session.isDeviceAccount {
                    Text(L10n.text("settings.account.device_not_linked", fallback: "未登录"))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(role: .destructive) {
                    Task {
                        try? await authRepository.signOut()
                    }
                } label: {
                    Text(L10n.tr("home.logout", fallback: "退出登录"))
                }
            }
        }
    }
}
