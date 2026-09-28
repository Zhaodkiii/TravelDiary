import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct AITrialSettingsView: View {
    @ObservedObject var viewModel: AISettingsViewModel

    @State private var trialPrivacyAccepted = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var hasLoadedTrialStatus = false

    private var isSignedIn: Bool {
        true
    }

    private var snapshot: AISettingsSnapshot {
        viewModel.snapshot
    }

    private var trialProviders: [APIKeys] {
        guard snapshot.trial.isActive else { return [] }
        let endpoints = Set(snapshot.trialModelPolicy.map { $0.config.endpoint.lowercased() })
        let list = snapshot.apiKeys.filter { provider in
            endpoints.contains(provider.requestURL.lowercased())
        }
        let grouped = Dictionary(grouping: list, by: \.providerID)
        return grouped.values.compactMap { $0.first }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        Group {
            Section {
                trialEntryCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            if snapshot.trial.isActive, trialProviders.isEmpty == false {
                Section(L10n.text("ai_settings.providers.section.trial_providers")) {
                    ForEach(trialProviders) { provider in
                        HStack(spacing: 12) {
                            Image(companyIconName(for: provider.company))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text(provider.localizedDisplayName)
                                .font(.body)
                            Spacer()
                            Text(L10n.text("ai_settings.providers.badge.trial"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.text("ai_settings.providers.trial_providers.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert(L10n.text("ai_settings.providers.editor.alert.notice_title"), isPresented: $showErrorAlert) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            guard hasLoadedTrialStatus == false else { return }
            hasLoadedTrialStatus = true
            await viewModel.refreshTrialStatus()
        }
    }

    private var trialEntryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "key.radiowaves.forward.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("ai_settings.providers.trial.card.title"))
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(L10n.text("ai_settings.providers.trial.card.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                statusLabel
                if !snapshot.trial.isActive {
                    trialConsentArea
                    trialActionButton
                }
         
            }

            modelBadges
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private var statusLabel: some View {
        Group {
            switch snapshot.trial.status {
            case "active":
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(L10n.text("ai_settings.providers.trial.status.active"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if snapshot.trial.remainingSeconds > 0 {
                        Text(L10n.format("ai_settings.providers.trial.status.remaining_days", daysRemaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            case "pending":
                Label(L10n.text("ai_settings.providers.trial.status.pending"), systemImage: "clock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            case "rejected":
                Label(L10n.text("ai_settings.providers.trial.status.rejected"), systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            case "expired":
                Label(L10n.text("ai_settings.providers.trial.status.expired"), systemImage: "hourglass.bottomhalf.filled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            default:
                Label(L10n.text("ai_settings.providers.trial.status.default"), systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var daysRemaining: Int {
        max(Int(ceil(Double(snapshot.trial.remainingSeconds) / 86_400.0)), 0)
    }

    private var trialConsentArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("ai_settings.providers.trial.consent.hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Toggle(isOn: $trialPrivacyAccepted) {
                Text(L10n.text("ai_settings.providers.trial.consent.toggle"))
                    .font(.footnote)
            }
            .tint(.accentColor)
        }
    }

    private var trialActionButton: some View {
        Button {
            guard trialPrivacyAccepted else {
                showError(L10n.text("ai_settings.providers.trial.error.need_consent"))
                return
            }
            Task {
                let ok = await viewModel.submitTrialApplication()
                if ok {
                    impact(.medium)
                } else if let message = viewModel.errorMessage, message.isEmpty == false {
                    showError(message)
                } else {
                    showError(L10n.text("common.error", fallback: "操作失败"))
                }
            }
        } label: {
            HStack {
                if viewModel.trialOperationInFlight {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
                Text(trialButtonTitle)
                    .font(.body)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.trialOperationInFlight || !isSignedIn)
    }

    private var trialButtonTitle: String {
        switch snapshot.trial.status {
        case "active": return L10n.text("ai_settings.providers.trial.action.active")
        case "pending": return L10n.text("ai_settings.providers.trial.action.pending")
        case "rejected", "expired": return L10n.text("ai_settings.providers.trial.action.reapply")
        default: return L10n.text("ai_settings.providers.trial.action.apply")
        }
    }

    private var modelBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["OpenAI", "Gemini", "Claude", "DeepSeek", "GLM"], id: \.self) { title in
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemBackground), in: Capsule())
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}
