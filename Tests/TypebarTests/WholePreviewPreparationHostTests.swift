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
  func testFirstInputPublishesFreshFieldInkAndCaretThroughHost() throws {
    try check(.actualFirstInput)
  }
  func testFirstInputThenMarkedTextFontChangeAndSecondKeyKeepCurrentInkAndCaret() throws {
    try check(.actualInterleavings)
  }
  func testAboveFormerCeilingAcceptsFirstInputThroughHost() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TYPEBAR_ENDURANCE_TESTS"] == "1",
      "Run explicitly with TYPEBAR_ENDURANCE_TESTS=1")
    try check(.actualFirstInput, wordCount: 100_001)
  }
  func testLargestLegalPendingTargetCanLeaveWithoutPublishing() throws {
    try check(.leave, wordCount: OfficialTestLimitInput.maximumValue)
  }

  func testRenderStageKeepsInputLockedAndStyleChangeRendersSameCandidateAgain() throws {
    let suite = "WholePreviewRenderingHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.showAllPracticeLines = true
    settings.testModifiers = [.noQuit]
    let configuration = TestConfiguration.words(201).with(modifiers: [.noQuit])
    XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let expected = Array(repeating: "staged", count: 201).joined(separator: " ")
    var generationCalls = 0
    var renderCalls = 0
    var pendingRenders: [CheckedContinuation<Void, Never>] = []
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      wholePreviewPrepare: { configuration, _, _ in
        generationCalls += 1
        return TypingSession(configuration: configuration, prompt: expected)
      }, wholePreviewRender: { candidate, style in
        renderCalls += 1
        await withCheckedContinuation { pendingRenders.append($0) }
        return try await PromptRenderPlan(session: candidate, composition: "", style: style).renderCooperatively()
      }).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func target() -> String {
      views(PromptFieldNativeView.self, in: host).compactMap { $0.accessibilityValue() as? String }.joined()
    }
    defer {
      for continuation in pendingRenders { continuation.resume() }
      host.rootView = AnyView(EmptyView())
      flush()
      window.contentView = nil
      window.close()
      withExtendedLifetime(container) {}
    }
    for _ in 0..<30 where pendingRenders.isEmpty { flush() }
    XCTAssertEqual(generationCalls, 1)
    XCTAssertEqual(renderCalls, 1)
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    input.insertText("x", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertFalse(target().contains("staged"))
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    settings.fontSize = 36
    flush()
    pendingRenders.removeFirst().resume()
    for _ in 0..<30 where renderCalls < 2 { flush() }
    XCTAssertEqual(generationCalls, 1)
    XCTAssertEqual(renderCalls, 2)
    XCTAssertFalse(target().contains("staged"))
    input.insertText("x", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    pendingRenders.removeFirst().resume()
    for _ in 0..<30 where target() != expected { flush() }
    XCTAssertEqual(target(), expected)
    XCTAssertEqual(generationCalls, 1)
    input.onInsert("s", false)
    XCTAssertFalse(settings.allowsRestartingConfigurationChange,
      "The actual first input must lock No Quit before its callback returns")
    flush()
    XCTAssertFalse(settings.allowsRestartingConfigurationChange)
  }

  func testGeometryStageKeepsInputLockedAndRejectsOldFontWithoutRegenerating() throws {
    let suite = "WholePreviewGeometryHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.showAllPracticeLines = true
    settings.testModifiers = [.noQuit]
    let configuration = TestConfiguration.words(6_001).with(modifiers: [.noQuit])
    XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let expected = Array(repeating: "staged", count: 6_001).joined(separator: " ")
    var generationCalls = 0, layoutCalls = 0
    var pendingLayouts: [CheckedContinuation<Void, Never>] = []
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      wholePreviewPrepare: { configuration, _, _ in
        generationCalls += 1
        return TypingSession(configuration: configuration, prompt: expected)
      }, wholePreviewLayout: { map, width, font, spacing, rtl, joins in
        layoutCalls += 1
        await withCheckedContinuation { pendingLayouts.append($0) }
        return try await PromptFieldTextLayout.makeCooperatively(map: map, width: width,
          font: font, lineSpacing: spacing, rightToLeft: rtl, joinsLetters: joins)
      }).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func target() -> String {
      views(PromptFieldNativeView.self, in: host).compactMap { $0.accessibilityValue() as? String }.joined()
    }
    defer {
      for continuation in pendingLayouts { continuation.resume() }
      host.rootView = AnyView(EmptyView())
      flush()
      window.contentView = nil
      window.close()
      withExtendedLifetime(container) {}
    }
    let deadline = Date().addingTimeInterval(20)
    while layoutCalls < 1 && Date() < deadline { flush() }
    XCTAssertEqual(generationCalls, 1)
    XCTAssertEqual(layoutCalls, 1)
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    input.insertText("x", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertFalse(target().contains("staged"))
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    settings.fontSize = 36
    flush()
    pendingLayouts.removeFirst().resume()
    while layoutCalls < 2 && Date() < deadline { flush() }
    XCTAssertEqual(generationCalls, 1)
    XCTAssertEqual(layoutCalls, 2)
    XCTAssertFalse(target().contains("staged"))
    XCTAssertTrue(settings.allowsRestartingConfigurationChange)
    pendingLayouts.removeFirst().resume()
    while target() != expected && Date() < deadline { flush() }
    XCTAssertEqual(target(), expected)
    XCTAssertTrue(views(PromptFieldNativeView.self, in: host).first?.usedPreparedLayout == true)
  }
  private enum Scenario { case publish, restart, displayOff, leave, failure, rules, resume, tape, actual, actualFirstInput, actualInterleavings }

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
    pending.usesActualGenerator = scenario == .actual || scenario == .actualFirstInput
      || scenario == .actualInterleavings
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
    if scenario == .actual || scenario == .actualFirstInput || scenario == .actualInterleavings {
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
      XCTAssertEqual(actual.split(separator: " ").count, wordCount)
      let renderDeadline = Date().addingTimeInterval(wordCount > 100_000 ? 90 : 20)
      while target() != actual && Date() < renderDeadline { flush() }
      let displayed = target()
      XCTAssertTrue(displayed == actual,
        "Complete candidate must publish after rendering: displayed=\(displayed.count) expected=\(actual.count); \(evidence)")
      if wordCount > 100_000 {
        XCTAssertTrue(views(PromptFieldNativeView.self, in: host).first?.usedPreparedLayout == true,
          "The production field must consume ticket-prepared geometry at the actual width")
      }
      if let started = pending.preparationStarted {
        print("whole preview presentation observation: words=\(wordCount) elapsed=\(ProcessInfo.processInfo.systemUptime - started) layoutMax=\(layoutMaximum) runLoopMax=\(runLoopMaximum)")
      }
      if scenario == .actualFirstInput || scenario == .actualInterleavings {
        let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
        let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
        let beforeCaret = try XCTUnwrap(field.measuredMainCaretRect())
        let beforeInk = try XCTUnwrap(field.renderedCellText(for: 0))
        let first = try XCTUnwrap(actual.first)
        let before = ProcessInfo.processInfo.systemUptime
        input.onInsert(String(first), false)
        XCTAssertFalse(settings.allowsRestartingConfigurationChange,
          "A long No Quit attempt must lock before the first input callback returns")
        let callback = ProcessInfo.processInfo.systemUptime - before
        flush()
        let elapsed = ProcessInfo.processInfo.systemUptime - before
        print("whole preview first input observation: words=\(wordCount) callback=\(callback) elapsed=\(elapsed) layoutMax=\(layoutMaximum) runLoopMax=\(runLoopMaximum)")
        XCTAssertEqual(target(), actual)
        let updated = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
        XCTAssertTrue(updated === field, "The prompt view must keep its native owner across the first key")
        XCTAssertNotEqual(updated.renderedCellText(for: 0), beforeInk,
          "The first accepted key must update visible field ink, not retain the initial snapshot")
        let afterCaret = try XCTUnwrap(updated.measuredMainCaretRect())
        XCTAssertGreaterThan(afterCaret.minX, beforeCaret.minX,
          "The field caret must advance with the first accepted key")
        XCTAssertFalse(settings.allowsRestartingConfigurationChange,
          "The first character must begin the actual No Quit attempt")
        XCTAssertLessThan(elapsed, 40, "The first key must not render the entire body twice")
        if scenario == .actualInterleavings {
          let second = try XCTUnwrap(actual.dropFirst().first)
          let acceptedInk = try XCTUnwrap(updated.renderedCellText(for: 0))
          let secondBeforeInk = try XCTUnwrap(updated.renderedCellText(for: 1))
          input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertTrue(input.hasMarkedText())
          XCTAssertTrue(target().hasPrefix(String(first) + "候"),
            "The candidate must replace the current visible cell, not the accepted first cell")
          settings.fontSize = 36
          flush()
          XCTAssertTrue(target().hasPrefix(String(first) + "候"),
            "A style change must not publish pre-composition ink over the candidate")
          input.unmarkText()
          flush()
          XCTAssertFalse(input.hasMarkedText())
          XCTAssertEqual(target(), actual)
          let resumed = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
          XCTAssertTrue(resumed === field)
          XCTAssertEqual(resumed.renderedCellText(for: 0), acceptedInk)
          let resumedCaret = try XCTUnwrap(resumed.measuredMainCaretRect())
          XCTAssertGreaterThan(resumedCaret.minX,
            try XCTUnwrap(resumed.measuredRect(for: 0)).minX)
          input.onInsert(String(second), false)
          flush()
          XCTAssertEqual(target(), actual)
          let twiceUpdated = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
          XCTAssertTrue(twiceUpdated === field)
          XCTAssertNotEqual(twiceUpdated.renderedCellText(for: 1), secondBeforeInk)
          XCTAssertGreaterThan(try XCTUnwrap(twiceUpdated.measuredMainCaretRect()).minX,
            resumedCaret.minX)
          XCTAssertFalse(settings.allowsRestartingConfigurationChange)
        }
      }
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
    case .actual, .actualFirstInput, .actualInterleavings: XCTFail("Handled above")
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
