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
    flush()
    pending.finish()
    for _ in 0..<5 { flush() }
    let field = try XCTUnwrap(views(PromptFieldNativeView.self, in: host).first)
    let expected = (0..<151).map { ["quiet", "harbor", "morning"][$0 % 3] }.joined(separator: " ")
    XCTAssertEqual(field.accessibilityValue() as? String, expected,
      "A setting changed while transport is suspended must control the actual replacement")
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    let markers = views(NSHostingView<PromptCaretMarkerView>.self, in: host)
    XCTAssertTrue(markers.contains { $0.rootView.style == .outline && !$0.isHidden },
      "Online replacement must retain the configured independent pace marker after input starts")
    XCTAssertFalse(window.isVisible)
  }
}
