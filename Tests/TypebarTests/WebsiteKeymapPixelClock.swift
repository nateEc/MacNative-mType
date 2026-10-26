import AppKit
import XCTest
@testable import Typebar

@MainActor final class WebsiteKeymapPixelClock {
  struct Sample { let plan: WebsiteKeymapAnimationState.Plan; let progress: Double }
  var time: TimeInterval = 0
  var samples: [Sample] = []
  var waits: [TimeInterval] = []
  var environment: WebsiteKeymapAnimationClock {
    .init(now: { self.time }, didSample: { self.samples.append(.init(plan: $0, progress: $1)) },
      didWait: { self.waits.append($0) })
  }
  func wait(_ host: NSView, until ready: () -> Bool,
    file: StaticString = #filePath, line: UInt = #line) async throws {
    for _ in 0..<200 {
      host.layoutSubtreeIfNeeded()
      if ready() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("Keymap did not publish the requested logical frame", file: file, line: line)
  }
}
