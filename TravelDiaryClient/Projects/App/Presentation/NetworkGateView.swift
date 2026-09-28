import SwiftUI
import UIKit

struct NetworkGateView: View {
    @ObservedObject var monitor: NetworkPathMonitor
    @State private var isRetrying = false
    @State private var showRetryError = false
    @State private var retryErrorMessage = ""

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "wifi.slash")
                    .font(.system(size: 80))
                    .foregroundColor(.secondary)

                VStack(spacing: 16) {
                    Text(L10n.text("network.gate.title"))
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Text(L10n.text("network.gate.subtitle"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if monitor.isSatisfied {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundColor(.secondary)
                        Text(L10n.text("network.gate.detected"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()

                VStack(spacing: 16) {
                    Button(action: { checkConnectivity() }) {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.text("network.gate.check"))
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.primary)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRetrying || monitor.isSatisfied == false)

                    Button(action: openSettings) {
                        Text(L10n.text("network.gate.settings"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .alert(L10n.text("network.gate.alert_title"), isPresented: $showRetryError) {
            Button(L10n.text("common.ok"), role: .cancel) {}
        } message: {
            Text(retryErrorMessage)
        }
    }

    private func checkConnectivity() {
        isRetrying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isRetrying = false
            if monitor.isSatisfied == false {
                retryErrorMessage = L10n.text("network.gate.retry_failed")
                showRetryError = true
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
