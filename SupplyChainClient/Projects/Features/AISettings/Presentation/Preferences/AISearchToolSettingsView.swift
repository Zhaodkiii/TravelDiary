import SwiftUI
#if canImport(UIKit)
import SafariServices
import UIKit
#endif

private struct SearchKeyEditorContext: Identifiable {
    let id: UUID
    var key: SearchKeys
    var isNew: Bool

    init(key: SearchKeys, isNew: Bool) {
        self.id = key.id
        self.key = key
        self.isNew = isNew
    }
}

private struct SearchHelpPage: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

/// AI 搜索工具设置页面
/// 管理搜索开关、结果数量、双语搜索、服务商配置等功能
struct AISearchToolSettingsView: View {
    /// 视图模型（观测数据变化）
    @ObservedObject var viewModel: AISettingsViewModel

    /// 搜索密钥编辑弹窗上下文（nil=不显示）
    @State private var editorContext: SearchKeyEditorContext?
    /// 错误提示信息
    @State private var errorMessage: String?

    /// 搜索工具偏好配置（从视图模型快照中获取）
    private var preferences: AISearchToolPreferences {
        viewModel.snapshot.searchToolPreferences
    }

    /// 所有搜索服务商密钥列表
    private var searchKeys: [SearchKeys] {
        viewModel.snapshot.searchKeys
    }

    /// 按名称排序后的搜索服务商列表
    private var sortedSearchKeys: [SearchKeys] {
        searchKeys.sorted {
            let lhs = displayName(for: $0)
            let rhs = displayName(for: $1)
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    // MARK: - 页面主体
    var body: some View {
        Form {
            // MARK: 顶部介绍区
            Section {
                VStack(alignment: .center, spacing: 10) {
                    // 搜索图标
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)
                        .padding(.top, 4)

                    // 功能介绍文本
                    Text(L10n.text("ai_settings.search.intro"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // MARK: 启用搜索开关
            Section(L10n.text("ai_settings.search.section.active_search")) {
                Toggle(L10n.text("ai_settings.field.use_search"), isOn: preferenceBinding(\.useSearch))
                    .tint(.blue)
            }

            // MARK: 搜索结果数量（5-20 步进调整）
            Section(L10n.text("ai_settings.search.section.result_count")) {
                Stepper(value: preferenceBinding(\.searchCount), in: 5...20) {
                    HStack {
                        Text(L10n.text("ai_settings.field.search_count"))
                        Spacer()
                        Text("\(preferences.searchCount)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: 双语搜索开关
            Section(L10n.text("ai_settings.search.section.bilingual")) {
                Toggle(L10n.text("ai_settings.field.bilingual_search"), isOn: preferenceBinding(\.bilingualSearch))
                    .tint(.blue)
            }

            // MARK: 搜索服务商列表（可删除、可编辑、可启用）
            Section(L10n.text("ai_settings.search.section.providers")) {
                if sortedSearchKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text("ai_settings.search.empty_providers"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            editorContext = SearchKeyEditorContext(key: makeBlankSearchKey(), isNew: true)
                        } label: {
                            Label(L10n.text("ai_settings.search.action.add_provider"), systemImage: "plus.circle")
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(sortedSearchKeys) { key in
                        searchEngineRow(for: key)
                    }
                    .onDelete(perform: deleteSearchKeys)
                }
            }

            // MARK: 搜索能力说明区
            Section(L10n.text("ai_settings.search.section.capabilities")) {
                Label(L10n.text("ai_settings.search.capability.web_search"), systemImage: "network")
                Label(L10n.text("ai_settings.search.capability.paper_search"), systemImage: "graduationcap")
                Label(L10n.text("ai_settings.search.capability.web_page_read"), systemImage: "text.and.command.macwindow")
                Label(L10n.text("ai_settings.search.capability.remote_file_read"), systemImage: "text.document")
            }
        }
        .navigationTitle(L10n.text("ai_settings.search.nav_title"))
        // 工具栏：添加新的搜索服务商
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    editorContext = SearchKeyEditorContext(key: makeBlankSearchKey(), isNew: true)
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        // 弹出编辑页面
        .sheet(item: $editorContext) { context in
            SearchKeyEditorView(
                initialKey: context.key,
                isNew: context.isNew,
                onSave: { key in
                    saveSearchKey(key)
                }
            )
        }
        // 错误提示弹窗
        .alert(L10n.text("common.notice"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { presented in
                if presented == false { errorMessage = nil }
            }
        )) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 搜索服务商列表行
    /// 单个搜索服务商的行视图（图标、名称、开关、编辑入口）
    private func searchEngineRow(for key: SearchKeys) -> some View {
        HStack(spacing: 12) {
            // 点击进入编辑
            Button {
                editorContext = SearchKeyEditorContext(key: key, isNew: false)
            } label: {
                HStack(spacing: 12) {
                    // 服务商图标
                    Image(companyIconName(for: key.company))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        // 显示名称 + 自定义标记
                        HStack(spacing: 6) {
                            Text(displayName(for: key))
                                .foregroundStyle(.primary)
                            if key.source == .custom {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // 服务商名称 + 价格提示
                        HStack(spacing: 8) {
                            Text(key.company.uppercased())
                            Text(priceHint(for: key.company))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // 是否配置了 API Key 图标提示
                    Image(systemName: hasAPIKey(key) ? "key.fill" : "key")
                        .foregroundStyle(hasAPIKey(key) ? .blue : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 单选激活：开启即切换当前激活项
            Toggle("", isOn: Binding(
                get: { key.isUsing },
                set: { enabled in
                    if enabled {
                        setActiveSearchProvider(id: key.id, enabled: true)
                    } else if key.isUsing {
                        setActiveSearchProvider(id: key.id, enabled: false)
                    }
                }
            ))
            .labelsHidden()
            .tint(.blue)
        }
    }

    // MARK: - 数据保存与更新
    /// 保存/更新搜索密钥（自动格式化字段）
    private func saveSearchKey(_ key: SearchKeys) {
        var next = key
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.company = next.company.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        next.key = next.key.trimmingCharacters(in: .whitespacesAndNewlines)
        next.requestURL = next.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        next.searchClass = next.searchClass.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "web" : next.searchClass
        next.timestamp = Date()
        next.revision += 1

        Task { @MainActor in
            if await viewModel.upsertSearchKeyAndPersist(next) {
                impact(.medium) // 震动反馈
            }
        }
    }

    /// 设置搜索服务商启用状态（单选激活，启用前校验凭证）
    private func setActiveSearchProvider(id: UUID, enabled: Bool) {
        guard let selected = searchKeys.first(where: { $0.id == id }) else { return }
        let provider = SearchProviderID(company: selected.company)
        if enabled {
            let spec = SearchProviderCatalog.fieldSpec(for: provider)
            if spec.requiresAPIKey, hasAPIKey(selected) == false {
                errorMessage = L10n.format("ai_settings.search.error.need_api_key_format", displayName(for: selected))
                return
            }
            if spec.requiresBaseURL,
               selected.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = L10n.text("ai_settings.search.error.need_base_url")
                return
            }
        }

        Task { @MainActor in
            if await viewModel.setSearchProviderEnabledAndPersist(id: id, enabled: enabled) {
                impact(.light)
            }
        }
    }

    /// 删除搜索服务商
    private func deleteSearchKeys(at offsets: IndexSet) {
        let ids = offsets.map { sortedSearchKeys[$0].id }
        Task { @MainActor in
            _ = await viewModel.deleteSearchKeysAndPersist(ids: ids)
        }
    }

    // MARK: - 工具方法
    /// 偏好设置双向绑定（通用封装）
    private func preferenceBinding<Value>(_ keyPath: WritableKeyPath<AISearchToolPreferences, Value>) -> Binding<Value> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { value in
                Task { @MainActor in
                    var next = viewModel.snapshot.searchToolPreferences
                    next[keyPath: keyPath] = value
                    _ = await viewModel.updateSearchToolPreferencesAndPersist(next)
                }
            }
        )
    }

    /// 创建空白的搜索密钥（用于新增）
    private func makeBlankSearchKey() -> SearchKeys {
        var key = SearchProviderCatalog.makeDefaultDuckDuckGoProfile()
        key.id = UUID()
        key.isUsing = searchKeys.contains(where: \.isUsing) == false
        key.source = .custom
        return key
    }

    /// 获取显示名称（优先名称，无则用公司名）
    private func displayName(for key: SearchKeys) -> String {
        let name = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        let company = key.company.trimmingCharacters(in: .whitespacesAndNewlines)
        return company.isEmpty ? L10n.text("ai_settings.search.provider.untitled") : company
    }

    /// 判断是否已配置 API Key
    private func hasAPIKey(_ key: SearchKeys) -> Bool {
        let provider = SearchProviderID(company: key.company)
        if SearchProviderCatalog.canActivateWithoutCredentials(provider: provider) {
            return true
        }
        if SearchProviderCatalog.requiresBaseURL(for: provider) {
            return key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// 根据服务商返回价格提示文本
    private func priceHint(for company: String) -> String {
        switch company.uppercased() {
        case "GOOGLE_SEARCH":
            return L10n.text("ai_settings.search.price.google")
        case "TAVILY":
            return L10n.text("ai_settings.search.price.tavily")
        case "LANGSEARCH":
            return L10n.text("ai_settings.search.price.free")
        case "BRAVE":
            return L10n.text("ai_settings.search.price.brave")
        case "SPARK":
            return L10n.text("ai_settings.search.price.spark")
        default:
            return L10n.text("ai_settings.search.price.provider")
        }
    }

    /// 系统震动反馈
    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

/// 搜索密钥配置编辑页面
/// 用于新增/编辑第三方搜索服务的API密钥、请求地址、优先级等配置
private struct SearchKeyEditorView: View {
    // MARK: - 环境与状态属性
    /// 页面关闭环境对象
    @Environment(\.dismiss) private var dismiss
    
    /// 当前编辑的搜索密钥模型
    @State private var key: SearchKeys
    /// 当前选中的 provider（驱动 Picker 与字段可见性）
    @State private var selectedProvider: SearchProviderID
    /// API测试结果（nil=未测试，true=成功，false=失败）
    @State private var testResult: Bool?
    /// 是否正在执行API测试
    @State private var isTesting = false
    /// 错误提示信息
    @State private var errorMessage: String?
    /// 帮助文档页面（Sheet弹出）
    @State private var helpPage: SearchHelpPage?

    // MARK: - 入参
    /// 是否为新增模式（false=编辑模式）
    let isNew: Bool
    /// 保存成功回调
    let onSave: (SearchKeys) -> Void

    // MARK: - 初始化
    /// 初始化方法
    /// - Parameters:
    ///   - initialKey: 初始搜索密钥模型
    ///   - isNew: 是否新增
    ///   - onSave: 保存回调
    init(initialKey: SearchKeys, isNew: Bool, onSave: @escaping (SearchKeys) -> Void) {
        let provider = SearchProviderID(company: initialKey.company)
        var normalized = initialKey
        if normalized.company.isEmpty {
            SearchProviderCatalog.applyDefaults(to: &normalized, provider: .duckduckgo)
        }
        _key = State(initialValue: normalized)
        _selectedProvider = State(initialValue: provider == .spark && normalized.company.isEmpty ? .duckduckgo : provider)
        self.isNew = isNew
        self.onSave = onSave
    }

    // MARK: - 页面主体
    var body: some View {
        CompatibleNavigationContainer {
            Form {
                // MARK: 顶部信息区（图标+说明+帮助链接）
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        // 服务商图标
                        Image(companyIconName(for: key.company))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 52, height: 52)
                            .padding(.top, 4)

                        // 页面说明文本
                        Text(L10n.format("ai_settings.search.editor.intro_format", displayName))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        // 帮助链接（有help地址则显示按钮，无则显示默认文本）
                        if let url = URL(string: key.help), key.help.isEmpty == false {
                            Button {
                                // 打开帮助文档Sheet
                                helpPage = SearchHelpPage(
                                    url: url,
                                    title: L10n.format("ai_settings.search.editor.help_title_format", displayName)
                                )
                            } label: {
                                Label(
                                    L10n.format("ai_settings.search.editor.help_link_format", displayName),
                                    systemImage: "safari"
                                )
                                .font(.footnote)
                            }
                        } else {
                            Text(L10n.text("ai_settings.search.editor.help_fallback"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                // MARK: 基础配置区
                Section(L10n.text("ai_settings.search.editor.section.basic")) {
                    TextField(L10n.text("common.name"), text: $key.name)

                    Picker(L10n.text("ai_settings.field.company"), selection: $selectedProvider) {
                        Section(L10n.text("ai_settings.search.editor.section.primary_providers")) {
                            ForEach(SearchProviderCatalog.primaryProviders, id: \.self) { provider in
                                Text(SearchProviderCatalog.displayName(for: provider))
                                    .tag(provider)
                            }
                        }
                        Section(L10n.text("ai_settings.search.editor.section.legacy_providers")) {
                            ForEach(SearchProviderCatalog.legacyProviders, id: \.self) { provider in
                                Text(SearchProviderCatalog.displayName(for: provider))
                                    .tag(provider)
                            }
                        }
                    }
                    .onChange(of: selectedProvider) { provider in
                        SearchProviderCatalog.applyDefaults(to: &key, provider: provider)
                    }

                    if fieldSpec.showsBaseURL {
                        TextField(
                            fieldSpec.requiresBaseURL
                                ? L10n.text("ai_settings.search.editor.field.base_url")
                                : L10n.text("ai_settings.endpoint"),
                            text: $key.requestURL
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    }

                    TextField(L10n.text("ai_settings.search.editor.field.help_link"), text: $key.help)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if fieldSpec.showsAPIKey {
                    // MARK: API密钥区
                    Section(L10n.text("ai_settings.search.editor.section.key")) {
                        SecureField(L10n.text("ai_settings.search.editor.field.key_placeholder"), text: $key.key)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                // MARK: 高级配置区
                Section(L10n.text("ai_settings.search.editor.section.advanced")) {
                    // 优先级调整（0-100）
                    Stepper(value: $key.priority, in: 0...100) {
                        HStack {
                            Text(L10n.text("ai_settings.search.editor.field.priority"))
                            Spacer()
                            Text("\(key.priority)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    // 启用开关
                    Toggle(L10n.text("ai_settings.field.enabled"), isOn: $key.isUsing)
                        .tint(.blue)
                }

                // MARK: API测试按钮区
                Section {
                    HStack {
                        Button(L10n.text("ai_settings.search.editor.action.test_api")) {
                            testAPI()
                        }
                        .disabled(isTesting || canTest == false)

                        Spacer()

                        // 测试中/测试结果展示
                        if isTesting {
                            ProgressView()
                        } else if let testResult {
                            Text(testResult ? L10n.text("ai_settings.search.editor.test.passed") : L10n.text("ai_settings.search.editor.test.failed"))
                                .foregroundStyle(testResult ? .green : .red)
                        }
                    }
                }

                // MARK: 错误信息展示
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                // MARK: 底部提示文本
                Section {
                    Text(L10n.text("ai_settings.search.editor.note"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            // 导航栏标题（新增/编辑）
            .navigationTitle(isNew ? L10n.text("ai_settings.search.editor.nav_add") : L10n.text("ai_settings.search.editor.nav_edit"))
            .navigationBarTitleDisplayMode(.inline)
            // 工具栏（取消 + 保存）
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.save")) {
                        guard validateForSave() else { return }
                        onSave(key)
                        dismiss()
                    }
                    .disabled(canSave == false)
                }
            }
            // 页面出现时重置测试状态
            .onAppear {
                testResult = nil
            }
            // 帮助文档页面（Sheet）
            .sheet(item: $helpPage) { page in
                SearchHelpWebSheet(page: page)
            }
        }
    }

    // MARK: - 计算属性
    /// 显示名称（优先取配置名称，无则取服务商名）
    private var displayName: String {
        let name = key.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        let company = key.company.trimmingCharacters(in: .whitespacesAndNewlines)
        return company.isEmpty ? L10n.text("ai_settings.search.provider.generic") : company
    }

    /// 当前 provider 的字段可见性规格
    private var fieldSpec: SearchProviderFieldSpec {
        SearchProviderCatalog.fieldSpec(for: selectedProvider)
    }

    /// 是否允许保存
    private var canSave: Bool {
        let nameOK = key.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let companyOK = key.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if fieldSpec.requiresBaseURL {
            return nameOK && companyOK && key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if fieldSpec.requiresAPIKey {
            return nameOK && companyOK
        }
        return nameOK && companyOK
    }

    /// 是否允许测试
    private var canTest: Bool {
        guard canSave else { return false }
        if fieldSpec.requiresAPIKey {
            return key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if fieldSpec.requiresBaseURL {
            return key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        return selectedProvider != .none
    }

    // MARK: - 业务方法
    /// 保存前校验
    /// - Returns: 校验通过返回true，失败返回false并设置错误信息
    private func validateForSave() -> Bool {
        SearchProviderCatalog.applyDefaults(to: &key, provider: selectedProvider)

        if fieldSpec.requiresBaseURL {
            let endpoint = key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") else {
                errorMessage = L10n.text("ai_settings.search.error.endpoint_scheme")
                return false
            }
        } else if fieldSpec.showsBaseURL {
            let endpoint = key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if endpoint.isEmpty == false,
               endpoint.hasPrefix("http://") == false,
               endpoint.hasPrefix("https://") == false {
                errorMessage = L10n.text("ai_settings.search.error.endpoint_scheme")
                return false
            }
        }

        if key.isUsing {
            if fieldSpec.requiresAPIKey,
               key.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = L10n.format("ai_settings.search.error.need_api_key_format", displayName)
                return false
            }
            if fieldSpec.requiresBaseURL,
               key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = L10n.text("ai_settings.search.error.need_base_url")
                return false
            }
        }

        errorMessage = nil
        return true
    }

    /// 测试API连通性
    private func testAPI() {
        guard validateForSave() else { return }
        isTesting = true
        testResult = nil

        let endpointString = key.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackURL = SearchProviderCatalog.defaultRequestURL(for: selectedProvider)
        let rawURLString = endpointString.isEmpty ? fallbackURL : endpointString
        let url: URL
        if selectedProvider == .duckduckgo,
           let rawURL = URL(string: rawURLString) {
            url = DuckDuckGoHTMLParser.searchEndpoint(from: rawURL)
        } else {
            guard let parsed = URL(string: rawURLString) else { return }
            url = parsed
        }

        let config = SearchRuntimeConfig(
            provider: selectedProvider,
            displayName: displayName,
            apiKey: key.key.trimmingCharacters(in: .whitespacesAndNewlines),
            requestURL: url,
            searchCount: 3,
            bilingualSearch: false,
            revision: SearchRuntimeConfigRevision(),
            rawKeyID: key.id
        )

        // 异步执行搜索测试
        Task {
            do {
                let response = try await WebSearchGateway().search(query: "SparkClient", config: config)
                // 主线程更新UI
                await MainActor.run {
                    testResult = response.items.isEmpty == false
                    isTesting = false
                }
            } catch {
                // 测试失败，展示错误
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    testResult = false
                    isTesting = false
                }
            }
        }
    }
}

private struct SearchHelpWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    let page: SearchHelpPage

    var body: some View {
        CompatibleNavigationContainer {
#if canImport(UIKit)
            SearchHelpSafariView(url: page.url)
                .ignoresSafeArea(edges: .bottom)
#else
            Text(page.url.absoluteString)
                .font(.footnote)
                .foregroundStyle(.secondary)
#endif
        }
        .navigationTitle(page.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.text("common.close")) {
                    dismiss()
                }
            }
        }
    }
}

#if canImport(UIKit)
private struct SearchHelpSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif
