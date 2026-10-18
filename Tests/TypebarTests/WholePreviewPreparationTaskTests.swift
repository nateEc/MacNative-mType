import XCTest
@testable import Typebar

@MainActor final class WholePreviewPreparationTaskTests: XCTestCase {
  @MainActor private final class Gate {
    var pending: CheckedContinuation<TypingSession, Error>?
    var started: CheckedContinuation<Void, Never>?

    func prepare() async throws -> TypingSession {
      try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        started?.resume()
        started = nil
      }
    }

    func waitUntilStarted() async {
      if pending != nil { return }
      await withCheckedContinuation { started = $0 }
    }

    func finish(_ result: sending Result<TypingSession, Error>) {
      let continuation = pending
      pending = nil
      continuation?.resume(with: result)
    }
  }

  private enum Failure: Error { case expected }
  private struct PreparedSnapshot {
    let session: TypingSession
    let rendering: PromptRendering
  }
  @MainActor private final class PresentationGate {
    var pending: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?
    func prepare() async {
      await withCheckedContinuation { continuation in
        pending = continuation
        started?.resume()
        started = nil
      }
    }
    func waitUntilStarted() async {
      if pending != nil { return }
      await withCheckedContinuation { started = $0 }
    }
    func finish() { pending?.resume(); pending = nil }
  }
  private func session(_ text: String) -> sending TypingSession {
    .init(configuration: .words(1), prompt: text)
  }

  func testRepeatedStartsRegisterAndResumeGateOnOneActor() async {
    let owner = WholePreviewPreparationTask()
    var completions = 0
    for _ in 0..<200 {
      let gate = Gate()
      let task = owner.start(operation: { try await gate.prepare() }) { _ in completions += 1 }
      await gate.waitUntilStarted()
      gate.finish(.success(session("owned")))
      await task.value
    }
    XCTAssertEqual(completions, 200)
    XCTAssertFalse(owner.isPreparing)
  }

  func testOwnerCanBeReleasedWhileUncooperativePreparationIsSuspended() async {
    var owner: WholePreviewPreparationTask? = .init()
    weak var released = owner
    let gate = Gate()
    var published = false
    let task = owner!.start(operation: { try await gate.prepare() }) { _ in published = true }
    await gate.waitUntilStarted()
    owner = nil
    XCTAssertNil(released)
    gate.finish(.success(session("obsolete")))
    await task.value
    XCTAssertFalse(published)
  }

  func testDirectTaskCancellationAlsoClearsCurrentLoadingState() async {
    let owner = WholePreviewPreparationTask()
    let gate = Gate()
    var published = false
    let task = owner.start(operation: { try await gate.prepare() }) { _ in published = true }
    await gate.waitUntilStarted()
    task.cancel()
    gate.finish(.success(session("cancelled")))
    await task.value
    XCTAssertFalse(owner.isPreparing)
    XCTAssertFalse(published)
  }

  func testActualHugePreparationCancelsWithoutPublishingPartialSession() async {
    let owner = WholePreviewPreparationTask()
    var counts: [Int] = []
    var published = false
    let task = owner.start(operation: {
      try await WholePreviewWordPreparation.prepareSession(
        configuration: .words(OfficialTestLimitInput.maximumValue, language: .codeSwift),
        sourceWords: ["north"], nextRandomWordIndex: { 0 }, didPrepare: {
          counts.append($0)
          owner.cancel()
        })
    }) { _ in published = true }
    await task.value
    XCTAssertEqual(counts, [100])
    XCTAssertFalse(published)
    XCTAssertFalse(owner.isPreparing)
  }

  func testCancellationRejectsEvenAnOperationThatIgnoresCancellation() async {
    let owner = WholePreviewPreparationTask()
    let gate = Gate()
    var published = false
    let task = owner.start(operation: { try await gate.prepare() }) { _ in published = true }
    await gate.waitUntilStarted()
    XCTAssertTrue(owner.isPreparing)
    owner.cancel()
    XCTAssertFalse(owner.isPreparing)
    gate.finish(.success(session("old")))
    await task.value
    XCTAssertFalse(published)
  }

  func testOldSuccessAndFailureCannotPublishOrClearReplacement() async {
    for oldFails in [false, true] {
      let owner = WholePreviewPreparationTask()
      let old = Gate(), replacement = Gate()
      var published: [String] = []
      let first = owner.start(operation: { try await old.prepare() }) { _ in published.append("old") }
      await old.waitUntilStarted()
      let second = owner.start(operation: { try await replacement.prepare() }) { result in
        XCTAssertFalse(owner.isPreparing)
        published.append((try? result.get().prompt) ?? "failure")
      }
      await replacement.waitUntilStarted()
      old.finish(oldFails ? .failure(Failure.expected) : .success(session("old")))
      await first.value
      XCTAssertTrue(owner.isPreparing)
      XCTAssertTrue(published.isEmpty)
      replacement.finish(.success(session("new")))
      await second.value
      XCTAssertEqual(published, ["new"])
      XCTAssertFalse(owner.isPreparing)
    }
  }

  func testCurrentFailureFinishesBeforeCallbackAndCanStartReplacement() async {
    let owner = WholePreviewPreparationTask()
    let replacement = Gate()
    var deliveredFailure = false
    var nextTask: Task<Void, Never>?
    let first = owner.start(operation: { throw Failure.expected }) { result in
      XCTAssertFalse(owner.isPreparing)
      if case .failure(Failure.expected) = result { deliveredFailure = true }
      nextTask = owner.start(operation: { try await replacement.prepare() }) { _ in }
    }
    await first.value
    await replacement.waitUntilStarted()
    XCTAssertTrue(deliveredFailure)
    XCTAssertTrue(owner.isPreparing)
    replacement.finish(.success(session("new")))
    await nextTask?.value
    XCTAssertFalse(owner.isPreparing)
  }

  func testWholeSessionAndRenderingSnapshotShareOnePublicationTicket() async {
    for oldFails in [false, true] {
      let owner = WholePreviewPreparationTask()
      let oldRendering = PresentationGate()
      var published: [String] = []
      let first = owner.start(operation: {
        let prepared = self.session("old")
        await oldRendering.prepare()
        if oldFails { throw Failure.expected }
        return PreparedSnapshot(session: prepared,
          rendering: .init(text: AttributedString("old-ink"), glyphCharacterOffsets: [:]))
      }) { result in
        if let value = try? result.get() {
          published.append("\(value.session.prompt):\(String(value.rendering.text.characters))")
        }
      }
      await oldRendering.waitUntilStarted()
      XCTAssertTrue(owner.isPreparing)
      let second = owner.start(operation: {
        PreparedSnapshot(session: self.session("new"),
          rendering: .init(text: AttributedString("new-ink"), glyphCharacterOffsets: [:]))
      }) { result in
        if let value = try? result.get() {
          published.append("\(value.session.prompt):\(String(value.rendering.text.characters))")
        }
      }
      await second.value
      oldRendering.finish()
      await first.value
      XCTAssertEqual(published, ["new:new-ink"])
      XCTAssertFalse(owner.isPreparing)
    }
  }
}
