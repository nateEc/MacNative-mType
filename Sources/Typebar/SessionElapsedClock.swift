import Foundation

/// Owned process-local measurement source. Origins and instants never enter
/// a result, archive, service request, or user-visible calendar date.
struct SessionElapsedClock {
  let now: () -> TimeInterval

  static var system: Self {
    let clock = SuspendingClock()
    let origin = clock.now
    return .init {
      let value = origin.duration(to: clock.now).components
      return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
  }
}
