import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class ViewportPracticeHostTests: XCTestCase {
  @MainActor private final class Counts {
    var generation = 0
    var completeRenders = 0
    var preparedRenders = 0
    var sourceReplies: [CheckedContinuation<Void, Never>] = []
    func finishFirstSource() { if !sourceReplies.isEmpty { sourceReplies.removeFirst().resume() } }
    func finishAllSources() { while !sourceReplies.isEmpty { finishFirstSource() } }
  }
  @MainActor private final class Fixture {
    static func verticalWheel(_ event: CGEvent) throws -> NSEvent {
      // This fixture models an unmodified vertical wheel. AppKit remaps a
      // Shift-bearing CGEvent to the horizontal axis during conversion.
      event.flags = []
      return try XCTUnwrap(NSEvent(cgEvent: event))
    }
    let suite = "ViewportPracticeHostTests.\(UUID())"
    let defaults: UserDefaults
    let settings: AppSettings
    let container: ModelContainer
    let host: NSHostingView<AnyView>
    let window: NSWindow
    let counts: Counts
    let prompt: String
    init(unicode: Bool = false, promptOverride: String? = nil,
      gatesSource: Bool = false, viewportEnabled: Bool = true, wordCount: Int = 201,
      hostSize: CGSize = .init(width: 1000, height: 720)) throws {
      // XCTest does not run NSApplicationMain. Initialize AppKit before the
      // hidden hierarchy so native wheel handling never depends on test order.
      _ = NSApplication.shared
      defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      settings = AppSettings(defaults: defaults)
      settings.reducePracticeMotion = true
      settings.showAllPracticeLines = true
      settings.testModifiers = [.noQuit]
      let configuration = TestConfiguration.words(wordCount).with(modifiers: [.noQuit])
      XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
        testParameterMemory: .legacyDefaults(configuration: configuration))))
      container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let prompt = promptOverride ?? (0..<wordCount).map { unicode && $0 == 1 ? "😀" : "word\($0)" }.joined(separator: " ")
      self.prompt = prompt
      let counts = Counts()
      self.counts = counts
      let content = TypebarApp.practiceContent(settings: settings,
        account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
        hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
        network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
        wholePreviewPrepare: { configuration, _, _ in
          counts.generation += 1
          if gatesSource { await withCheckedContinuation { counts.sourceReplies.append($0) } }
          return TypingSession(configuration: configuration, prompt: prompt)
        }, wholePreviewRender: { session, style in
          counts.preparedRenders += 1
          let plan = try await PromptRenderPlan.prepareCooperatively(session: session, composition: "", style: style)
          return try await plan.renderCooperatively()
        }, promptRender: { session, composition, style in
          counts.completeRenders += 1
          return PromptRenderPlan(session: session, composition: composition, style: style).render()
        }, wholePreviewViewportEnabled: viewportEnabled).modelContainer(container)
      host = NSHostingView(rootView: AnyView(content.frame(width: hostSize.width, height: hostSize.height)))
      window = NSWindow(contentRect: .init(origin: .zero, size: hostSize),
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
    var promptReady: Bool {
      guard let native = views(PromptViewportPracticeNativeView.self).first else { return false }
      return native.viewport.canvas.hasCompleteHeight
        && native.viewport.canvas.accessibilityValue() as? String == prompt
        && abs(native.frame.height - native.measuredHeight) < 0.01
        && (native.enclosingScrollView?.documentView?.frame.height ?? 0) >= native.frame.height
        && views(TypingInputView.self).first?.acceptsTextInput == true
    }
    var completePromptReady: Bool {
      views(PromptFieldNativeView.self).contains {
        $0.accessibilityValue() as? String == prompt
          && abs($0.bounds.height - $0.intrinsicContentSize.height) < 0.01
      } && views(TypingInputView.self).first?.acceptsTextInput == true
    }
    func completeLayout(width: CGFloat) throws -> PromptFieldTextLayout {
      let session = TypingSession(configuration: .words(201), prompt: prompt)
      let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
        accent: .blue, colorScheme: .light), fontSize: settings.fontSize)
      let map = try XCTUnwrap(PromptRenderPlan(session: session, composition: "", style: style).render().compositionTextMap)
      let font = settings.practiceFont.nsFont(size: settings.fontSize,
        installedFontName: settings.installedPracticeFontName, language: session.configuration.language)
      return PromptFieldTextLayout(map: map, width: width, font: font)
    }
    func waitUntil(_ ready: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
      flush()
      let deadline = Date().addingTimeInterval(15)
      while !ready() && Date() < deadline { flush() }
      let native = views(PromptViewportPracticeNativeView.self).first
      XCTAssertTrue(ready(), "Practice page did not reach the expected renderer: complete=\(native?.viewport.canvas.hasCompleteHeight as Any), frame=\(native?.frame as Any), measuredHeight=\(native?.measuredHeight as Any), input=\(views(TypingInputView.self).first?.acceptsTextInput as Any), pageBounds=\(native?.enclosingScrollView?.contentView.bounds as Any), pageDocument=\(native?.enclosingScrollView?.documentView?.frame as Any)", file: file, line: line)
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

  func testDefaultWholePromptKeepsRemoteReadingRowAcrossVisualFocusChanges() throws {
    try checkDefaultWholeFocus(unicode: false, usesComposition: false)
  }

  func testDefaultWholeUnicodePromptKeepsRemoteReadingRowDuringCompositionAndFocusChanges() throws {
    try checkDefaultWholeFocus(unicode: true, usesComposition: true)
  }

  private func checkDefaultWholeFocus(unicode: Bool, usesComposition: Bool) throws {
    let fixture = try Fixture(unicode: unicode, viewportEnabled: false)
    defer { fixture.close() }
    fixture.waitUntil { fixture.completePromptReady }
    let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    let page = try XCTUnwrap(full.enclosingScrollView)
    let document = try XCTUnwrap(page.documentView)
    let start = try XCTUnwrap(fixture.prompt.range(of: "word100")?.lowerBound)
    let anchor = fixture.prompt.distance(from: fixture.prompt.startIndex, to: start)
    let rect = try XCTUnwrap(full.measuredRect(for: anchor))
    let point = full.convert(rect.origin, to: document)
    page.contentView.scroll(to: point)
    page.reflectScrolledClipView(page.contentView)
    fixture.flush()
    let before = full.visibleRect.minY - rect.minY
    let unfocusedHeight = document.frame.height
    if usesComposition {
      input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
        replacementRange: .init(location: NSNotFound, length: 0))
    } else { input.onInsert("w", false) }
    fixture.waitUntil { document.frame.height < unfocusedHeight && !full.isAwaitingFallbackPosition }
    XCTAssertEqual(full.visibleRect.minY - rect.minY, before, accuracy: 1,
      "Entering visual focus must not move a manually chosen reading row")
    let focusedHeight = document.frame.height
    let mouse = try XCTUnwrap(fixture.views(TypingVisualFocusMouseView.self).first)
    mouse.onMovement(4, 0)
    fixture.waitUntil { document.frame.height > focusedHeight && !full.isAwaitingFallbackPosition }
    XCTAssertEqual(full.visibleRect.minY - rect.minY, before, accuracy: 1,
      "Leaving visual focus must preserve the same reading row")
    XCTAssertTrue(fixture.views(PromptFieldNativeView.self).first === full)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testWholePromptAtPageTopDoesNotIntroduceFocusNavigation() throws {
    let fixture = try Fixture(viewportEnabled: false)
    defer { fixture.close() }
    fixture.waitUntil { fixture.completePromptReady }
    let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    let page = try XCTUnwrap(full.enclosingScrollView)
    let height = try XCTUnwrap(page.documentView).frame.height
    XCTAssertEqual(page.contentView.bounds.minY, 0)
    try XCTUnwrap(fixture.views(TypingInputView.self).first).onInsert("w", false)
    fixture.waitUntil { (page.documentView?.frame.height ?? height) < height
      && !full.isAwaitingFallbackPosition }
    XCTAssertEqual(page.contentView.bounds.minY, 0,
      "A layout transition must not navigate an already top-aligned page")
    let focusedHeight = try XCTUnwrap(page.documentView).frame.height
    try XCTUnwrap(fixture.views(TypingInputView.self).first).onWindowFocusChanged(false, false)
    fixture.waitUntil { (page.documentView?.frame.height ?? focusedHeight) > focusedHeight
      && !full.isAwaitingFallbackPosition }
    XCTAssertEqual(page.contentView.bounds.minY, 0,
      "Direct retirement must not introduce page-top navigation either")
  }

  func testWindowAndAttachedSheetRetirementKeepTheWholePromptReadingRow() throws {
    for (isKey, attachedSheet) in [(false, false), (true, true), (false, true)] {
      let fixture = try Fixture(viewportEnabled: false)
      defer { fixture.close() }
      fixture.waitUntil { fixture.completePromptReady }
      let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
      let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
      let page = try XCTUnwrap(full.enclosingScrollView)
      let document = try XCTUnwrap(page.documentView)
      let initialHeight = document.frame.height
      input.onInsert("w", false)
      fixture.waitUntil { document.frame.height < initialHeight && !full.isAwaitingFallbackPosition }
      let start = try XCTUnwrap(fixture.prompt.range(of: "word100")?.lowerBound)
      let anchor = fixture.prompt.distance(from: fixture.prompt.startIndex, to: start)
      let rect = try XCTUnwrap(full.measuredRect(for: anchor))
      page.contentView.scroll(to: full.convert(rect.origin, to: document))
      page.reflectScrolledClipView(page.contentView)
      fixture.flush()
      let before = full.visibleRect.minY - rect.minY
      let focusedHeight = document.frame.height
      input.onWindowFocusChanged(isKey, attachedSheet)
      fixture.waitUntil { document.frame.height > focusedHeight && !full.isAwaitingFallbackPosition }
      XCTAssertEqual(full.visibleRect.minY - rect.minY, before, accuracy: 1,
        "Direct retirement must preserve the reading row; isKey=\(isKey), attachedSheet=\(attachedSheet)")
      let retiredHeight = document.frame.height
      input.onWindowFocusChanged(true, false)
      input.onInsert("o", false)
      fixture.waitUntil { document.frame.height < retiredHeight && !full.isAwaitingFallbackPosition
        && full.measuredMainCaretRect() == full.measuredRect(for: 2) }
      XCTAssertEqual(full.visibleRect.minY - rect.minY, before, accuracy: 1,
        "Refocus must continue the same input and reading position")
      XCTAssertTrue(fixture.views(PromptFieldNativeView.self).first === full)
      XCTAssertEqual(fixture.counts.generation, 1)
      XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
      XCTAssertFalse(fixture.window.isVisible)
    }
  }

  func testShortDefaultPracticeStillShowsThreeRowsAfterFocusEntry() throws {
    let fixture = try Fixture(viewportEnabled: false, hostSize: .init(width: 900, height: 530))
    defer { fixture.close() }
    fixture.settings.showAllPracticeLines = false
    fixture.waitUntil { fixture.views(PromptFieldNativeView.self).contains { $0.bounds.width > 1 }
      && fixture.views(TypingInputView.self).first?.acceptsTextInput == true }
    let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    let text = try XCTUnwrap(full.accessibilityValue() as? String)
    input.onInsert(String(try XCTUnwrap(text.first)), false)
    fixture.waitUntil { !fixture.settings.allowsRestartingConfigurationChange
      && full.convert(.zero, to: fixture.host).y < 300 }
    let frames = (0..<text.utf16.count).compactMap { full.measuredRect(for: $0) }
    let rows = Dictionary(grouping: frames, by: \.minY).sorted { $0.key < $1.key }.prefix(3)
    XCTAssertEqual(rows.count, 3)
    for row in rows {
      let rect = row.value.reduce(CGRect.null) { $0.union($1) }
      XCTAssertTrue(full.visibleRect.contains(rect))
      XCTAssertTrue(fixture.host.bounds.contains(full.convert(rect, to: fixture.host)),
        "Focused 900×530 practice must retain three complete on-screen rows")
    }
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testCompositionFallbackKeepsRemoteReadingPosition() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertTrue(native.viewport.scrollToField(100))
    fixture.waitUntil { native.viewport.visibleDocumentRect.minY > 0 }
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    let oldRect = try XCTUnwrap(native.viewport.canvas.measuredRect(for: anchor))
    let oldRowFraction = max(0, min(1,
      (native.viewport.visibleDocumentRect.minY - oldRect.minY) / oldRect.height))
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains {
        ($0.accessibilityValue() as? String)?.contains("中") == true
      } }
    let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    fixture.waitUntil { !full.isAwaitingFallbackPosition }
    let newRect = try XCTUnwrap(full.measuredRect(for: anchor))
    XCTAssertEqual(full.bounds.height, full.intrinsicContentSize.height, accuracy: 0.01,
      "The complete parent page must have adopted the replacement layout")
    XCTAssertEqual((full.visibleRect.minY - newRect.minY) / newRect.height, oldRowFraction, accuracy: 0.01,
      "A presentation fallback must not reset the manually chosen reading row: oldFrame=\(native.frame) oldRect=\(oldRect) anchor=\(anchor) frame=\(full.frame) size=\(full.intrinsicContentSize) visible=\(full.visibleRect) rect=\(newRect) page=\(full.enclosingScrollView?.contentView.bounds as Any)")
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertEqual(native.viewport.measuredFieldCount, 0)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
  }

  func testCompositionFallbackDuringReflowKeepsThePendingReadingAnchor() throws {
    let fixture = try Fixture(wordCount: 2_001)
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertTrue(native.viewport.scrollToField(100))
    fixture.waitUntil { native.viewport.visibleDocumentRect.minY > 0 }
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    let oldRect = try XCTUnwrap(native.viewport.canvas.measuredRect(for: anchor))
    let oldRowFraction = max(0, min(1,
      (native.viewport.visibleDocumentRect.minY - oldRect.minY) / oldRect.height))
    fixture.settings.fontSize = 36
    fixture.waitUntil { native.viewport.isPreparing && !native.viewport.canvas.hasCompleteHeight }
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains {
        ($0.accessibilityValue() as? String)?.contains("中") == true
      } }
    let full = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    fixture.waitUntil { !full.isAwaitingFallbackPosition }
    let rect = try XCTUnwrap(full.measuredRect(for: anchor))
    XCTAssertEqual((full.visibleRect.minY - rect.minY) / rect.height, oldRowFraction, accuracy: 0.01,
      "Fallback must carry the pending source anchor across new font geometry")
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertEqual(native.viewport.measuredFieldCount, 0)
  }

  func testActualPracticeInputRepaintsViewportAndKeepsRemotePosition() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
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
    fixture.waitUntil { native.viewport.visibleDocumentRect.minY > 0 }
    let origin = native.viewport.visibleDocumentRect.minY
    input.onInsert("o", false)
    fixture.flush()
    XCTAssertEqual(native.viewport.visibleDocumentRect.minY, origin)
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt)
    native.viewport.scrollToTop()
    XCTAssertEqual(native.viewport.canvas.measuredMainCaretRect(style: .bar), native.viewport.canvas.measuredRect(for: 2))
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testAdmittedSourceSkipsUnusedCompletePreparationButFallbackAndDefaultKeepIt() throws {
    do {
      let fixture = try Fixture()
      defer { fixture.close() }
      fixture.waitUntil { fixture.promptReady }
      XCTAssertEqual(fixture.counts.preparedRenders, 0)
      XCTAssertEqual(fixture.counts.generation, 1)
    }
    for enabled in [false, true] {
      let fixture = try Fixture(unicode: enabled, viewportEnabled: enabled)
      defer { fixture.close() }
      fixture.waitUntil { fixture.views(PromptFieldNativeView.self).contains {
        $0.accessibilityValue() as? String == fixture.prompt
      } }
      XCTAssertEqual(fixture.counts.preparedRenders, 1)
      XCTAssertEqual(fixture.counts.generation, 1)
      XCTAssertTrue(fixture.views(PromptViewportPracticeNativeView.self).isEmpty)
    }
  }

  func testSourceOnlyRestartKeepsInputLockedAndRejectsLateOldGeneration() throws {
    let fixture = try Fixture(gatesSource: true)
    defer { fixture.counts.finishAllSources(); fixture.close() }
    fixture.waitUntil { fixture.counts.generation == 1 && fixture.counts.sourceReplies.count == 1 }
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertFalse(input.acceptsTextInput)
    input.onInsert("x", false)
    XCTAssertTrue(fixture.settings.allowsRestartingConfigurationChange)
    input.onRestart()
    fixture.waitUntil { fixture.counts.generation == 2 && fixture.counts.sourceReplies.count == 2 }
    fixture.counts.finishFirstSource()
    fixture.flush()
    XCTAssertTrue(fixture.views(PromptViewportPracticeNativeView.self).isEmpty)
    XCTAssertFalse(input.acceptsTextInput)
    XCTAssertEqual(fixture.counts.preparedRenders, 0)
    fixture.settings.fontSize = 36
    fixture.counts.finishFirstSource()
    fixture.waitUntil { fixture.promptReady }
    let activeInput = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertTrue(activeInput.acceptsTextInput)
    activeInput.onInsert("w", false)
    fixture.waitUntil { !fixture.settings.allowsRestartingConfigurationChange }
    XCTAssertEqual(fixture.counts.generation, 2)
    XCTAssertEqual(fixture.counts.preparedRenders, 0)
  }

  func testSourcePublicationDoesNotUnlockInputBeforePageLayoutIsAdopted() throws {
    let fixture = try Fixture(gatesSource: true, wordCount: 2_001)
    defer { fixture.counts.finishAllSources(); fixture.close() }
    fixture.waitUntil { fixture.counts.sourceReplies.count == 1 }
    fixture.counts.finishFirstSource()
    let deadline = Date().addingTimeInterval(15)
    var checkedUnreadyPage = false
    while !fixture.promptReady && Date() < deadline {
      fixture.flush()
      if !checkedUnreadyPage, !fixture.promptReady,
        !fixture.views(PromptViewportPracticeNativeView.self).isEmpty {
        checkedUnreadyPage = true
        let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
        XCTAssertFalse(input.acceptsTextInput, "Source completion is not page-layout readiness")
        input.onInsert("x", false)
        XCTAssertTrue(fixture.settings.allowsRestartingConfigurationChange,
          "A key delivered before publication must not start the attempt")
      }
    }
    XCTAssertTrue(checkedUnreadyPage, "Exercise the actual source-to-page handoff")
    fixture.waitUntil { fixture.promptReady }
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertTrue(input.acceptsTextInput)
    input.onInsert("w", false)
    fixture.waitUntil { !fixture.settings.allowsRestartingConfigurationChange }
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testRestartWhileAwaitingPagePublicationCannotUnlockTheReplacementSource() throws {
    let fixture = try Fixture(gatesSource: true, wordCount: 2_001)
    defer { fixture.counts.finishAllSources(); fixture.close() }
    fixture.waitUntil { fixture.counts.sourceReplies.count == 1 }
    fixture.counts.finishFirstSource()
    fixture.waitUntil { !fixture.views(PromptViewportPracticeNativeView.self).isEmpty }
    XCTAssertFalse(fixture.promptReady)
    let old = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onRestart()
    fixture.waitUntil { fixture.counts.generation == 2 && fixture.counts.sourceReplies.count == 1 }
    XCTAssertEqual(old.viewport.measuredFieldCount, 0)
    let replacement = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertFalse(replacement.acceptsTextInput)
    replacement.onInsert("x", false)
    XCTAssertTrue(fixture.settings.allowsRestartingConfigurationChange)
    fixture.counts.finishFirstSource()
    fixture.waitUntil { fixture.promptReady }
    XCTAssertTrue(fixture.views(TypingInputView.self).first?.acceptsTextInput == true)
    XCTAssertEqual(fixture.counts.generation, 2)
  }

  func testSynchronousShortSourceUsesTheSamePublicationGateAndCanStart() throws {
    let fixture = try Fixture(wordCount: 25)
    defer { fixture.close() }
    fixture.waitUntil { !fixture.views(PromptViewportPracticeNativeView.self).isEmpty }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    if abs(native.frame.height - native.measuredHeight) >= 0.01 {
      XCTAssertFalse(input.acceptsTextInput)
    }
    fixture.waitUntil { native.viewport.canvas.hasCompleteHeight
      && abs(native.frame.height - native.measuredHeight) < 0.01
      && input.acceptsTextInput }
    let text = try XCTUnwrap(native.viewport.canvas.accessibilityValue() as? String)
    let first = try XCTUnwrap(text.first)
    input.onInsert(String(first), false)
    fixture.waitUntil { !fixture.settings.allowsRestartingConfigurationChange }
    XCTAssertEqual(fixture.counts.generation, 0, "Short sources must not enter the asynchronous generator")
  }

  func testDisablingWholeDisplayWhileAwaitingPublicationRestoresCompleteInputPath() throws {
    let fixture = try Fixture(gatesSource: true, wordCount: 2_001)
    defer { fixture.counts.finishAllSources(); fixture.close() }
    fixture.waitUntil { fixture.counts.sourceReplies.count == 1 }
    fixture.counts.finishFirstSource()
    fixture.waitUntil { !fixture.views(PromptViewportPracticeNativeView.self).isEmpty }
    XCTAssertFalse(fixture.promptReady)
    let old = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    fixture.settings.showAllPracticeLines = false
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(TypingInputView.self).first?.acceptsTextInput == true
      && !fixture.views(PromptFieldNativeView.self).isEmpty }
    XCTAssertEqual(old.viewport.measuredFieldCount, 0)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onInsert("w", false)
    fixture.waitUntil { !fixture.settings.allowsRestartingConfigurationChange }
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testAdmittedInputAvoidsCompleteRendererButCompositionFallbackUsesIt() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    let before = fixture.counts.completeRenders
    input.onInsert("w", false)
    fixture.waitUntil { fixture.promptReady
      && native.viewport.canvas.measuredMainCaretRect(style: .bar) == native.viewport.canvas.measuredRect(for: 1) }
    XCTAssertEqual(fixture.counts.completeRenders, before,
      "An admitted display must not also construct the complete prompt after input")
    XCTAssertNotNil(native.viewport.canvas.renderedCellText(for: 0))
    input.onDelete()
    fixture.waitUntil { fixture.promptReady
      && native.viewport.canvas.measuredMainCaretRect(style: .bar) == native.viewport.canvas.measuredRect(for: 0) }
    input.onInsert("w", false)
    fixture.waitUntil { fixture.promptReady
      && native.viewport.canvas.measuredMainCaretRect(style: .bar) == native.viewport.canvas.measuredRect(for: 1) }
    XCTAssertEqual(fixture.counts.completeRenders, before,
      "Deleting and retyping must not rebuild unused complete presentation")
    let ink = native.viewport.canvas.renderedCellText(for: 0)
    fixture.settings.flipTestColors.toggle()
    fixture.waitUntil { fixture.promptReady && native.viewport.canvas.renderedCellText(for: 0) != ink }
    XCTAssertEqual(fixture.counts.completeRenders, before,
      "Appearance changes must repaint admitted ink without the complete renderer")
    input.setMarkedText("中", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.contains("中") == true } }
    XCTAssertGreaterThan(fixture.counts.completeRenders, before)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
  }

  func testWholePromptExpandsToExactHeightAndUsesThePageScroller() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let full = try fixture.completeLayout(width: native.viewport.layoutWidth)
    fixture.waitUntil { native.viewport.canvas.hasCompleteHeight }
    XCTAssertEqual(native.frame.height, full.size.height, accuracy: 0.01)
    XCTAssertFalse(native.viewport.scrollView.hasVerticalScroller, "Only the page may scroll the full prompt")
    let page = try XCTUnwrap(native.enclosingScrollView)
    let document = try XCTUnwrap(page.documentView)
    XCTAssertTrue(NSLocationInRange(0, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    let lastID = fixture.prompt.utf16.count - 1
    let last = try XCTUnwrap(full.cellFrames[lastID])
    let pageRect = native.viewport.canvas.convert(last, to: document)
    var bounds = page.contentView.bounds
    bounds.origin.y = pageRect.minY
    page.contentView.scroll(to: page.contentView.constrainBoundsRect(bounds).origin)
    page.reflectScrolledClipView(page.contentView)
    fixture.flush()
    XCTAssertTrue(NSLocationInRange(lastID, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertLessThan(native.viewport.retainedWindowCount, 7, "An expanded page must not retain every drawing window")
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testPageHeightMatchesShortMultilineAndOversizedFieldPrompts() throws {
    for prompt in ["oak", "oak\n\npine\n", String(repeating: "a", count: 240) + " tail"] {
      let fixture = try Fixture(promptOverride: prompt)
      defer { fixture.close() }
      fixture.waitUntil { fixture.promptReady }
      let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
      let full = try fixture.completeLayout(width: native.viewport.layoutWidth)
      XCTAssertEqual(native.frame.height, full.size.height, accuracy: 0.01, prompt)
      XCTAssertEqual(native.viewport.canvas.frame.height, full.size.height, accuracy: 0.01, prompt)
      XCTAssertEqual(native.viewport.canvas.accessibilityNumberOfCharacters(), prompt.utf16.count)
      XCTAssertFalse(native.viewport.scrollView.hasVerticalScroller)
      if prompt == "oak" { XCTAssertLessThan(native.frame.height, 184, "A short prompt must shrink to its actual height") }
    }
  }

  func testWheelOverPromptScrollsPageWithoutMovingInnerClipOrReplacingInput() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertTrue(fixture.window.makeFirstResponder(input))
    input.onInsert("w", false)
    fixture.waitUntil { fixture.promptReady }
    let page = try XCTUnwrap(native.enclosingScrollView)
    for style: NSScroller.Style in [.overlay, .legacy] {
      page.scrollerStyle = style
      page.tile()
      fixture.waitUntil { fixture.promptReady }
      native.viewport.scrollToTop()
      fixture.flush()
      let before = page.contentView.bounds.minY
      let down = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
        wheelCount: 1, wheel1: -8, wheel2: 0, wheel3: 0))
      native.viewport.scrollView.scrollWheel(with: try Fixture.verticalWheel(down))
      fixture.waitUntil { page.contentView.bounds.minY > before }
      let afterDown = page.contentView.bounds.minY
      let up = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
        wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0))
      native.viewport.scrollView.scrollWheel(with: try Fixture.verticalWheel(up))
      fixture.waitUntil { page.contentView.bounds.minY < afterDown }
      XCTAssertEqual(native.viewport.scrollView.contentView.bounds.minY, 0,
        "The full-height inner container must not consume page scrolling")
    }
    XCTAssertTrue(fixture.window.firstResponder === input)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt)
    XCTAssertFalse(fixture.window.isVisible)
  }

  func testSyntheticVerticalWheelFixtureRemovesAmbientModifiersBeforeAppKitConversion() throws {
    for flags: CGEventFlags in [[], .maskShift, .maskControl, .maskAlternate, .maskCommand] {
      let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line,
        wheelCount: 1, wheel1: 8, wheel2: 0, wheel3: 0))
      cg.flags = flags
      let event = try Fixture.verticalWheel(cg)
      XCTAssertEqual(event.scrollingDeltaY, 8)
      XCTAssertTrue(event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty)
    }
  }

  func testCompositionUsesCompleteRendererAndRetiresViewportWithoutResettingAttempt() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
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
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    XCTAssertEqual(fixture.counts.preparedRenders, 0)
    let completeBefore = fixture.counts.completeRenders
    input.onInsert("word0xx", false)
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && fixture.views(PromptFieldNativeView.self).contains { ($0.accessibilityValue() as? String)?.hasPrefix("word0xx") == true } }
    XCTAssertEqual(native.viewport.measuredFieldCount, 0)
    XCTAssertGreaterThan(fixture.counts.completeRenders, completeBefore)
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testViewportBatchKeepsFittingExtrasButRejectsWordHeightGrowthBeforeFallback() throws {
    for viewportEnabled in [true, false] {
      try checkBatchWrapAdmission(viewportEnabled: viewportEnabled)
    }
  }

  private func checkBatchWrapAdmission(viewportEnabled: Bool) throws {
    let prompt = String(repeating: "a", count: 28) + " tail"
    let fixture = try Fixture(promptOverride: prompt, viewportEnabled: viewportEnabled)
    defer { fixture.close() }
    fixture.settings.customPracticeLineColumns = 30
    fixture.settings.practiceLineWidth = .custom
    fixture.waitUntil { viewportEnabled ? fixture.promptReady : fixture.views(PromptFieldNativeView.self).contains {
      $0.accessibilityValue() as? String == prompt
    } }
    let widthView: NSView = viewportEnabled
      ? try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first).viewport.canvas
      : try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    let font = fixture.settings.practiceFont.nsFont(size: fixture.settings.fontSize,
      installedFontName: fixture.settings.installedPracticeFontName, language: .english)
    let style = PromptRenderStyle(theme: .init(background: .white, panel: .white,
      accent: .blue, colorScheme: .light), fontSize: fixture.settings.fontSize)
    let width = widthView.bounds.width
    var expected = TypingSession(configuration: .words(201).with(modifiers: [.noQuit]), prompt: prompt)
    let data = String(repeating: "a", count: 28) + String(repeating: "x", count: 12)
    expected.insertBatch(data, at: .now, wrapAdmission: .init { current, candidate in
      PromptInputWrapGeometry.rejects(session: current, candidate: candidate,
        rendering: PromptRenderPlan(session: current, composition: "", style: style).render(),
        width: width, font: font, lineSpacing: 12, isRightToLeft: false)
    })
    XCTAssertGreaterThan(expected.typed.count, 28, "The fitting extras must still be accepted")
    XCTAssertLessThan(expected.typed.count, data.count, "The oracle must exercise a real wrap rejection")
    let expectedText = String(PromptRenderPlan(session: expected, composition: "", style: style).render().text.characters)
    input.onInsert(data, false)
    fixture.waitUntil { fixture.views(PromptViewportPracticeNativeView.self).isEmpty
      && !fixture.views(PromptFieldNativeView.self).isEmpty }
    XCTAssertEqual(fixture.views(PromptFieldNativeView.self).first?.accessibilityValue() as? String, expectedText,
      "viewportEnabled=\(viewportEnabled)")
    fixture.settings.customPracticeLineColumns = 60
    fixture.waitUntil { (fixture.views(PromptFieldNativeView.self).first?.bounds.width ?? 0) > width }
    let expandedWidth = try XCTUnwrap(fixture.views(PromptFieldNativeView.self).first).bounds.width
    let more = String(repeating: "x", count: 10)
    expected.insertBatch(more, at: .now, wrapAdmission: .init { current, candidate in
      PromptInputWrapGeometry.rejects(session: current, candidate: candidate,
        rendering: PromptRenderPlan(session: current, composition: "", style: style).render(),
        width: expandedWidth, font: font, lineSpacing: 12, isRightToLeft: false)
    })
    XCTAssertEqual(expected.typed.count, 40, "Widening must allow the formerly rejected extras")
    try XCTUnwrap(fixture.views(TypingInputView.self).first).onInsert(more, false)
    let expandedText = String(PromptRenderPlan(session: expected, composition: "", style: style).render().text.characters)
    fixture.waitUntil { fixture.views(PromptFieldNativeView.self).first?.accessibilityValue() as? String == expandedText }
    XCTAssertFalse(fixture.settings.allowsRestartingConfigurationChange)
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testRemoteReadingPositionAndSelectionSurviveFontAndWidthChanges() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let selected = NSRange(location: 730, length: 3)
    native.viewport.canvas.setAccessibilitySelectedTextRange(selected)
    fixture.flush()
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    let oldRowHeight = try XCTUnwrap(native.viewport.canvas.measuredRect(for: anchor)).height
    let oldWidth = native.frame.width
    XCTAssertNotEqual(anchor, NSNotFound)
    XCTAssertGreaterThan(native.viewport.visibleDocumentRect.minY, 0)
    fixture.settings.fontSize = 36
    fixture.waitUntil { fixture.promptReady
      && (native.viewport.canvas.measuredRect(for: anchor)?.height ?? 0) > oldRowHeight
      && NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()) }
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()),
      "Reflow must keep the reading row, not return to the first batch")
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    fixture.settings.customPracticeLineColumns = 30
    fixture.settings.practiceLineWidth = .custom
    fixture.waitUntil { fixture.promptReady && native.frame.width < oldWidth
      && NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()) }
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    let page = try XCTUnwrap(native.enclosingScrollView)
    page.scrollerStyle = .legacy
    page.tile()
    fixture.waitUntil { fixture.promptReady && native.viewport.canvas.accessibilitySelectedTextRange() == selected }
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()),
      "anchor=\(anchor) visible=\(native.viewport.canvas.accessibilityVisibleCharacterRange()) rect=\(native.viewport.visibleDocumentRect)")
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    XCTAssertEqual(fixture.counts.generation, 1)
    XCTAssertEqual(native.viewport.measuredFieldCount, 201, "Expanded page height requires complete measurement")
    XCTAssertFalse(fixture.window.isVisible)
    let input = try XCTUnwrap(fixture.views(TypingInputView.self).first)
    input.onRestart()
    fixture.waitUntil { fixture.counts.generation == 2
      && fixture.promptReady }
    let restarted = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    XCTAssertEqual(restarted.viewport.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
    XCTAssertEqual(restarted.viewport.visibleDocumentRect.minY, 0)
    XCTAssertEqual(native.viewport.measuredFieldCount, 0, "Restart must retire the former display owner")
  }

  func testManualRemoteScrollWithoutSelectionSurvivesReflow() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    XCTAssertTrue(native.viewport.scrollToField(100))
    fixture.waitUntil { !native.viewport.isPreparing && native.viewport.visibleDocumentRect.minY > 0 }
    let anchor = native.viewport.canvas.accessibilityVisibleCharacterRange().location
    XCTAssertNotEqual(anchor, NSNotFound)
    fixture.settings.fontSize = 36
    fixture.waitUntil { fixture.promptReady && NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()) }
    XCTAssertTrue(NSLocationInRange(anchor, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), .init(location: NSNotFound, length: 0))
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testExternalPageNavigationDuringReflowSupersedesOldReadingAnchor() throws {
    let fixture = try Fixture(wordCount: 2_001)
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let page = try XCTUnwrap(native.enclosingScrollView)
    let selected = NSRange(location: 730, length: 3)
    native.viewport.canvas.setAccessibilitySelectedTextRange(selected)
    fixture.waitUntil { page.contentView.bounds.minY > 0 }
    fixture.settings.fontSize = 36
    fixture.waitUntil { native.viewport.isPreparing && !native.viewport.canvas.hasCompleteHeight }
    page.contentView.scroll(to: .zero)
    page.reflectScrolledClipView(page.contentView)
    XCTAssertEqual(page.contentView.bounds.minY, 0)
    fixture.waitUntil { fixture.promptReady }
    XCTAssertEqual(page.contentView.bounds.minY, 0,
      "Reflow must not undo the newer page navigation")
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected,
      "Cancelling position restoration must not erase the independent selection")
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testNewSelectionDuringReflowSupersedesSavedSelectionAndPosition() throws {
    let fixture = try Fixture(wordCount: 2_001)
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    native.viewport.canvas.setAccessibilitySelectedTextRange(.init(location: 730, length: 3))
    fixture.waitUntil { native.viewport.visibleDocumentRect.minY > 0 }
    fixture.settings.fontSize = 36
    fixture.waitUntil { native.viewport.isPreparing && !native.viewport.canvas.hasCompleteHeight }
    let selected = NSRange(location: 0, length: 2)
    native.viewport.canvas.setAccessibilitySelectedTextRange(selected)
    let selectedOrigin = try XCTUnwrap(native.enclosingScrollView).contentView.bounds.minY
    fixture.waitUntil { fixture.promptReady }
    XCTAssertEqual(native.viewport.canvas.accessibilitySelectedTextRange(), selected)
    XCTAssertEqual(native.enclosingScrollView?.contentView.bounds.minY, selectedOrigin)
    XCTAssertTrue(NSLocationInRange(0, native.viewport.canvas.accessibilityVisibleCharacterRange()))
    XCTAssertEqual(fixture.counts.generation, 1)
  }

  func testFontAndLineWidthChangesUseVisibleWidthIncludingLegacyScroller() throws {
    let fixture = try Fixture()
    defer { fixture.close() }
    fixture.waitUntil { fixture.promptReady }
    let native = try XCTUnwrap(fixture.views(PromptViewportPracticeNativeView.self).first)
    let oldRect = try XCTUnwrap(native.viewport.canvas.measuredRect(for: 0))
    let oldWidth = native.bounds.width
    fixture.settings.fontSize = 36
    fixture.settings.customPracticeLineColumns = 30
    fixture.settings.practiceLineWidth = .custom
    fixture.waitUntil { native.viewport.canvas.measuredRect(for: 0).map { $0.height > oldRect.height } == true
      && native.bounds.width < oldWidth }
    let page = try XCTUnwrap(native.enclosingScrollView)
    page.scrollerStyle = .legacy
    page.tile()
    fixture.flush()
    XCTAssertLessThan(page.contentView.bounds.width, page.bounds.width)
    XCTAssertEqual(native.viewport.canvas.frame.width, native.viewport.scrollView.contentView.bounds.width)
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt)
    page.scrollerStyle = .overlay
    page.tile()
    page.scrollerStyle = .legacy
    page.tile()
    fixture.flush()
    XCTAssertEqual(native.viewport.canvas.accessibilityValue() as? String, fixture.prompt,
      "A retired layout must rebuild even when the width returns to its prior value")
  }
}
