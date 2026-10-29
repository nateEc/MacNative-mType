import SwiftData
import XCTest
@testable import Typebar

/// Retain the store while cancelled SwiftUI work releases page callbacks.
/// RunLoop pumping alone does not let all MainActor tasks finish retirement.
@MainActor enum PracticeHostLifetime {
  static func withModelContainer(
    file: StaticString = #filePath, line: UInt = #line,
    _ body: @MainActor (ModelContainer, (AnyObject) -> Void) async throws -> Void
  ) async throws {
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    weak var callbacks: AnyObject?
    let result: Result<Void, Error>
    do {
      try await body(container, { callbacks = $0 })
      result = .success(())
    } catch {
      result = .failure(error)
    }
    let deadline = Date().addingTimeInterval(1)
    while callbacks != nil && Date() < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
    XCTAssertNil(callbacks, "Practice callbacks outlived their model container scope", file: file, line: line)
    withExtendedLifetime(container) {}
    try result.get()
  }
}

@MainActor final class PracticeHostLifetimeTests: XCTestCase {
  private final class CallbackOwner {}
  private enum Failure: Error { case owned }

  func testSuccessfulBodyKeepsStoreAliveUntilQueuedCallbacksRelease() async throws {
    try await verify(throwsError: false)
  }

  func testThrowingBodyRetiresCallbacksBeforePropagatingItsOriginalError() async throws {
    try await verify(throwsError: true)
  }

  private func verify(throwsError: Bool) async throws {
    var completed = false
    weak var owner: CallbackOwner?
    do {
      try await PracticeHostLifetime.withModelContainer { container, track in
        let callbacks = CallbackOwner(); owner = callbacks; track(callbacks)
        Task { @MainActor [callbacks, weak container] in
          await Task.yield()
          XCTAssertNotNil(container)
          completed = true
          withExtendedLifetime(callbacks) {}
        }
        if throwsError { throw Failure.owned }
      }
      XCTAssertFalse(throwsError)
    } catch Failure.owned {
      XCTAssertTrue(throwsError)
    }
    XCTAssertTrue(completed)
    XCTAssertNil(owner)
  }
}
