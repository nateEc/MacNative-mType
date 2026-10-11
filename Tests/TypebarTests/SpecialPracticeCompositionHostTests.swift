import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class SpecialPracticeCompositionHostTests: XCTestCase {
  func testProductionChooCompositionModesUpdateAndCancelWithoutConsumingTargets() throws {
    let suite = "SpecialPracticeCompositionHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.testModifiers = [.chooVisual]
    let prompt = "quiet harbor morning"
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .english, modifiers: [.chooVisual])
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
    defer { window.contentView = nil; window.close() }
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    flush()
    let input = try XCTUnwrap(descendants(host, TypingInputView.self).first)
    let owner = try XCTUnwrap(descendants(host, ChooLayerView.self).first)
    XCTAssertEqual(owner.accessibilityLabel(), prompt)
    let frame = host.frame
    for style in CompositionDisplayStyle.allCases {
      settings.compositionDisplayStyle = style
      flush()
      for candidate in ["候", "中文"] {
        input.setMarkedText(candidate, selectedRange: .init(location: candidate.utf16.count, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        XCTAssertTrue(input.hasMarkedText())
        XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
        XCTAssertTrue(descendants(host, ChooLayerView.self).first === owner)
        let displayed = try XCTUnwrap(owner.accessibilityLabel())
        XCTAssertEqual(displayed.hasPrefix(candidate), style == .replace)
        let ink = owner.layer?.sublayers?.compactMap { $0 as? CATextLayer }
          .compactMap { ($0.string as? NSAttributedString)?.string }.joined() ?? ""
        XCTAssertEqual(ink.contains("候") || ink.contains("中"), style == .replace)
        let candidateRows = descendants(host, NSTextField.self).filter {
          $0.accessibilityLabel()?.hasPrefix("正在组合：") == true
        }
        XCTAssertEqual(candidateRows.count, style == .below ? 1 : 0)
        if style == .below {
          XCTAssertEqual(candidateRows.first?.stringValue, candidate)
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(host.frame, frame)
      }
      input.unmarkText()
      flush()
      XCTAssertFalse(input.hasMarkedText())
      XCTAssertEqual(owner.accessibilityLabel(), prompt,
        "Cancellation must restore the complete unconsumed target")
    }
    settings.compositionDisplayStyle = .replace
    flush()
    input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertFalse(input.hasMarkedText())
    input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertTrue(owner.accessibilityLabel()?.hasPrefix("q候") == true,
      "After confirmation the next candidate must start after exactly one accepted target")
    XCTAssertTrue(descendants(host, ChooLayerView.self).first === owner)
    XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
    input.unmarkText()
    flush()
    XCTAssertEqual(owner.accessibilityLabel(), prompt)
    XCTAssertFalse(window.isVisible)
  }
}
