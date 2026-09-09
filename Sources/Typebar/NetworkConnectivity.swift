import Foundation
import Network
import Observation

enum NetworkConnectivityStatus: Equatable, Sendable {
  case checking
  case online
  case offline
}

enum NetworkConnectivityEvent: Equatable, Sendable {
  case restored
}

/// Keeps the observable transition contract independent from `NWPathMonitor`
/// so initial discovery and repeated callbacks cannot masquerade as recovery.
struct NetworkConnectivityState: Equatable, Sendable {
  private(set) var status: NetworkConnectivityStatus = .checking

  var showsOfflineBanner: Bool { status == .offline }

  mutating func observe(
    _ observedStatus: NetworkConnectivityStatus
  ) -> NetworkConnectivityEvent? {
    guard observedStatus != .checking else { return nil }
    let previousStatus = status
    status = observedStatus
    return previousStatus == .offline && observedStatus == .online ? .restored : nil
  }
}

/// Owns the app's single passive macOS network-path observer. It does not poll
/// a server or infer that a reachable network means a Typebar service is healthy.
@MainActor
@Observable
final class NetworkConnectivityMonitor {
  private(set) var state = NetworkConnectivityState()
  private(set) var recoveryEventID = 0

  private let monitor: NWPathMonitor
  private let queue = DispatchQueue(label: "app.typebar.network-connectivity")

  init(monitor: NWPathMonitor = NWPathMonitor()) {
    self.monitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      let status: NetworkConnectivityStatus = path.status == .satisfied ? .online : .offline
      Task { @MainActor [weak self] in
        self?.receive(status)
      }
    }
    monitor.start(queue: queue)
  }

  deinit {
    monitor.cancel()
  }

  var status: NetworkConnectivityStatus { state.status }
  var showsOfflineBanner: Bool { state.showsOfflineBanner }

  private func receive(_ status: NetworkConnectivityStatus) {
    if state.observe(status) == .restored {
      recoveryEventID &+= 1
    }
  }
}
