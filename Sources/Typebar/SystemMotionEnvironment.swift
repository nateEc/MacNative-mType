import SwiftUI

/// Nil preserves SwiftUI's live system accessibility preference. Tests can
/// select a motion state without changing the runner's global preference.
private struct TypebarSystemReduceMotionOverrideKey: EnvironmentKey {
  static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
  var typebarSystemReduceMotionOverride: Bool? {
    get { self[TypebarSystemReduceMotionOverrideKey.self] }
    set { self[TypebarSystemReduceMotionOverrideKey.self] = newValue }
  }
}
