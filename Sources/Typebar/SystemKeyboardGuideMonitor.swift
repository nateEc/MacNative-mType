import Carbon
import Foundation
import Observation

/// Invalidates the system-backed keyboard guide when macOS changes the
/// selected keyboard input source. It deliberately holds no input state and
/// never participates in AppKit text interpretation.
@MainActor
@Observable
final class SystemKeyboardGuideMonitor {
  static let selectedInputSourceChanged = Notification.Name(
    kTISNotifySelectedKeyboardInputSourceChanged as String)

  @ObservationIgnored private var observer: NSObjectProtocol?
  private(set) var revision = 0

  init(observesInputSourceChanges: Bool = true) {
    guard observesInputSourceChanges else { return }
    observer = DistributedNotificationCenter.default().addObserver(
      forName: Self.selectedInputSourceChanged, object: nil, queue: .main
    ) { [weak self] notification in
      let notificationName = notification.name.rawValue
      Task { @MainActor in
        self?.receive(notificationName: notificationName)
      }
    }
  }

  func receive(notificationName: String) {
    guard notificationName == Self.selectedInputSourceChanged.rawValue else { return }
    revision &+= 1
  }
}
