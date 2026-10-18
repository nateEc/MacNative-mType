import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class WholePreviewPreparationHostTests: XCTestCase {
  @MainActor private final class Pending {
    var replies: [CheckedContinuation<Void, Never>] = []
    var calls = 0
    var cancelled = 0
    var fails = false
    var usesActualGenerator = false
    var actualPrompt: String?
    var preparedWordCount = 0
    var preparationStarted: TimeInterval?
    var lastBatchElapsed: TimeInterval?
    var preparationReturnedElapsed: TimeInterval?
    var preparationErrorType: String?
    enum Failure: Error { case expected }
    func prepare(_ configuration: TestConfiguration, _ scores: WeakSpotScores,
      _ state: PoolWordDecorationState) async throws -> TypingSession {
      calls += 1
      let number = calls
      if usesActualGenerator {
        let started = ProcessInfo.processInfo.systemUptime
        preparationStarted = started
        do {
          let prepared = try await WholePreviewWordPreparation.prepareSession(configuration: configuration,
            weakSpotScores: scores, wordDecorationState: state, nextRandomWordIndex: { 0 },
            didPrepare: { count in
              self.preparedWordCount = count
              self.lastBatchElapsed = ProcessInfo.processInfo.systemUptime - started
            })
          preparationReturnedElapsed = ProcessInfo.processInfo.systemUptime - started
          actualPrompt = prepared.prompt
          return prepared
        } catch {
          preparationErrorType = String(describing: type(of: error))
          throw error
        }
      }
      await withCheckedContinuation { replies.append($0) }
      if Task.isCancelled {
        cancelled += 1
        // Ignore cancellation deliberately, without allocating a giant test
        // fixture merely to prove its obsolete result cannot be published.
        return .init(configuration: configuration, prompt: "owned\(number)")
      }
      if fails { throw Failure.expected }
      // Deliberately return even when cancelled to exercise publication guards.
      return .init(configuration: configuration,
        prompt: Array(repeating: "owned\(number)", count: configuration.wordLimit ?? 0).joined(separator: " "),
        weakSpotScores: scores, wordDecorationState: state)
    }
    func finishFirst() {
      guard !replies.isEmpty else { return }
      replies.removeFirst().resume()
    }
    func finishAll() { while !replies.isEmpty { finishFirst() } }
  }

  func testPendingPreparationBlocksInputThenPublishesCompleteTarget() throws { try check(.publish) }
  func testRestartRejectsOldResultWhileReplacementIsPending() throws { try check(.restart) }
  func testTurningOffWholeDisplayCancelsPreparationWithoutLateReplacement() throws { try check(.displayOff) }
  func testRemovingHostCancelsPreparation() throws { try check(.leave) }
  func testFailureCanRestartWithoutLeavingInputBlocked() throws { try check(.failure) }
  func testRuleChangeReplacesPendingPreparation() throws { try check(.rules) }
  func testReturningToHostRestartsInterruptedPreparation() throws { try check(.resume) }
  func testTapeModeCancelsPendingWholePreparation() throws { try check(.tape) }
  func testActualGeneratorPublishesItsEntireTargetThroughHost() throws { try check(.actual) }
  func testNativeStreamPublishesExactTargetThroughProductionHost() throws {
    try check(.actual, modifiers: [.binaryStream])
  }
  func testAboveFormerCeilingPublishesCompleteActualTargetThroughHost() throws {
    try check(.actual, wordCount: 100_001)
  }
  func testLargestLegalPendingTargetCanLeaveWithoutPublishing() throws {
    try check(.leave, wordCount: OfficialTestLimitInput.maximumValue)
  }
  private enum Scenario { case publish, restart, displayOff, leave, failure, rules, resume, tape, actual }

  private func check(_ scenario: Scenario, wordCount: Int = 201, modifiers: [TestModifier] = [.noQuit]) throws {
    let suite = "WholePreviewPreparationHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.reducePracticeMotion = true
    settings.showAllPracticeLines = true
    settings.testModifiers = modifiers
    let configuration = TestConfiguration.words(wordCount).with(modifiers: modifiers)
    XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let pending = Pending()
    pending.usesActualGenerator = scenario == .actual
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      wholePreviewPrepare: pending.prepare).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    var layoutTotal: TimeInterval = 0
    var layoutMaximum: TimeInterval = 0
    var runLoopTotal: TimeInterval = 0
    var runLoopMaximum: TimeInterval = 0
    func flush() {
      let start = ProcessInfo.processInfo.systemUptime
      host.layoutSubtreeIfNeeded()
      let beforeRunLoop = ProcessInfo.processInfo.systemUptime
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      let afterRunLoop = ProcessInfo.processInfo.systemUptime
      host.layoutSubtreeIfNeeded()
      let end = ProcessInfo.processInfo.systemUptime
      let layout = beforeRunLoop - start + end - afterRunLoop
      let runLoop = afterRunLoop - beforeRunLoop
      layoutTotal += layout; layoutMaximum = max(layoutMaximum, layout)
      runLoopTotal += runLoop; runLoopMaximum = max(runLoopMaximum, runLoop)
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func target() -> String {
      views(PromptFieldNativeView.self, in: host).compactMap { $0.accessibilityValue() as? String }.joined()
    }
    defer {
      withExtendedLifetime(container) {
        pending.finishAll()
        host.rootView = AnyView(EmptyView())
        flush()
        window.contentView = nil
        window.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      }
    }
    for _ in 0..<10 where pending.calls == 0 { flush() }
    XCTAssertEqual(pending.calls, 1)
    if scenario == .actual {
      var flushCount = 0
      // The 100,001-word generator was still progressing at 99,700 words when
      // a fixed 200-flush wait expired on the macOS 15 runner. Wait for the
      // actual completion, with a finite wall-clock bound for a stalled task.
      let deadline = Date().addingTimeInterval(wordCount > 100_000 ? 90 : 20)
      while pending.actualPrompt == nil && Date() < deadline {
        flush()
        flushCount += 1
      }
      let elapsed = pending.preparationStarted.map { ProcessInfo.processInfo.systemUptime - $0 }
      let evidence = "words=\(wordCount) calls=\(pending.calls) flushes=\(flushCount) prepared=\(pending.preparedWordCount) elapsed=\(String(describing: elapsed)) lastBatch=\(String(describing: pending.lastBatchElapsed)) returned=\(String(describing: pending.preparationReturnedElapsed)) layoutTotal=\(layoutTotal) layoutMax=\(layoutMaximum) runLoopTotal=\(runLoopTotal) runLoopMax=\(runLoopMaximum) errorType=\(pending.preparationErrorType ?? "none")"
      print("whole preview preparation observation: \(evidence)")
      let actual = try XCTUnwrap(pending.actualPrompt, evidence)
      XCTAssertEqual(pending.preparedWordCount, wordCount)
      flush()
      XCTAssertEqual(actual.split(separator: " ").count, wordCount)
      XCTAssertEqual(target(), actual)
      return
    }
    XCTAssertEqual(pending.replies.count, 1)
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    input.insertText("x", replacementRange: .init(location: NSNotFound, length: 0))
    input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    XCTAssertFalse(input.hasMarkedText(), "Preparation must not retain a candidate for the next session")
    flush()
    XCTAssertTrue(settings.allowsRestartingConfigurationChange,
      "Pending preparation must not start a No Quit attempt")
    switch scenario {
    case .actual: XCTFail("Handled above")
    case .resume:
      window.contentView = nil
      flush()
      window.contentView = host
      for _ in 0..<10 where pending.calls < 2 { flush() }
      XCTAssertEqual(pending.calls, 2)
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      pending.finishFirst()
      flush()
      XCTAssertEqual(target(), Array(repeating: "owned2", count: 201).joined(separator: " "))
    case .tape:
      settings.practiceTapeMode = .word
      flush()
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      XCTAssertEqual(pending.calls, 1)
      XCTAssertFalse(target().contains("owned1"))
    case .rules:
      settings.freedomMode = true
      for _ in 0..<10 where pending.calls < 2 { flush() }
      XCTAssertEqual(pending.calls, 2)
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      pending.finishFirst()
      flush()
      XCTAssertEqual(target(), Array(repeating: "owned2", count: 201).joined(separator: " "))
    case .failure:
      pending.fails = true
      pending.finishFirst()
      flush()
      XCTAssertTrue(settings.allowsRestartingConfigurationChange)
      input.onRestart()
      for _ in 0..<10 where pending.calls < 2 { flush() }
      XCTAssertEqual(pending.calls, 2)
      pending.fails = false
      pending.finishFirst()
      flush()
      XCTAssertEqual(target(), Array(repeating: "owned2", count: 201).joined(separator: " "))
    case .leave:
      host.rootView = AnyView(EmptyView())
      flush()
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      XCTAssertTrue(views(TypingInputView.self, in: host).isEmpty)
    case .displayOff:
      settings.showAllPracticeLines = false
      flush()
      let bounded = target()
      XCTAssertFalse(bounded.isEmpty)
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      XCTAssertEqual(target(), bounded)
    case .restart:
      input.onRestart()
      for _ in 0..<10 where pending.calls < 2 { flush() }
      XCTAssertEqual(pending.calls, 2)
      pending.finishFirst()
      flush()
      XCTAssertEqual(pending.cancelled, 1)
      XCTAssertFalse(target().contains("owned1"))
      pending.finishFirst()
      flush()
      XCTAssertEqual(target(), Array(repeating: "owned2", count: 201).joined(separator: " "))
    case .publish:
      pending.finishFirst()
      flush()
      XCTAssertEqual(target(), Array(repeating: "owned1", count: 201).joined(separator: " "))
      let ready = try XCTUnwrap(views(TypingInputView.self, in: host).first)
      ready.onInsert("o", false)
      flush()
      XCTAssertFalse(settings.allowsRestartingConfigurationChange)
    }
  }
}
