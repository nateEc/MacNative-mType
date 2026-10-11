import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class LivePracticeReplacementHostTests: XCTestCase {
  private final class ExistingWindow: NSWindow {
    var closeCount = 0
    override func close() { closeCount += 1; super.close() }
  }

  @MainActor private final class PendingContent {
    var continuations: [CheckedContinuation<LivePracticeContent?, Never>] = []
    var source: LivePracticeContentSource?
    var callCount = 0
    var cancelledReplies = 0
    var scriptedTokens: [String]?
    var returnsFailure = false
    func fetch(_ source: LivePracticeContentSource, _ language: TypingLanguage) async -> LivePracticeContent? {
      self.source = source
      callCount += 1
      let content = await withCheckedContinuation { continuations.append($0) }
      if withUnsafeCurrentTask(body: { $0?.isCancelled == true }) { cancelledReplies += 1 }
      return content
    }
    func finish() {
      let pending = continuations
      continuations = []
      for continuation in pending {
        continuation.resume(returning: returnsFailure ? nil : .init(source: source ?? .poetry, title: "Authored delayed fixture",
          byline: nil, tokens: scriptedTokens ?? (0..<151).map { ["quiet", "harbor", "morning"][$0 % 3] }, separator: " "))
      }
    }
  }

  func testDelayedLiveReplacementUsesCurrentWholePreviewAndKeepsConfiguredPace() throws {
    try checkDelayedReplacement()
  }

  func testLiveResponseAfterFirstInputPreservesPromptAndMainCaret() throws {
    try checkDelayedReplacement(startsBeforeReturn: true)
  }

  func testDisablingPaceDuringLiveFetchDoesNotRestoreTheOldMarker() throws {
    try checkDelayedReplacement(disablesPace: true)
  }

  func testLiveResponseDuringUncommittedCompositionPreservesPromptAndCandidate() throws {
    try checkDelayedReplacement(composesBeforeReturn: true)
  }

  func testLiveSectionPrefetchIsSingleFlightAndAppendsWithoutReplacingNativeInput() throws {
    try checkDelayedReplacement(prefetches: true)
  }

  func testExhaustedGeneratorFetchesWithFullWindowAndPublishesOnlyOneField() throws {
    try checkDelayedReplacement(prefetches: true, generatesNextWord: true)
  }

  func testEmptyGeneratorSectionFailsEvenWithFullWindowAndActiveNoQuit() throws {
    try checkDelayedReplacement(prefetches: true, locksNoQuit: true, emptyPrefetch: true,
      generatesNextWord: true)
  }

  func testGeneratorTransportFailureEndsNoQuitAttemptWithoutDisablingSource() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, locksNoQuit: true,
      generatesNextWord: true)
  }

  func testLeavingPracticeCancelsGeneratorRequestAndRejectsItsLateField() throws {
    try checkDelayedReplacement(prefetches: true, cancelsPrefetch: true, generatesNextWord: true)
  }

  func testUnlockedGeneratorFailureDisablesSourceWithoutRestartingOffline() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, generatesNextWord: true)
  }

  func testEncyclopediaGeneratorFailureEndsAttemptWithoutDisablingSource() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true,
      generatesNextWord: true, encyclopedia: true)
  }

  func testEncyclopediaSideFailurePreservesAttemptAndCanRecoverOnLaterProgress() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, encyclopedia: true)
  }

  func testEncyclopediaGeneratorFailurePreservesSourceAndReleasesNoQuitLock() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, locksNoQuit: true,
      generatesNextWord: true, encyclopedia: true)
  }

  func testEncyclopediaSideFailurePreservesNoQuitLockAndCanRecover() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, locksNoQuit: true,
      encyclopedia: true)
  }

  func testLeavingPracticeRejectsLateEncyclopediaGeneratorFailure() throws {
    try checkDelayedReplacement(prefetches: true, cancelsPrefetch: true, failsPrefetch: true,
      generatesNextWord: true, encyclopedia: true)
  }

  func testBackwardDeletionDoesNotStartAnotherGeneratorRequest() throws {
    try checkDelayedReplacement(prefetches: true, generatesNextWord: true, checksBackwardInput: true)
  }

  func testLeavingLivePracticeCancelsPrefetchAndRejectsLateSection() throws {
    try checkDelayedReplacement(prefetches: true, cancelsPrefetch: true)
  }

  func testFailedPrefetchDisablesOnlyItsSourceAndRestartsOffline() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true)
  }

  func testFailedPrefetchRetainsNoQuitLockedAttemptAndCanRecoverOnLaterProgress() throws {
    try checkDelayedReplacement(prefetches: true, failsPrefetch: true, locksNoQuit: true)
  }

  func testFailedInitialFetchDisablesItsSourceAndRebuildsOffline() throws {
    try checkDelayedReplacement(failsInitial: true)
  }

  func testFailedInitialFetchKeepsUnrelatedNoQuitOnTheUnstartedReplacement() throws {
    try checkDelayedReplacement(locksNoQuit: true, failsInitial: true)
  }

  func testLateInitialFetchFailureCannotResetAnAlreadyLockedAttempt() throws {
    try checkDelayedReplacement(startsBeforeReturn: true, locksNoQuit: true, failsInitial: true)
  }

  func testFailureWhileFillingInitialPreviewDiscardsPartialContentAndDisablesSource() throws {
    try checkDelayedReplacement(locksNoQuit: true, failsInitial: true, failsInitialFill: true)
  }

  func testEmptyPrefetchRetainsSourcePromptAndLockedAttemptUntilLaterProgress() throws {
    try checkDelayedReplacement(prefetches: true, locksNoQuit: true, emptyPrefetch: true)
  }

  func testEmptyInitialSectionReattemptsBeforeApplyingAValidPrompt() throws {
    try checkDelayedReplacement(emptyInitialReplies: 1)
  }

  func testThreeEmptyInitialSectionsStopWithoutDisablingSourceOrUsingOfflinePrompt() throws {
    try checkDelayedReplacement(emptyInitialReplies: 3)
  }

  func testEmptyInitializationFailureCannotReplaceAnAlreadyStartedAttempt() throws {
    try checkDelayedReplacement(startsBeforeReturn: true, emptyInitialReplies: 3)
  }

  func testEmptySectionAtExhaustedTargetsFailsWithoutDisablingSource() throws {
    try checkDelayedReplacement(prefetches: true, locksNoQuit: true,
      emptyPrefetch: true, exhaustsBeforeEmpty: true)
  }

  func testFailedGenerationPresentationKeepsAValidStoreWhileAnUnrelatedStoreSaves() throws {
    let existing = ExistingWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    existing.isReleasedWhenClosed = false
    let existingContent = NSView()
    existing.contentView = existingContent
    defer { existing.contentView = nil; existing.close() }
    try checkDelayedReplacement(prefetches: true, locksNoQuit: true,
      emptyPrefetch: true, exhaustsBeforeEmpty: true)
    XCTAssertEqual(existing.closeCount, 0, "Fixture retirement must not close a pre-existing window")
    XCTAssertTrue(existing.contentView === existingContent)
    let writer = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defer { withExtendedLifetime(writer) {} }
    try LocalPersonalBestStore.initialize(in: writer.mainContext)
    XCTAssertEqual(try writer.mainContext.fetchCount(FetchDescriptor<LocalPersonalBestLedgerRecord>()), 1)
  }

  private func checkDelayedReplacement(startsBeforeReturn: Bool = false,
    disablesPace: Bool = false, composesBeforeReturn: Bool = false, prefetches: Bool = false,
    cancelsPrefetch: Bool = false, failsPrefetch: Bool = false, locksNoQuit: Bool = false,
    emptyPrefetch: Bool = false, emptyInitialReplies: Int = 0,
    exhaustsBeforeEmpty: Bool = false, failsInitial: Bool = false,
    failsInitialFill: Bool = false, generatesNextWord: Bool = false,
    checksBackwardInput: Bool = false, encyclopedia: Bool = false) throws {
    let suite = "LivePracticeReplacementHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.reducePracticeMotion = true
    settings.paceGuideMode = .custom
    settings.paceGuideCustomWpm = 80
    settings.paceCaretStyle = .outline
    settings.showAllPracticeLines = false
    let sourceModifier: TestModifier = encyclopedia ? .referenceStream : .poetryStream
    let modifiers: [TestModifier] = locksNoQuit ? [sourceModifier, .noQuit] : [sourceModifier]
    settings.testModifiers = modifiers
    if composesBeforeReturn { settings.compositionDisplayStyle = .below }
    let configuration = TestConfiguration.words(prefetches ? 300 : 151).with(modifiers: modifiers)
    XCTAssertTrue(settings.saveActiveTestSelection(.init(
      preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let priorWindowIDs = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
    let pending = PendingContent()
    let authoredTokens = (0..<300).map { "owned\($0)" }
    if prefetches { pending.scriptedTokens = Array(authoredTokens.prefix(151)) }
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      liveContentFetch: pending.fetch).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      withExtendedLifetime(container) {
        pending.finish()
        // Release query/observation nodes before their in-memory container.
        host.rootView = AnyView(EmptyView())
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(views(TypingInputView.self, in: host).isEmpty,
          "Replacing the hosted root must remove the old practice input before releasing its store")
        XCTAssertTrue(views(PromptFieldNativeView.self, in: host).isEmpty,
          "Replacing the hosted root must remove the old prompt before releasing its store")
        window.contentView = nil
        window.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      }
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func presentCarets() {
      // A bounded run-loop drain does not guarantee a timer presentation in
      // an invisible XCTest window. Sample the real presenter on both sides
      // of transport completion, rather than compare a stale pre-input frame.
      for presenter in views(PromptCaretNativeView.self, in: host) {
        presenter.present(at: ProcessInfo.processInfo.systemUptime)
      }
    }
    for _ in 0..<10 where pending.continuations.isEmpty { flush() }
    XCTAssertEqual(pending.source, encyclopedia ? .encyclopedia : .poetry)
    XCTAssertFalse(pending.continuations.isEmpty, "The production load must reach the injected transport")
    if !prefetches { settings.showAllPracticeLines = true }
    if disablesPace { settings.paceGuideMode = .off }
    flush()
    let initialField = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
    let initialPrompt = try XCTUnwrap(initialField.accessibilityValue() as? String)
    let initialInput = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    var startedCaret: CGRect?
    if composesBeforeReturn {
      initialInput.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
        replacementRange: .init(location: NSNotFound, length: 0))
      flush()
      XCTAssertTrue(initialInput.hasMarkedText())
    }
    if startsBeforeReturn {
      // Exercise the native focus callbacks without activating this window.
      // A genuinely unfocused production window intentionally has no main marker.
      initialInput.onFocusChanged(true)
      initialInput.onWindowFocusChanged(true, false)
      flush()
      presentCarets()
      let beforeInputCaret = try XCTUnwrap(views(NSHostingView<PromptCaretMarkerView>.self, in: host)
        .first { $0.rootView.style == .bar && !$0.isHidden }).frame
      initialInput.insertText(String(initialPrompt.prefix(1)),
        replacementRange: .init(location: NSNotFound, length: 0))
      flush()
      presentCarets()
      startedCaret = try XCTUnwrap(views(NSHostingView<PromptCaretMarkerView>.self, in: host)
        .first { $0.rootView.style == .bar && !$0.isHidden }).frame
      XCTAssertGreaterThan(try XCTUnwrap(startedCaret).minX, beforeInputCaret.minX,
        "The first accepted English character must advance the main caret before the response")
    }
    if emptyInitialReplies > 0 {
      let initialRequestCount = pending.callCount
      pending.scriptedTokens = []
      for _ in 0..<emptyInitialReplies {
        pending.finish()
        for _ in 0..<5 { flush() }
      }
      XCTAssertEqual(pending.callCount, initialRequestCount + min(emptyInitialReplies, 2))
      XCTAssertTrue(settings.testModifiers.contains(.poetryStream))
      if emptyInitialReplies == 3 {
        XCTAssertTrue(pending.continuations.isEmpty, "Three failed initial generations are the limit")
        if startsBeforeReturn {
          let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
          XCTAssertEqual(field.accessibilityValue() as? String, initialPrompt)
          XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
        } else {
          XCTAssertTrue(views(PromptFieldNativeView.self, in: host).isEmpty,
            "An initial generation failure must not leave an offline prompt")
          initialInput.insertText("ignored", replacementRange: .init(location: NSNotFound, length: 0))
          for _ in 0..<5 { flush() }
          XCTAssertTrue(views(PromptFieldNativeView.self, in: host).isEmpty)
          XCTAssertEqual(pending.callCount, initialRequestCount + 2)
          XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
        }
        XCTAssertFalse(window.isVisible)
        return
      }
      pending.scriptedTokens = nil
    }
    let requestsBeforeInitialReply = pending.callCount
    if failsInitial {
      pending.returnsFailure = !failsInitialFill
      if failsInitialFill { pending.scriptedTokens = ["ownedPartialInitial"] }
    }
    pending.finish()
    for _ in 0..<5 { flush() }
    if failsInitialFill {
      XCTAssertEqual(pending.callCount, requestsBeforeInitialReply + 1)
      XCTAssertEqual(pending.continuations.count, 1)
      pending.returnsFailure = true
      pending.finish()
      for _ in 0..<5 { flush() }
    }
    if failsInitial {
      XCTAssertEqual(settings.testModifiers.contains(.poetryStream), startsBeforeReturn)
      XCTAssertEqual(settings.testModifiers.contains(.noQuit), locksNoQuit)
      XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(.poetryStream), startsBeforeReturn)
      XCTAssertEqual(settings.allowsRestartingConfigurationChange, !(startsBeforeReturn && locksNoQuit))
      XCTAssertEqual(pending.callCount, requestsBeforeInitialReply + (failsInitialFill ? 1 : 0),
        "The initial failure must not trigger an additional provider request")
      XCTAssertTrue(pending.continuations.isEmpty)
      let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
      XCTAssertFalse((field.accessibilityValue() as? String)?.isEmpty ?? true)
      XCTAssertFalse((field.accessibilityValue() as? String)?.contains("ownedPartialInitial") == true,
        "A failed initial fill must not publish its partially collected provider words")
      if startsBeforeReturn {
        XCTAssertEqual(field.accessibilityValue() as? String, initialPrompt)
        XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
        presentCarets()
        let caret = try XCTUnwrap(views(NSHostingView<PromptCaretMarkerView>.self, in: host)
          .first { $0.rootView.style == .bar && !$0.isHidden })
        XCTAssertEqual(caret.frame, startedCaret)
      }
      XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
      XCTAssertFalse(window.isVisible)
      return
    }
    if prefetches {
      let initialRequestCount = pending.callCount
      XCTAssertTrue(pending.continuations.isEmpty, "Initial restoration requests must have resolved")
      if generatesNextWord {
        initialInput.insertText("o", replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount, "A partial first word must not request generator content")
        initialInput.insertText("wned0 " + authoredTokens[1..<51].joined(separator: " ") + " ",
          replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount, "Consuming the last retained field does not itself fetch")
        initialInput.insertText(authoredTokens[51] + " ",
          replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount + 1, "The next forward action must fetch with a full future window")
        XCTAssertEqual(pending.continuations.count, 1)
        initialInput.insertText(authoredTokens[52..<54].joined(separator: " ") + " ",
          replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount + 1, "Generator requests must remain single-flight")
        let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
        let before = try XCTUnwrap(field.accessibilityValue() as? String)
        let cancelled = pending.cancelledReplies
        if locksNoQuit { XCTAssertFalse(settings.allowsRestartingConfigurationChange) }
        if cancelsPrefetch {
          window.contentView = nil
          for _ in 0..<5 { flush() }
        }
        pending.scriptedTokens = emptyPrefetch ? []
          : checksBackwardInput ? [authoredTokens[151]] : Array(authoredTokens[151..<300])
        pending.returnsFailure = failsPrefetch
        pending.finish()
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount + 1)
        XCTAssertTrue(pending.continuations.isEmpty)
        if cancelsPrefetch {
          XCTAssertGreaterThan(pending.cancelledReplies, cancelled)
          XCTAssertEqual(field.accessibilityValue() as? String, before)
        } else if emptyPrefetch || failsPrefetch {
          let keepsSource = emptyPrefetch || locksNoQuit || encyclopedia
          XCTAssertEqual(settings.testModifiers.contains(sourceModifier), keepsSource)
          XCTAssertEqual(settings.testModifiers.contains(.noQuit), locksNoQuit)
          XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(sourceModifier), keepsSource)
          XCTAssertTrue(settings.allowsRestartingConfigurationChange, "Generator failure ends the attempt, unlike a refused side-pull restart")
          XCTAssertEqual(field.accessibilityValue() as? String, before)
          XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
          XCTAssertTrue(NSApplication.shared.windows.contains {
            $0 !== window && !priorWindowIDs.contains(ObjectIdentifier($0)) && $0.contentView != nil
          }, "A generator failure must produce real result presentation content")
        } else {
          XCTAssertEqual(field.accessibilityValue() as? String, before.trimmingCharacters(in: .whitespaces) + " owned151 ")
          XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
          if checksBackwardInput {
            initialInput.onDeleteWord()
            for _ in 0..<5 { flush() }
            XCTAssertEqual(pending.callCount, initialRequestCount + 1,
              "Backward progress must not fetch another section even when its generator pool is empty")
            XCTAssertTrue(pending.continuations.isEmpty)
            XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
            return
          }
          initialInput.insertText(authoredTokens[54] + " ",
            replacementRange: .init(location: NSNotFound, length: 0))
          for _ in 0..<5 { flush() }
          XCTAssertTrue((field.accessibilityValue() as? String)?.hasSuffix("owned151 owned152 ") == true)
          XCTAssertFalse((field.accessibilityValue() as? String)?.contains("owned153") == true)
          XCTAssertEqual(pending.callCount, initialRequestCount + 1)
        }
        XCTAssertFalse(window.isVisible)
        return
      }
      // One bulk input event reaches the side-pull boundary before SwiftUI
      // delivers the count change. Separate tests above cover earlier demand.
      initialInput.insertText(authoredTokens.prefix(132).joined(separator: " ") + " ",
        replacementRange: .init(location: NSNotFound, length: 0))
      for _ in 0..<5 { flush() }
      XCTAssertEqual(pending.callCount, initialRequestCount + 1, "19 words must start a new section request")
      XCTAssertEqual(pending.continuations.count, 1)
      initialInput.insertText(authoredTokens[132..<134].joined(separator: " ") + " ",
        replacementRange: .init(location: NSNotFound, length: 0))
      for _ in 0..<5 { flush() }
      XCTAssertEqual(pending.callCount, initialRequestCount + 1, "Progress during an in-flight request must not duplicate it")
      let fieldBeforeReply = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
      let beforeReply = try XCTUnwrap(fieldBeforeReply.accessibilityValue() as? String)
      let priorCancelledReplies = pending.cancelledReplies
      if locksNoQuit {
        XCTAssertFalse(settings.allowsRestartingConfigurationChange,
          "The active No Quit attempt must actually be locked before the source fails")
      }
      if exhaustsBeforeEmpty {
        initialInput.insertText(authoredTokens[134..<151].joined(separator: " ") + " ",
          replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
      }
      if cancelsPrefetch {
        window.contentView = nil
        for _ in 0..<5 { flush() }
      }
      pending.scriptedTokens = emptyPrefetch ? [] : Array(authoredTokens[151..<300])
      pending.returnsFailure = failsPrefetch
      pending.finish()
      for _ in 0..<5 { flush() }
      if emptyPrefetch {
        XCTAssertTrue(settings.testModifiers.contains(.poetryStream))
        XCTAssertTrue(settings.testModifiers.contains(.noQuit))
        XCTAssertEqual(pending.callCount, initialRequestCount + 1, "No tight loop on empty sections")
        XCTAssertTrue(pending.continuations.isEmpty)
        if exhaustsBeforeEmpty {
          XCTAssertTrue(settings.allowsRestartingConfigurationChange, "Generation failure ends the active lock")
          XCTAssertTrue((fieldBeforeReply.accessibilityValue() as? String)?.contains("owned150") == true,
            "Failure retains the authored targets rather than starting an offline attempt")
          XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
          XCTAssertTrue(NSApplication.shared.windows.contains {
            $0 !== window && !priorWindowIDs.contains(ObjectIdentifier($0)) && $0.contentView != nil
          }, "The failed attempt must really create result presentation content before retirement")
          XCTAssertFalse(window.isVisible)
          return
        }
        let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
        XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
        XCTAssertFalse(settings.allowsRestartingConfigurationChange)
        XCTAssertEqual(field.accessibilityValue() as? String, beforeReply)
        pending.scriptedTokens = Array(authoredTokens[151..<300])
        initialInput.insertText(authoredTokens[134] + " ",
          replacementRange: .init(location: NSNotFound, length: 0))
        for _ in 0..<5 { flush() }
        XCTAssertEqual(pending.callCount, initialRequestCount + 2)
        XCTAssertEqual(pending.continuations.count, 1)
        pending.finish()
        for _ in 0..<5 { flush() }
        XCTAssertTrue(settings.testModifiers.contains(.poetryStream))
        XCTAssertFalse(settings.allowsRestartingConfigurationChange)
        XCTAssertTrue((field.accessibilityValue() as? String)?.hasSuffix(authoredTokens.suffix(3).joined(separator: " ")) == true)
        XCTAssertFalse(window.isVisible)
        return
      }
      if failsPrefetch {
        if encyclopedia {
          XCTAssertTrue(settings.testModifiers.contains(sourceModifier))
          XCTAssertEqual(settings.allowsRestartingConfigurationChange, !locksNoQuit)
          XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(sourceModifier), true)
          XCTAssertEqual(fieldBeforeReply.accessibilityValue() as? String, beforeReply)
          XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
          XCTAssertEqual(pending.callCount, initialRequestCount + 1, "No immediate retry after a rejected side request")
          XCTAssertTrue(pending.continuations.isEmpty)
          XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
          XCTAssertFalse(NSApplication.shared.windows.contains {
            $0 !== window && !priorWindowIDs.contains(ObjectIdentifier($0)) && $0.contentView != nil
          }, "A rejected side request does not end the attempt or present a result")
          pending.returnsFailure = false
          initialInput.insertText(authoredTokens[134] + " ",
            replacementRange: .init(location: NSNotFound, length: 0))
          for _ in 0..<5 { flush() }
          XCTAssertEqual(pending.callCount, initialRequestCount + 2)
          XCTAssertEqual(pending.continuations.count, 1)
          pending.finish()
          for _ in 0..<5 { flush() }
          XCTAssertTrue(settings.testModifiers.contains(sourceModifier))
          XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
          XCTAssertTrue((fieldBeforeReply.accessibilityValue() as? String)?.hasSuffix(authoredTokens.suffix(3).joined(separator: " ")) == true)
          XCTAssertFalse(window.isVisible)
          return
        }
        if locksNoQuit {
          XCTAssertTrue(settings.testModifiers.contains(.poetryStream))
          XCTAssertTrue(settings.testModifiers.contains(.noQuit))
          XCTAssertFalse(settings.allowsRestartingConfigurationChange)
          XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(.poetryStream), true)
          XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(.noQuit), true)
          let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
          XCTAssertEqual(field.accessibilityValue() as? String, beforeReply)
          XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
          XCTAssertEqual(pending.callCount, initialRequestCount + 1)
          XCTAssertTrue(pending.continuations.isEmpty)
          XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<TestResultRecord>()), 0)
          pending.returnsFailure = false
          initialInput.insertText(authoredTokens[134] + " ",
            replacementRange: .init(location: NSNotFound, length: 0))
          for _ in 0..<5 { flush() }
          XCTAssertEqual(pending.callCount, initialRequestCount + 2)
          XCTAssertEqual(pending.continuations.count, 1)
          pending.finish()
          for _ in 0..<5 { flush() }
          XCTAssertTrue(settings.testModifiers.contains(.poetryStream))
          XCTAssertFalse(settings.allowsRestartingConfigurationChange)
          XCTAssertTrue((field.accessibilityValue() as? String)?.hasSuffix(authoredTokens.suffix(3).joined(separator: " ")) == true)
          XCTAssertFalse(window.isVisible)
          return
        }
        XCTAssertFalse(settings.testModifiers.contains(.poetryStream))
        XCTAssertEqual(settings.testModifiers.contains(.noQuit), locksNoQuit)
        XCTAssertTrue(settings.allowsRestartingConfigurationChange,
          "The newly restarted attempt has not started typing")
        XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(.noQuit), locksNoQuit)
        XCTAssertEqual(settings.activeTestSelection?.preset.configuration.modifiers.contains(.poetryStream), false)
        let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
        let offlinePrompt = try XCTUnwrap(field.accessibilityValue() as? String)
        XCTAssertFalse(offlinePrompt.isEmpty)
        XCTAssertNotEqual(offlinePrompt, beforeReply)
        XCTAssertFalse(offlinePrompt.contains("owned"))
        XCTAssertEqual(pending.callCount, initialRequestCount + 1)
        XCTAssertTrue(pending.continuations.isEmpty)
        XCTAssertFalse(window.isVisible)
        return
      }
      if cancelsPrefetch {
        XCTAssertGreaterThan(pending.cancelledReplies, priorCancelledReplies)
        XCTAssertEqual(fieldBeforeReply.accessibilityValue() as? String, beforeReply)
        XCTAssertEqual(pending.callCount, initialRequestCount + 1)
        XCTAssertFalse(window.isVisible)
        return
      }
      let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
      XCTAssertEqual(field.accessibilityValue() as? String,
        beforeReply.trimmingCharacters(in: .whitespaces) + " " + authoredTokens[151..<300].joined(separator: " "),
        "Append must preserve the exact retained visible window, not restore retired words")
      XCTAssertTrue(views(TypingInputView.self, in: host).first === initialInput)
      XCTAssertEqual(pending.callCount, initialRequestCount + 1)
      XCTAssertFalse(window.isVisible)
      return
    }
    let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
    let expected = (0..<151).map { ["quiet", "harbor", "morning"][$0 % 3] }.joined(separator: " ")
    XCTAssertEqual(field.accessibilityValue() as? String,
      startsBeforeReturn || composesBeforeReturn ? initialPrompt : expected,
      "Use current display settings only before input starts; a late response must not replace an active prompt")
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    XCTAssertTrue(input === initialInput, "Transport completion must not replace the native input owner")
    if startsBeforeReturn {
      presentCarets()
      let caret = try XCTUnwrap(views(NSHostingView<PromptCaretMarkerView>.self, in: host)
        .first { $0.rootView.style == .bar && !$0.isHidden })
      XCTAssertEqual(caret.frame, startedCaret,
        "The accepted first character's main caret must not reset when the response arrives")
    } else if !composesBeforeReturn {
      input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
    }
    flush()
    if composesBeforeReturn {
      XCTAssertTrue(input.hasMarkedText(), "A late response must not end native marked text")
      XCTAssertTrue(views(NSTextField.self, in: host)
        .contains { $0.accessibilityLabel() == "正在组合：中文" },
        "The exact uncommitted candidate must remain attached to the production prompt")
      XCTAssertFalse(window.isVisible)
      return
    }
    // An invisible host's run-loop drain does not guarantee a timer delivery.
    // Sample the actual presenter just as the main-caret assertions above do.
    XCTAssertFalse(views(PromptCaretNativeView.self, in: host).isEmpty)
    presentCarets()
    let markers = views(NSHostingView<PromptCaretMarkerView>.self, in: host)
    XCTAssertEqual(markers.contains { $0.rootView.style == .outline && !$0.isHidden }, !disablesPace,
      "Online completion must use the current Pace choice, not the pre-request choice")
    XCTAssertFalse(window.isVisible)
  }
}
