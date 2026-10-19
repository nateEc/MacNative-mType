import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ViewportPracticeHostTests: XCTestCase {
  @MainActor private final class Counts { var generation = 0 }
  @MainActor private final class Fixture {
    let suite = "ViewportPracticeHostTests.\(UUID())"
    let defaults: UserDefaults
    let settings: AppSettings
    let container: ModelContainer
    let host: NSHostingView<AnyView>
    let window: NSWindow
    let counts: Counts
    let prompt: String
    init(unicode: Bool = false) throws {
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults)
      settings.reducePracticeMotion = true
      settings.showAllPracticeLines = true
      settings.testModifiers = [.noQuit]
      let configuration = TestConfiguration.words(201).with(modifiers: [.noQuit])
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
        testParameterMemory: .legacyDefaults(configuration: configuration))))
      container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let prompt = (0..<201).map { unicode && $0 == 1 ? "😀" : "word\($0)" }.joined(separator: " ")
      self.prompt = prompt
      let counts = Counts()
      self.counts = counts
      let content = TypebarApp.practiceContent(settings: settings,
        account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
        hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
        network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
        wholePreviewPrepare: { configuration, _, _ in
          counts.generation += 1
          return TypingSession(configuration: configuration, prompt: prompt)
        }, wholePreviewViewportEnabled: true).modelContainer(container)
      host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
      window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      host.layoutSubtreeIfNeeded()
    }
    func views<T: NSView>(_ type: T.Type, in root: NSView? = nil) -> [T] {
      let root = root ?? host
      return (root as? T).map { [$0] } ?? root.subviews.flatMap { views(type, in: $0) }
    }
    func waitUntil(_ ready: () -> Bool) {
      let deadline = Date().addingTimeInterval(15)
      while !ready() && Date() < deadline { flush() }
      XCTAssertTrue(ready(), "Practice page did not reach the expected renderer")
    }
    func close() {
      host.rootView = AnyView(EmptyView())
      flush()
      window.contentView = nil
      window.close()
      defaults.removePersistentDomain(forName: suite)
      withExtendedLifetime(container) {}
    }
  }

  func testActualPracticeInputRepaintsViewportAndKeepsRemotePosition() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertEqual(fixture.counts.generation, 1)
    let before = try XCTUnwrap(native.viewport.canvas.renderedCellText(for: 0))
    input.onInsert("w", false)
    fixture.flush()
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertNotEqual(native.viewport.canvas.renderedCellText(for: 0), before)
    XCTAssertEqual(native.viewport.canvas.measuredMainCaretRect(style: .bar), native.viewport.canvas.measuredRect(for: 1))
    native.viewport.canvas.setAccessibilitySelectedTextRange(.init(location: 130, length: 1))
    fixture.waitUntil { native.viewport.scrollView.contentView.bounds.minY > 0 }
    let origin = native.viewport.scrollView.contentView.bounds.minY
    input.onInsert("o", false)
    fixture.flush()
    XCTAssertEqual(native.viewport.scrollView.contentView.bounds.minY, origin)
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt)
    native.viewport.scrollToTop()
    XCTAssertEqual(native.viewport.canvas.measuredMainCaretRect(style: .bar), native.viewport.canvas.measuredRect(for: 2))
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testCompositionUsesCompleteRendererAndRetiresViewportWithoutResettingAttempt() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onInsert("w", false)
    fixture.flush()
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.contains("中") == true } }
    XCTAssertEqual(native.viewport.measuredFieldCount, 0)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    input.unmarkText()
    fixture.flush()
    XCTAssertTrue(fixture.views(PromptViewportPracticeNativeView.self).isEmpty)
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testUnadmittedTargetFallsBackToCompletePracticeText() throws {
    let fixture = try Fixture(unicode: true)
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptFieldNativeView.self).contains {
      $0.accessibilityValue() as? String == fixture.prompt
    } }
    XCTAssertTrue(fixture.views(PromptViewportPracticeNativeView.self).isEmpty)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertTrue(fixture.settings.allowsRestartingConfigurationChange)
  }

  func testExtraInputFallbackKeepsAcceptedTextAndRetiresViewport() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onInsert("word0xx", false)
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.hasPrefix("word0xx") == true } }
    XCTAssertEqual(native.viewport.measuredFieldCount, 0)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testRemoteReadingPositionAndSelectionSurviveFontAndWidthChanges() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let selected = NSRange(location: 730, length: 3)
    native.viewport.canvas.setAccessibilitySelectedTextRange(selected)
    fixture.flush()
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    XCTAssertNotEqual(anchor, NSNotFound)
    XCTAssertGreaterThan(native.viewport.scrollView.contentView.bounds.minY, 0)
    fixture.settings.fontSize = 36
    fixture.flush()
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()),
      "Reflow must keep the reading row, not return to the first batch")
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    fixture.settings.customPracticeLineColumns = 30
    fixture.settings.practiceLineWidth = .custom
    fixture.flush()
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    native.viewport.scrollView.scrollerStyle = .legacy
    native.viewport.scrollView.tile()
    fixture.flush()
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertLessThan(native.viewport.measuredFieldCount, 201, "Restoring a reading anchor must not measure the entire target")
    XCTAssertFalse(fixture.window.isVisible)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onRestart()
    fixture.waitUntil { fixture.counts.generation == 2
      && fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let restarted = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    XCTAssertEqual(restarted.viewport.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
    XCTAssertEqual(restarted.viewport.scrollView.contentView.bounds.minY, 0)
    XCTAssertEqual(native.viewport.measuredFieldCount, 0, "Restart must retire the former display owner")
  }

  func testManualRemoteScrollWithoutSelectionSurvivesReflow() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    XCTAssertTrue(native.viewport.scrollToField(100))
    fixture.waitUntil { !native.viewport.isPreparing && native.viewport.scrollView.contentView.bounds.minY > 0 }
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    XCTAssertNotEqual(anchor, NSNotFound)
    fixture.settings.fontSize = 36
    fixture.flush()
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testFontAndLineWidthChangesUseVisibleWidthIncludingLegacyScroller() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).first?.viewport.canvas.accessibilityValue() as? String == fixture.prompt }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let oldRect = try XCTUnwrap(native.viewport.canvas.measuredRect(for: 0))
    let oldWidth = native.bounds.width
    fixture.settings.fontSize = 36
    fixture.settings.customPracticeLineColumns = 30
    fixture.settings.practiceLineWidth = .custom
    fixture.waitUntil { native.viewport.canvas.measuredRect(for: 0).map { $0.height > oldRect.height } == true
      && native.bounds.width < oldWidth }
    native.viewport.scrollView.scrollerStyle = .legacy
    native.viewport.scrollView.tile()
    fixture.flush()
    XCTAssertLessThan(native.viewport.scrollView.contentView.bounds.width, native.bounds.width)
    XCTAssertEqual(native.viewport.canvas.frame.width, native.viewport.scrollView.contentView.bounds.width)
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt)
    native.viewport.scrollView.scrollerStyle = .overlay
    native.viewport.scrollView.tile()
    native.viewport.scrollView.scrollerStyle = .legacy
    native.viewport.scrollView.tile()
    fixture.flush()
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt,
      "A retired layout must rebuild even when the width returns to its prior value")
  }
}
