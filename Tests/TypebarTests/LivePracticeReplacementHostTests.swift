import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class LivePracticeReplacementHostTests: XCTestCase {
  @MainActor private final class PendingContent {
    var continuations: [CheckedContinuation<LivePracticeContent?, Never>] = []
    var source: LivePracticeContentSource?
    func fetch(_ source: LivePracticeContentSource, _ language: TypingLanguage) async -> LivePracticeContent? {
      self.source = source
      return await withCheckedContinuation { continuations.append($0) }
    }
    func finish() {
      let pending = continuations
      continuations = []
      for continuation in pending {
        continuation.resume(returning: .init(source: .poetry, title: "Authored delayed fixture",
          byline: nil, tokens: ["quiet", "harbor", "morning"], separator: " "))
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

  private func checkDelayedReplacement(startsBeforeReturn: Bool = false,
    disablesPace: Bool = false, composesBeforeReturn: Bool = false) throws {
    let suite = "LivePracticeReplacementHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.reducePracticeMotion = true
    settings.paceGuideMode = .custom
    settings.paceGuideCustomWpm = 80
    settings.paceCaretStyle = .outline
    settings.showAllPracticeLines = false
    settings.testModifiers = [.poetryStream]
    if composesBeforeReturn { settings.compositionDisplayStyle = .below }
    let configuration = TestConfiguration.words(151).with(modifiers: [.poetryStream])
    XCTAssertTrue(settings.saveActiveTestSelection(.init(
      preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let pending = PendingContent()
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      liveContentFetch: pending.fetch).modelContainer(container)
    let host = NSHostingView(rootView: content.frame(width: 1000, height: 720))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { pending.finish(); window.contentView = nil; window.close() }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    for _ in 0..<10 where pending.continuations.isEmpty { flush() }
    XCTAssertEqual(pending.source, .poetry)
    XCTAssertFalse(pending.continuations.isEmpty, "The production load must reach the injected transport")
    settings.showAllPracticeLines = true
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
      initialInput.insertText(String(initialPrompt.prefix(1)),
        replacementRange: .init(location: NSNotFound, length: 0))
      flush()
      startedCaret = try XCTUnwrap(views(NSHostingView<PromptCaretMarkerView>.self, in: host)
        .first { $0.rootView.style == .bar && !$0.isHidden }).frame
    }
    pending.finish()
    for _ in 0..<5 { flush() }
    let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
    let expected = (0..<151).map { ["quiet", "harbor", "morning"][$0 % 3] }.joined(separator: " ")
    XCTAssertEqual(field.accessibilityValue() as? String,
      startsBeforeReturn || composesBeforeReturn ? initialPrompt : expected,
      "Use current display settings only before input starts; a late response must not replace an active prompt")
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    XCTAssertTrue(input === initialInput, "Transport completion must not replace the native input owner")
    if startsBeforeReturn {
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
    let markers = views(NSHostingView<PromptCaretMarkerView>.self, in: host)
    XCTAssertEqual(markers.contains { $0.rootView.style == .outline && !$0.isHidden }, !disablesPace,
      "Online completion must use the current Pace choice, not the pre-request choice")
    XCTAssertFalse(window.isVisible)
  }
}
