import SwiftUI

struct AppCoordinatorView: View {
    let dependencies: AppCoordinatorDependencies
    private let onEntryReady: (Bool) -> Void
    @State private var authEntryReady = false
    @State private var homeReadyAccountID: Int64?
    @StateObject private var networkMonitor = NetworkPathMonitor()
    @StateObject private var lifecycle: AppLifecycleCoordinator

    init(dependencies: AppCoordinatorDependencies, onEntryReady: @escaping (Bool) -> Void = { _ in }) {
        self.dependencies = dependencies
        self.onEntryReady = onEntryReady
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
        .onChange(of: entryReady, initial: true) { _, ready in onEntryReady(ready) }
        .onChange(of: lifecycle.sessionState, initial: true) { _, state in
            if case .signedIn = state {
                // 恢复已有账号也算已进入过应用，退出登录后不再自动创建游客会话。
                InitialGuestEntryPolicy().markExistingSession()
            }
        }
    }

    private var entryReady: Bool {
        if networkMonitor.hasEvaluatedPath, !networkMonitor.isSatisfied { return true }
        switch lifecycle.sessionState {
        case .loading: return false
        case .signedOut: return authEntryReady
        case .signedIn(let session):
            return lifecycle.preparationFailed || (lifecycle.preparedAccountID == session.accountID
                && homeReadyAccountID == session.accountID)
        }
    }

    @ViewBuilder
    private var sessionContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-diary-ai-book8") { DiaryAIBook8DebugScreen() }
        else { regularSessionContent }
        #else
        regularSessionContent
        #endif
    }

    @ViewBuilder
    private var regularSessionContent: some View {
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
            SignedOutAuthCoordinatorView(dependencies: dependencies, onEntryReady: { authEntryReady = $0 })
        case .signedIn(let session):
            AppPreparationTransition(isReady: lifecycle.preparedAccountID == session.accountID,
                failed: lifecycle.preparationFailed,
                onRetry: { Task { await lifecycle.retrySignedInPreparation() } }) {
                    SupportMainCoordinatorView(session: session, dependencies: dependencies,
                                               onHomeReady: { homeReadyAccountID = session.accountID })
                }.id(session.accountID)
        }
    }
}

private struct SignedOutAuthCoordinatorView: View {
    let dependencies: AppCoordinatorDependencies
    let onEntryReady: (Bool) -> Void
    @StateObject private var viewModel: LoginViewModel
    @State private var showsLogin: Bool

    init(dependencies: AppCoordinatorDependencies, onEntryReady: @escaping (Bool) -> Void) {
        self.dependencies = dependencies
        self.onEntryReady = onEntryReady
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
        .onChange(of: showsLogin, initial: true) { _, visible in onEntryReady(visible) }
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
    var onHomeReady: () -> Void

    @StateObject private var accountViewModel: AccountManagementViewModel
    @StateObject private var upgradeLoginViewModel: LoginViewModel
    @State private var showsDeviceAccountUpgradeSheet = false
    @State private var showsCreateDiaryBookForm = false
    @State private var showsCustomizationSettings = false
    @State private var materialToolbar = DiaryMaterialToolbarState()
    @State private var materialSearchQuery = ""
    @ObservedObject private var helpFeedback = HelpFeedbackService.shared
    @ObservedObject private var customizations = CustomizationService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: SupportRootTab = .diaryEditor
    @Namespace private var bookshelfTransition
    @State private var path = NavigationPath()
    @State private var stylePresentation: TravelStyleEditorPresentation?
    @State private var preparedReaderBook: DiaryBook?

    init(session: UserSession, dependencies: AppCoordinatorDependencies, onHomeReady: @escaping () -> Void = {}) {
        self.session = session
        self.dependencies = dependencies
        self.onHomeReady = onHomeReady
        _accountViewModel = StateObject(wrappedValue: dependencies.makeAccountManagementViewModel())
        _upgradeLoginViewModel = StateObject(wrappedValue: dependencies.makeLoginViewModel())
    }

    var body: some View {
        rootNavigation(path: $path) {
            tabContent
                .navigationTitle(currentTabTitle)
                .toolbar { tabToolbar }
                #if DEBUG
                .modifier(DiaryDebugImport(ownerID: String(session.accountID),
                    showsButton: selectedTab == .diaryEditor && path.isEmpty,
                    completed: {
                        NotificationCenter.default.post(name: Notification.Name("DiaryDebugImportCompleted"), object: nil)
                    }))
                #endif
        }
        .fullScreenCover(item: $stylePresentation) { presentation in
            DiaryEditorScreen(session: presentation.session, creationRequest: presentation.request,
                onNewPage: presentation.newPage,
                discardEmptyDraft: { try await presentation.coordinator.discardIfEmpty(presentation.session) },
                onFinished: { try await openPublishedPage(presentation.coordinator.draft) })
                .id(presentation.id)
        }
        .environment(\.accountLoginContext, AccountLoginContext(
            isDeviceAccount: session.isDeviceAccount, viewModel: upgradeLoginViewModel))
        .tabViewSearchActivation(.searchTabSelection)
        .task(id: helpFeedback.routeID) {
            guard let id = helpFeedback.routeID else { return }
            selectedTab = .settings
            do {
                _ = try await helpFeedback.ticket(id, owner: String(session.accountID))
                path = NavigationPath([SupportRoute(id: id)])
            } catch { helpFeedback.routeError = "此反馈在当前账号下不可访问，请确认登录账号后重试。" }
            helpFeedback.routeID = nil; UserDefaults.standard.removeObject(forKey: "support-push-pending-v1")
        }
        .alert("帮助与反馈", isPresented: Binding(get: { helpFeedback.routeError != nil }, set: { if !$0 { helpFeedback.routeError = nil } })) { Button("好") { helpFeedback.routeError = nil } } message: { Text(helpFeedback.routeError ?? "") }
        .task(id: customizations.routeID) {
            guard let id = customizations.routeID else { return }
            do {
                _ = try await customizations.detail(id, owner: String(session.accountID))
                customizations.routeError = nil
                selectedTab = .customization
                path = NavigationPath([CustomizationRoute(id: id)])
            } catch { selectedTab = .customization; customizations.routeError = "此内容在当前账号下不可用，或已被移除。" }
            customizations.routeID = nil; PushAdapter.shared.routeConsumed()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { PresetImportStatisticsReporter.shared.wake(); Task { await PushAdapter.shared.refreshRegistration(); await customizations.refreshUnread(owner: String(session.accountID)); await helpFeedback.refreshUnread(owner: String(session.accountID)) } }
        }
        .sheet(isPresented: $showsCustomizationSettings) {
            CustomizationNotificationSettingsView(owner: String(session.accountID))
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

    private func openPublishedPage(_ draft: CreationDraft) async throws {
        guard draft.publishedDigest != nil else { return }
        guard draft.owner == String(session.accountID), let bookID = draft.targetBookID else {
            throw DiaryEditorError.invalidDocument
        }
        let store = DiaryDocumentStore(ownerID: draft.owner, bookID: bookID)
        let book = try await store.loadBook()
        guard let page = book.contentPages.first(where: { $0.id == draft.documentID }) else {
            throw DiaryAIError.invalid("找不到刚保存的页面，请重试。")
        }
        _ = try await DiaryPreviewService.image(page: page, store: store, large: true)
        try Task.checkCancellation()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            preparedReaderBook = book
            selectedTab = .diaryEditor
            path = NavigationPath([DiaryBookRoute(bookID: bookID, pageID: page.id)])
        }
    }

    /// TabView is the shared stack's root. Pushed pages replace the entire tab
    /// container, so the tab bar needs no visibility modifiers.
    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            Tab("随记", systemImage: "sparkles", value: SupportRootTab.travelCapture) {
                TravelCaptureHomeView(ownerID: String(session.accountID)) { stylePresentation = $0 }
                    .id(session.accountID)
            }

            Tab("手帐", systemImage: "book.pages", value: SupportRootTab.diaryEditor) {
                DiaryEditorHomeView(ownerID: String(session.accountID), path: $path,
                    creating: $showsCreateDiaryBookForm, bookTransition: bookshelfTransition,
                    onBrowseTemplates: { selectedTab = .diaryPresets }, onInitialLoad: onHomeReady)
                    .id(session.accountID)
            }

            Tab("素材", systemImage: "books.vertical", value: SupportRootTab.diaryPresets) {
                DiaryPresetLibraryScreen(ownerID: String(session.accountID), toolbarState: materialToolbar)
                    .id(session.accountID)
            }
//            Tab("定制", systemImage: "sparkles", value: SupportRootTab.customization) {
//                CustomizationHomeView(owner: String(session.accountID))
//                    .id(session.accountID)
//            }.badge(customizations.unread)
            Tab(L10n.tr("tab.settings", fallback: "设置"), systemImage: "gearshape", value: SupportRootTab.settings) {
                SettingsView(accountManagementViewModel: accountViewModel,
                    session: session,
                    storageService: dependencies.storageService, onAccountEntryTap: handleAccountEntryTap)
                    .id(session.accountID)
            }
        }
    }

    /// Register typed routes at the shared stack root, independent of the
    /// selected tab, so notifications can open their destination immediately.
    private func rootNavigation<Content: View>(path: Binding<NavigationPath>, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: DiaryBookRoute.self) { route in
                    DiaryBookDestination(ownerID: String(session.accountID), bookID: route.bookID, pageID: route.pageID, managePages: route.managePages, preparedBook: route.pageID == nil ? nil : preparedReaderBook)
                        .id(route.bookID)
                        .contentZoomTransition(sourceID: route.bookID, in: route.zoomFromShelf ? bookshelfTransition : nil)
                }
                .navigationDestination(for: CustomizationRoute.self) { route in
                    CustomizationDetailView(id: route.id, owner: String(session.accountID))
                        .id("\(session.accountID):\(route.id)")
                }
                .navigationDestination(for: SupportRoute.self) { route in
                    FeedbackDetailScreen(id: route.id, owner: String(session.accountID))
                }
                .navigationDestination(for: AccountRoute.self) { _ in
                    AccountManagementView(viewModel: accountViewModel, session: session)
                }
        }
    }

    private var currentTabTitle: String {
        switch selectedTab {
        case .healthHome: return L10n.tr("home.title", fallback: "首页")
        case .photoEditor: return "照片编辑"
        case .travelCapture: return "旅行随记"
        case .diaryEditor: return "我的手帐"
        case .diaryPresets: return "旅行素材"
        case .templateSearch: return "搜索模板"
        case .customization: return "免费定制"
        case .secondCamera: return ""
        case .settings: return L10n.text("settings.title", fallback: "设置")
        }
    }
    @ToolbarContentBuilder
    private var tabToolbar: some ToolbarContent {
        switch selectedTab {
        case .diaryEditor:
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsCreateDiaryBookForm = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建手帐本")
            }
        case .diaryPresets:
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    materialSearchDestination
                } label: { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("搜索\(materialToolbar.category.rawValue)")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if materialToolbar.category.contentKind != nil {
                    Button { materialToolbar.requestFilters() } label: {
                        Image(systemName: materialToolbar.hasActiveFilters
                            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    }.accessibilityLabel("筛选\(materialToolbar.category.rawValue)")
                }
                Menu("我的素材", systemImage: "tray") {
                    NavigationLink { PresetDownloadCenter(ownerID: String(session.accountID)) } label: {
                        Label("模板下载", systemImage: "arrow.down.circle")
                    }
                    NavigationLink { StickerGalleryScreen(mine: true) } label: {
                        Label("贴纸收藏", systemImage: "heart")
                    }
                    NavigationLink { FontGalleryScreen(mine: true) } label: {
                        Label("我的字体", systemImage: "textformat")
                    }
                }
            }
        case .customization:
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsCustomizationSettings = true } label: { Image(systemName: "bell") }
                    .accessibilityLabel("定制提醒设置")
            }
        default:
            // Settings and the inactive tabs have no root toolbar actions.
            ToolbarItemGroup(placement: .topBarTrailing) { }
        }
    }

    @ViewBuilder
    private var materialSearchDestination: some View {
        switch materialToolbar.category {
        case .stickers:
            StickerGalleryScreen(isSearchPage: true)
        case .fonts:
            FontGalleryScreen()
        case .templates, .albums:
            DiaryPresetSearchScreen(ownerID: String(session.accountID), searchText: $materialSearchQuery,
                initialCatalog: materialToolbar.catalog,
                contentKind: materialToolbar.category.contentKind ?? "journal")
        }
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
    case travelCapture
    case diaryPresets
    case templateSearch
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
