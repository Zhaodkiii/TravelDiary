import Combine
import SwiftUI
import Testing
import UIKit
@testable import TravelDiary

@MainActor
struct CustomCameraSessionOwnershipTests {
    @Test func parentRefreshKeepsSessionAndReceivesAuthorizationCompletion() async throws {
        let probe = SessionProbe()
        let host = UIHostingController(rootView: RefreshingCameraParent(probe: probe))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }

        try await waitForSnapshot(0, probe: probe)
        let original = try #require(probe.candidates.first)
        let initial = try #require(probe.snapshots[0])
        #expect(!initial.controlsEnabled)

        // Simulate the parent refresh caused by the permission dialog / diary save.
        probe.revision = 1
        try await waitForSnapshot(1, probe: probe)
        #expect(probe.candidates.count >= 2)
        #expect(probe.snapshots[1]?.storeID == initial.storeID)

        // Authorization finishes on the original manager after the parent refreshed.
        original.attributes.sessionState = .running
        original.attributes.isSessionReady = true
        probe.revision = 2
        try await waitForSnapshot(2, probe: probe)
        #expect(probe.snapshots[2]?.storeID == initial.storeID)
        #expect(probe.snapshots[2]?.controlsEnabled == true)
    }

    private func waitForSnapshot(_ revision: Int, probe: SessionProbe) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while probe.snapshots[revision] == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(probe.snapshots[revision] != nil)
    }
}

@MainActor
private final class SessionProbe: ObservableObject {
    struct Snapshot {
        let storeID: ObjectIdentifier
        let controlsEnabled: Bool
    }

    @Published var revision = 0
    var candidates: [CustomCameraManager] = []
    var snapshots: [Int: Snapshot] = [:]

    func makeCamera(revision: Int) -> some View {
        let manager = CustomCameraManager(captureSession: MockCaptureSession(), captureDeviceInputType: MockDeviceInput.self)
        manager.attributes.sessionState = .starting
        // Use the preview branch to exercise ownership without requesting hardware permissions.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        manager.presentCapturedMedia(CustomCameraMedia(data: image)!)
        candidates.append(manager)
        return CustomCameraView(manager: manager)
            .setCapturedMediaScreen { context in
                SessionProbePreview(context: context, revision: revision) { revision, store, namespace in
                    guard let activeManager = self.candidates.first(where: { $0.attributes.multiCaptureStore === store }) else { return }
                    let screen = DefaultCustomCameraScreen(cameraManager: activeManager, namespace: namespace, closeCustomCameraAction: {})
                    self.snapshots[revision] = Snapshot(storeID: ObjectIdentifier(store), controlsEnabled: screen.isCameraControlsEnabled)
                }
            }
            .startSession()
    }
}

private struct RefreshingCameraParent: View {
    @ObservedObject var probe: SessionProbe

    var body: some View {
        probe.makeCamera(revision: probe.revision)
    }
}

private struct SessionProbePreview: CustomCapturedMediaScreen {
    let context: SecondCameraCapturedMediaContext
    let revision: Int
    let record: (Int, SecondCameraMultiCaptureStore, Namespace.ID) -> Void

    var previewStore: SecondCameraMultiCaptureStore { context.store }
    var namespace: Namespace.ID { context.namespace }
    var discardAction: () -> Void { context.discardAction }
    var continueCaptureAction: () -> Void { context.continueCaptureAction }
    var acceptMediaAction: () -> Void { context.acceptMediaAction }

    var body: some View {
        Color.black.task(id: revision) { record(revision, previewStore, namespace) }
    }
}
