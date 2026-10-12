import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class TapePracticeCompositionHostTests: XCTestCase {
  func testProductionTapeCompositionUpdatesCancelsAndCommitsWithoutReplacingInput() throws {
    for mode in [PracticeTapeMode.letter, .word] {
      let suite = "TapePracticeCompositionHostTests.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let settings = AppSettings(defaults: defaults)
      settings.practiceTapeMode = mode
      settings.reducePracticeMotion = true
      let prompt = "quiet harbor morning"
      let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
        difficulty: .normal, rules: .init(), language: .english)
      XCTAssertTrue(settings.saveActiveTestSelection(.init(
        preset: .init(configuration: configuration, customText: prompt),
        testParameterMemory: .legacyDefaults(configuration: configuration))))
      let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let content = TypebarApp.practiceContent(settings: settings,
        account: AccountSession(defaults: defaults),
        announcements: RemoteAnnouncementCenter(defaults: defaults), hotkey: GlobalHotkeyMonitor(),
        systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
        network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor())
        .modelContainer(container).frame(width: 1000, height: 720)
      let host = NSHostingView(rootView: content)
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
      }
      defer {
        descendants(host, TapePromptNativeView.self).forEach { $0.stop() }
        window.contentView = nil
        window.close()
      }
      func flush() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
      }
      flush()
      let input = try XCTUnwrap(descendants(host, TypingInputView.self).first)
      let owner = try XCTUnwrap(descendants(host, TapePromptNativeView.self).first)
      var expected = TypingSession(configuration: configuration, prompt: prompt)
      func check(_ candidate: String, _ style: CompositionDisplayStyle) throws {
        let presentation = try XCTUnwrap(PromptCompositionPresentation(session: expected,
          composition: candidate, style: style))
        let rendering = presentation.render { _, glyph, cell in
          AttributedString(cell?.text ?? String(glyph.character))
        }
        XCTAssertEqual(owner.accessibilityLabel(), String(rendering.text.characters))
        XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
        XCTAssertTrue(descendants(host, TapePromptNativeView.self).first === owner)
        let rows = descendants(host, NSTextField.self).filter {
          $0.accessibilityLabel()?.hasPrefix("正在组合：") == true
        }
        XCTAssertEqual(rows.count, style == .below && !candidate.isEmpty ? 1 : 0)
        if style == .below && !candidate.isEmpty { XCTAssertEqual(rows.first?.stringValue, candidate) }
        XCTAssertFalse(window.isVisible)
      }
      for candidate in ["候", "😀e\u{301}候", String(repeating: "中文", count: 20)] {
        input.setMarkedText(candidate, selectedRange: .init(location: candidate.utf16.count, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        for style in [CompositionDisplayStyle.replace, .off, .below, .replace] {
          settings.compositionDisplayStyle = style
          flush()
          XCTAssertTrue(input.hasMarkedText())
          XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: candidate.utf16.count))
          XCTAssertEqual(input.selectedRange(), NSRange(location: candidate.utf16.count, length: 0))
          try check(candidate, style)
        }
        input.unmarkText()
        flush()
        XCTAssertFalse(input.hasMarkedText())
        XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
        try check("", .replace)
      }
      input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
        replacementRange: .init(location: NSNotFound, length: 0))
      input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
      expected.insertBatch("q", at: Date())
      flush()
      XCTAssertFalse(input.hasMarkedText())
      // This input client owns only the marked buffer, not the committed prompt.
      XCTAssertEqual(input.selectedRange(), NSRange(location: 0, length: 0))
      input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
        replacementRange: .init(location: NSNotFound, length: 0))
      flush()
      XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: 2))
      try check("中文", .replace)
      input.unmarkText()
      flush()
      try check("", .replace)
    }
  }
}
