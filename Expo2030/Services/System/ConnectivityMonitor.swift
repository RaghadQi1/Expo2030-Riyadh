import Foundation
import Network
import Observation

/// Real network reachability (NWPathMonitor) combined with the demo switch «محاكاة انقطاع الاتصال».
/// Screens use it for the offline banners (17.02 / 17.04) and to trigger a sync when the connection returns (17.06).
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isNetworkAvailable = true
    private let demo: DemoSettings
    private let monitor = NWPathMonitor()

    init(demo: DemoSettings = .shared) {
        self.demo = demo
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isNetworkAvailable = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "expo.connectivity"))
    }

    deinit { monitor.cancel() }

    var isOffline: Bool { !isNetworkAvailable || demo.simulateOffline }
}
