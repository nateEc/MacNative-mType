import Foundation
import XCTest
@testable import Typebar

@MainActor
final class BackgroundFailureFeedbackTests: XCTestCase {
  private func settle() async { for _ in 0..<40 { await Task.yield() } }

  func testDeliveryIsDeferredAndRepeatingOneImageDoesNotFlood() async {
    let feedback = BackgroundFailureFeedback(), identity = UUID()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: identity, sink: { kinds.append($0) })
    for _ in 0..<100 { feedback.report(.render, identity: identity) }
    XCTAssertTrue(kinds.isEmpty, "Do not mutate SwiftUI during a representable update")
    await settle()
    XCTAssertEqual(kinds, [.render])
    feedback.report(.playback, identity: identity); await settle()
    XCTAssertEqual(kinds, [.render])
  }

  func testReplacementCancellationAndSameIDABARejectOldQueue() async {
    let feedback = BackgroundFailureFeedback(), first = UUID(), second = UUID()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: first, sink: { kinds.append($0) })
    feedback.report(.remote, identity: first)
    feedback.begin(identity: second, sink: { kinds.append($0) })
    feedback.begin(identity: first, sink: { kinds.append($0) })
    await settle()
    XCTAssertTrue(kinds.isEmpty)
    feedback.report(.local, identity: first); feedback.cancel(); await settle()
    XCTAssertTrue(kinds.isEmpty)
    feedback.begin(identity: second, sink: { kinds.append($0) })
    feedback.report(.remote, identity: first)
    feedback.report(.resourceLimit, identity: second); await settle()
    XCTAssertEqual(kinds, [.resourceLimit])
  }

  func testLatestLiveCandidateReplacesRetiredSurfaceWithoutLosingItsNotice() async {
    let feedback = BackgroundFailureFeedback(), identity = UUID()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: identity, sink: { kinds.append($0) })
    feedback.report(.render, identity: identity, isCurrent: { false })
    feedback.report(.playback, identity: identity, isCurrent: { true })
    await settle()
    XCTAssertEqual(kinds, [.playback])
  }

  func testRecoveryBeforeDeliveryDoesNotConsumeFutureFailure() async {
    final class Status { var failed = true }
    let feedback = BackgroundFailureFeedback(), identity = UUID()
    let status = Status()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: identity, sink: { kinds.append($0) })
    feedback.report(.render, identity: identity, isCurrent: { status.failed })
    status.failed = false; await settle()
    XCTAssertTrue(kinds.isEmpty)
    status.failed = true
    feedback.report(.render, identity: identity, isCurrent: { status.failed }); await settle()
    XCTAssertEqual(kinds, [.render])
  }

  func testSinkCanReenterAndBeginANewImage() async {
    let feedback = BackgroundFailureFeedback(), first = UUID(), second = UUID()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: first, sink: { kind in
      kinds.append(kind)
      feedback.begin(identity: second, sink: { kinds.append($0) })
      feedback.report(.local, identity: second)
    })
    feedback.report(.remote, identity: first); await settle()
    XCTAssertEqual(kinds, [.remote, .local])
    feedback.cancel()
  }

  func testValidatorReentryCannotDeliverTheRetiredCandidate() async {
    let feedback = BackgroundFailureFeedback(), first = UUID(), next = UUID()
    var kinds: [BackgroundFailureFeedback.Kind] = []
    feedback.begin(identity: first, sink: { kinds.append($0) })
    feedback.report(.remote, identity: first, isCurrent: {
      feedback.begin(identity: next, sink: { kinds.append($0) })
      feedback.report(.local, identity: next)
      return true
    })
    await settle()
    XCTAssertEqual(kinds, [.local])
    feedback.cancel()
  }

  func testNoticeMatchesSourceLevelDurationAndDoesNotExposeDiagnostics() async throws {
    let center = LocalNoticeCenter(), feedback = BackgroundFailureFeedback(), identity = UUID()
    defer { center.clearAll(); feedback.cancel() }
    feedback.begin(identity: identity, sink: center.backgroundFailureSink())
    feedback.report(.remote, identity: identity); await settle()
    let notice = try XCTUnwrap(center.active.first)
    XCTAssertEqual(center.history.count, 1); XCTAssertEqual(notice.entry.level, .notice)
    XCTAssertEqual(notice.durationMilliseconds, 5000); XCTAssertFalse(notice.important)
    XCTAssertNil(notice.entry.details); XCTAssertFalse(notice.entry.containsHTML)
    XCTAssertEqual(notice.entry.message, BackgroundFailureFeedback.Kind.remote.message)
    XCTAssertFalse(notice.entry.message.contains("http"))
  }

  func testOldAccountSinkIsRetiredButNewScopeCanPost() async {
    let center = LocalNoticeCenter(), feedback = BackgroundFailureFeedback(), identity = UUID()
    defer { center.clearAll(); feedback.cancel() }
    feedback.begin(identity: identity, sink: center.backgroundFailureSink())
    feedback.report(.remote, identity: identity)
    let prior = center.deliveryGeneration
    center.clearForAccountChange()
    XCTAssertNotEqual(center.deliveryGeneration, prior)
    await settle(); XCTAssertTrue(center.history.isEmpty)
    let next = UUID()
    feedback.begin(identity: next, sink: center.backgroundFailureSink())
    feedback.report(.local, identity: next); await settle()
    XCTAssertEqual(center.history.map(\.message), [BackgroundFailureFeedback.Kind.local.message])
  }
}
