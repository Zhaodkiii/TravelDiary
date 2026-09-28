import SwiftUI
#if canImport(UIKit)
import UIKit
import SafariServices
#endif

private enum ProviderSettingsSheet: Identifiable {
    case manageModels
    case privacyPolicy(URL)

    var id: String {
        switch self {
        case .manageModels:
            return "manageModels"
        case .privacyPolicy(let url):
            return "privacyPolicy-\(url.absoluteString)"
        }
    }
}

/// 服务商配置编辑页面
/// 用于配置 AI 服务商的 API Key、请求地址、模型管理、连接测试等
struct ProviderSettingsEditorView: View {
    /// 页面关闭环境变量
    @Environment(\.dismiss) private var dismiss

    /// 当前编辑的服务商配置模型
    @State var provider: APIKeys
    /// 配置视图模型
    @ObservedObject var viewModel: AISettingsViewModel

    /// 是否正在测试 API
    @State private var isTesting = false
    /// API 测试结果（nil=未测试，true=成功，false=失败）
    @State private var testPassed: Bool?
    /// 测试错误信息
    @State private var testErrorMessage: String?
    /// 选中用于测试的模型名称
    @State private var selectedTestModelName = ""
    /// 弹出的子页面（模型管理）
    @State private var presentedSheet: ProviderSettingsSheet?
    /// 是否显示提示弹窗
    @State private var showNoticeAlert = false
    /// 提示弹窗内容
    @State private var noticeMessage = ""
    
    /// 模型连通性探测服务
    private let probeService = ClientModelCapabilityProbeService()

    /// 当前服务商下的所有模型（过滤、排序）
    private var providerModels: [AllModels] {
        return viewModel.snapshot.allModels
            .filter { $0.identity == .model } // 只保留模型
            .filter { $0.providerID == provider.providerID } // 属于当前服务商
            .sorted { $0.position < $1.position } // 按位置排序
    }

    /// 可用于测试的模型（支持文本生成 + 已启用）
    private var testableModels: [AllModels] {
        providerModels
            .filter(\.supportsTextGen)
            .filter(\.isEnabled)
    }

    // MARK: - 页面主体
    var body: some View {
        Form {
            // MARK: 服务商基础配置区
            Section {
                Toggle(isOn: providerEnabledBinding) {
                    Text(L10n.text(provider.localizedDisplayName))
                }
                .tint(.accentColor)
                // API 请求地址输入框
                TextField(L10n.text("ai_settings.providers.editor.field.request_url"), text: $provider.requestURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                // API Key 加密输入框
                SecureField(L10n.text("ai_settings.providers.editor.field.api_key"), text: $provider.key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                if provider.privacyPolicyURL.isEmpty == false {
                    if let url = URL(string: provider.privacyPolicyURL) {
                        Button {
                            presentedSheet = .privacyPolicy(url)
                        } label: {
                            Text(L10n.text("ai_settings.providers.editor.privacy.view_policy"))
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle(isOn: $provider.privacyPolicyAccepted) {
                        Text(L10n.text("ai_settings.providers.editor.privacy.accept"))
                            .font(.footnote)
                    }
                    .tint(.accentColor)
                }
            }

            // MARK: 模型列表区
            Section {
                if providerModels.isEmpty {
                    Text(L10n.text("ai_settings.providers.editor.models.empty"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(providerModels) { model in
                        ModelsSettingsMainRow(
                            model: model,
                            viewModel: viewModel,
                            isEditing: false,
                            priceLabel: ModelsSettingsRowChrome.priceTierLabel(model.priceTier),
                            priceColor: ModelsSettingsRowChrome.priceTierColor(model.priceTier),
                            onDelete: {
                                deleteModel(modelID: model.id)
                            },
                            showsInfoButton: true,
                            showsLeadingSwipeAction: true
                        )
                    }
                }
            } header: {
                HStack {
                    Text(L10n.text("ai_settings.providers.editor.section.models"))
                    Spacer()
                    // 添加模型按钮 → 打开模型管理页
                    Button {
                        presentedSheet = .manageModels
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: API 连接测试区
            Section(L10n.text("ai_settings.providers.editor.section.api_test")) {
                // 测试模型选择器（有可测试模型时显示）
                if testableModels.isEmpty == false {
                    Picker(L10n.text("ai_settings.providers.editor.field.test_model"), selection: $selectedTestModelName) {
                        ForEach(testableModels) { model in
                            Text(model.displayName)
                                .tag(model.name)
                        }
                    }
                }

                HStack {
                    // 测试按钮
                    Button(L10n.text("ai_settings.providers.editor.action.test_api")) {
                        Task {
                            await testProvider()
                        }
                    }
                    .disabled(isTesting || testableModels.isEmpty)

                    Spacer()
                    
                    // 测试状态显示：加载中 / 成功/失败文本
                    if isTesting {
                        ProgressView()
                    } else if let passed = testPassed {
                        Text(L10n.text(passed ? "ai_settings.providers.editor.test.passed" : "ai_settings.providers.editor.test.failed"))
                            .foregroundStyle(passed ? .green : .red)
                    } else if testableModels.isEmpty {
                        Text(L10n.text("ai_settings.providers.editor.test.no_models"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 测试错误提示
                if let testErrorMessage, testErrorMessage.isEmpty == false {
                    Text(testErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(L10n.text("ai_settings.providers.editor.nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        // 导航栏保存按钮
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("common.save")) {
                    // 未同意隐私政策则无法保存
                    if provider.privacyPolicyURL.isEmpty == false, provider.privacyPolicyAccepted == false {
                        return
                    }
                    saveProvider()
                }
                .disabled(provider.privacyPolicyURL.isEmpty == false && provider.privacyPolicyAccepted == false)
            }
        }
        // 弹出模型管理页面
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .manageModels:
                ModelManagementView(provider: provider, viewModel: viewModel)
            case .privacyPolicy(let url):
                ProviderPrivacyPolicyWebSheet(url: url)
            }
        }
        // 通用提示弹窗
        .alert(L10n.text("ai_settings.providers.editor.alert.notice_title"), isPresented: $showNoticeAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(noticeMessage)
        }
        .onAppear {
            applyDefaultPrivacyPolicyAcceptanceIfNeeded()
            syncSelectedTestModel()
        }
        // 可测试模型变化时重新同步
        .onChange(of: testableModels) { _ in
            syncSelectedTestModel()
        }
    }

    // MARK: - 业务方法

    private var providerEnabledBinding: Binding<Bool> {
        Binding(
            get: { provider.isHidden == false },
            set: { enabled in
                setProviderEnabled(enabled)
            }
        )
    }

    private func setProviderEnabled(_ enabled: Bool) {
        if enabled {
            let key = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                showNotice(L10n.text("ai_settings.providers.editor.alert.need_api_key"))
                return
            }
        }

        var draft = provider
        draft.isHidden = !enabled
        provider.isHidden = !enabled

        Task {
            let ok = await viewModel.setProviderEnabledFromEditorAndPersist(draft, enabled: enabled)
            if ok {
                if let updated = viewModel.snapshot.apiKeys.first(where: { $0.id == provider.id }) {
                    provider.isHidden = updated.isHidden
                }
                impact(.light)
            } else {
                if let updated = viewModel.snapshot.apiKeys.first(where: { $0.id == provider.id }) {
                    provider.isHidden = updated.isHidden
                }
                if let message = viewModel.errorMessage {
                    showNotice(message)
                }
            }
        }
    }

    private func applyDefaultPrivacyPolicyAcceptanceIfNeeded() {
        guard provider.privacyPolicyURL.isEmpty == false else { return }
        guard provider.privacyPolicyAcceptedAt == nil else { return }
        provider.privacyPolicyAccepted = true
    }

    /// 删除指定模型
    private func deleteModel(modelID: UUID) {
        impact(.light)
        Task {
            let ok = await viewModel.deleteModelAndPersist(id: modelID)
            if ok == false, let message = viewModel.errorMessage {
                showNotice(message)
            }
        }
    }

    /// 保存服务商配置并关闭页面
    private func saveProvider() {
        if provider.isHidden == false {
            let key = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                showNotice(L10n.text("ai_settings.providers.editor.alert.need_api_key"))
                return
            }
        }
        impact(.medium)
        Task {
            _ = await viewModel.saveProviderFromEditorAndPersist(provider)
        }
        dismiss()
    }

    /// 测试服务商 API 连通性（核心方法）
    private func testProvider() async {
        let key = provider.key.trimmingCharacters(in: .whitespacesAndNewlines)
        // 校验 API Key 不能为空
        guard key.isEmpty == false else {
            showNotice(L10n.text("ai_settings.providers.editor.alert.need_api_key"))
            testPassed = false
            return
        }
        // 校验必须选择测试模型
        guard let modelName = resolvedTestModelName else {
            let message = L10n.text("ai_settings.providers.editor.alert.no_models")
            testPassed = false
            testErrorMessage = message
            showNotice(message)
            return
        }

        // 开始测试
        isTesting = true
        testErrorMessage = nil
        defer { isTesting = false } // 确保结束后重置状态

        // 先调用后端测试接口
        let backendResult = await viewModel.testProviderConnection(
            requestURL: provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: key,
            model: modelName
        )
        if backendResult.isReachable {
            testPassed = true
            testErrorMessage = nil
            impact(.medium)
            return
        }

        // 后端测试网络错误时，尝试本地直连测试
        if backendResult.message?.lowercased() == "network_error" {
            do {
                var localProvider = provider
                localProvider.key = key
                localProvider.requestURL = provider.requestURL.trimmingCharacters(in: .whitespacesAndNewlines)
                try await probeService.testConnection(modelName: modelName, provider: localProvider)
                testPassed = true
                testErrorMessage = nil
                impact(.medium)
                return
            } catch {
                let message = error.localizedDescription
                testPassed = false
                testErrorMessage = message
                showNotice(message)
                return
            }
        }

        // 测试失败，显示错误信息
        let message = backendFailureMessage(rawMessage: backendResult.message)
        testPassed = false
        testErrorMessage = message
        showNotice(message)
    }

    /// 获取最终用于测试的模型名称（自动兜底）
    private var resolvedTestModelName: String? {
        if testableModels.contains(where: { $0.name == selectedTestModelName }) {
            return selectedTestModelName
        }
        return testableModels.first?.name
    }

    /// 同步选中的测试模型（确保有效）
    private func syncSelectedTestModel() {
        guard let modelName = resolvedTestModelName else {
            selectedTestModelName = ""
            return
        }
        if selectedTestModelName != modelName {
            selectedTestModelName = modelName
        }
    }

    /// 格式化后端返回的错误信息
    private func backendFailureMessage(rawMessage: String?) -> String {
        let trimmed = rawMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.isEmpty == false else {
            return L10n.text("ai_settings.providers.editor.alert.test_failed")
        }
        switch trimmed.lowercased() {
        case "network_error":
            return L10n.text("ai_settings.providers.editor.alert.backend_network_error")
        default:
            return trimmed
        }
    }

    /// 显示提示弹窗
    private func showNotice(_ message: String) {
        noticeMessage = message
        showNoticeAlert = true
    }

    /// 触发系统震动反馈
    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

extension APIKeys {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        return company
    }

    var localizedDisplayName: String {
        if source == .custom {
            return displayName
        }
        let key = "company_\(company.uppercased())"
        let localized = L10n.text(key)
        return localized == key ? displayName : localized
    }
}
