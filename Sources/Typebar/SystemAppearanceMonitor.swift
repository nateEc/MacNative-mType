import AppKit
import Observation
import SwiftUI

enum SystemAppearancePolicy {
  static func colorScheme(for appearance: NSAppearance) -> ColorScheme {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
}

/// Window-level theme previews must not become the source of the user's system
/// theme. Typebar leaves the application's appearance unset so it inherits macOS.
@MainActor
@Observable
final class SystemAppearanceMonitor {
  private(set) var colorScheme: ColorScheme
  @ObservationIgnored private let application: NSApplication
  @ObservationIgnored private var observation: NSKeyValueObservation?

  init(application: NSApplication = .shared) {
    self.application = application
    colorScheme = SystemAppearancePolicy.colorScheme(for: application.effectiveAppearance)
    observation = application.observe(\.effectiveAppearance) { [weak self] _, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        // Read the latest application state on the UI actor; queued callbacks
        // cannot restore an obsolete appearance after a newer system change.
        colorScheme = SystemAppearancePolicy.colorScheme(for: application.effectiveAppearance)
      }
    }
  }
}
