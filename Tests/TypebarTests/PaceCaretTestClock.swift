import Foundation
@testable import Typebar

/// Owned monotonic samples; Date is only a shorthand in historical fixtures.
final class PaceCaretTestClock {
  var time: TimeInterval = 0
  var source: PaceCaretClock { .init { self.time } }

  func set(at date: Date) {
    time = date.timeIntervalSince1970 - 1_800_000_000
  }
}

extension PaceCaretProgress {
  mutating func start(at date: Date, blind: Bool) {
    start(at: date.timeIntervalSinceReferenceDate, blind: blind)
  }

  mutating func advance(to date: Date, blind: Bool) {
    advance(to: date.timeIntervalSinceReferenceDate, blind: blind)
  }

  func frame(at date: Date, blind: Bool) -> PaceCaretFrame? {
    frame(at: date.timeIntervalSinceReferenceDate, blind: blind)
  }
}
