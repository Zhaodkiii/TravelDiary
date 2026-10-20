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
        .onChange(of: lifecycle.sessionState, initial: true) { _, state in
            if case .signedIn = state {
                // 恢复已有账号也算已进入过应用，退出登录后不再自动创建游客会话。
                InitialGuestEntryPolicy().markExistingSession()
            }
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
            AppPreparationTransition(isReady: lifecycle.preparedAccountID == session.accountID,
                failed: lifecycle.preparationFailed,
                onRetry: { Task { await lifecycle.retrySignedInPreparation() } }) {
                    SupportMainCoordinatorView(session: session, dependencies: dependencies)
                }.id(session.accountID)
        }
    }
}

private struct SignedOutAuthCoordinatorView: View {
    let dependencies: AppCoordinatorDependencies
    @StateObject private var viewModel: LoginViewModel
    @State private var showsLogin: Bool

    init(dependencies: AppCoordinatorDependencies) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: dependencies.makeLoginViewModel())
        // 在构造登录页之前确定入口；后续退出登录直接展示登录页。
        _showsLogin = State(initialValue: !InitialGuestEntryPolicy().canAttemptAutomaticEntry)
    }

    var body: some View {
        Group {
            if showsLogin {
                LoginView(viewModel: viewModel, presentsInitialLegalPromptOnAppear: false)
            } else {
                AppLaunchScreenView()
            }
        }
        .task {
            await dependencies.lifecycle.handleSignedOutTask()
            guard !Task.isCancelled else { return }
            let authenticated = await viewModel.signInWithDeviceAutomaticallyIfNeeded()
            guard !Task.isCancelled else { return }
            // 成功后继续显示启动画面，直到根路由切到账号准备/书架；失败才创建登录页。
            if !authenticated { showsLogin = true }
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
    @State private var showsCreateDiaryBookForm = false
    @ObservedObject private var customizations = CustomizationService.shared
    @Environment(\.scenePhase) private var scenePhase
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

                DiaryEditorHomeView(ownerID: String(session.accountID), path: $path, creating: $showsCreateDiaryBookForm, onBrowseTemplates: { selectedTab = .diaryPresets })
                    .id(session.accountID)
                    .tabItem {
                        Label("手帐", systemImage: "book.pages")
                    }
                    .tag(SupportRootTab.diaryEditor)

                DiaryPresetLibraryScreen(ownerID: String(session.accountID))
                    .id(session.accountID)
                .tabItem {
                    Label("模板", systemImage: "books.vertical")
                }
                .tag(SupportRootTab.diaryPresets)

//                SecondCameraHomeView()
//                    .tabItem {
//                        Label(SecondCameraEditorL10n.Home.tabTitle, systemImage: "camera.fill")
//                    }
//                    .tag(SupportRootTab.secondCamera)

                CustomizationHomeView(owner: String(session.accountID))
                    .id(session.accountID)
                    .tabItem { Label("定制", systemImage: "sparkles") }
                    .badge(customizations.unread)
                    .tag(SupportRootTab.customization)

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
            // Keep the root toolbar installed while a destination is pushed. The
            // navigation stack scopes each screen's toolbar; removing these items
            // during a push can leave the root navigation bar empty after a pop.
            .toolbar { tabToolbar }
            // 路由在 TabView 外注册，所有标签中的链接都能由根导航栈解析。
            .navigationDestination(for: DiaryBookRoute.self) { route in
                DiaryBookDestination(ownerID: String(session.accountID), bookID: route.bookID, managePages: route.managePages)
                    .id(route.bookID)
            }
            .navigationDestination(for: CustomizationRoute.self) { route in
                CustomizationDetailView(id: route.id, owner: String(session.accountID))
                    .id("\(session.accountID):\(route.id)")
                    .id("\(session.accountID)-\(route.id)")
            }
            .navigationDestination(for: AccountRoute.self) { _ in
                AccountManagementView(viewModel: accountViewModel, session: session)
            }
        }
        .task(id: customizations.routeID) {
            guard let id = customizations.routeID else { return }
            do {
                _ = try await customizations.detail(id, owner: String(session.accountID))
                customizations.routeError = nil
                selectedTab = .customization
                path = NavigationPath(); path.append(CustomizationRoute(id: id))
            } catch { selectedTab = .customization; customizations.routeError = "此内容在当前账号下不可用，或已被移除。" }
            customizations.routeID = nil; PushAdapter.shared.routeConsumed()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await PushAdapter.shared.refreshRegistration(); await customizations.refreshUnread(owner: String(session.accountID)) } }
        }
        .sheet(isPresented: $showsDeviceAccountUpgradeSheet) {
            LoginView(viewModel: upgradeLoginViewModel, mode: .upgradeDeviceAccount)
        }
        .onChange(of: session.isDeviceAccount) { isDeviceAccount in
            if isDeviceAccount == false {
                showsDeviceAccountUpgradeSheet = false
            }
        }
    }

    private var currentTabTitle: String {
        switch selectedTab {
        case .healthHome: return L10n.tr("home.title", fallback: "首页")
        case .photoEditor: return "照片编辑"
        case .diaryEditor: return "我的手帐"
        case .diaryPresets: return "旅行模板"
        case .customization: return "专属定制"
        case .secondCamera: return ""
        case .settings: return L10n.text("settings.title", fallback: "设置")
        }
    }
    @ToolbarContentBuilder
    private var tabToolbar: some ToolbarContent {
        if selectedTab != .secondCamera {
            ToolbarItem(placement: .principal) { tabTitle(currentTabTitle) }
        }
        if selectedTab == .diaryEditor {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsCreateDiaryBookForm = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建手帐本")
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
    case customization
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
