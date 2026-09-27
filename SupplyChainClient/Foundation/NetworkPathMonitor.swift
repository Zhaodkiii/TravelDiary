import Combine
import Foundation
import Network

@MainActor
final class NetworkPathMonitor: ObservableObject {
    @Published private(set) var hasEvaluatedPath = false
    @Published private(set) var isSatisfied = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "supportclient.network.path")
    private var didStart = false

    func start() {
        guard didStart == false else { return }
        didStart = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.hasEvaluatedPath = true
                self?.isSatisfied = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}

