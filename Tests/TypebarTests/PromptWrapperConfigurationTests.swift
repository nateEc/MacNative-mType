import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PromptWrapperConfigurationTests: XCTestCase {
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
    let name = "TypebarTests.PromptWrapper.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    try body(AppSettings(defaults: defaults), defaults)
  }

  private var changes: [(String, (AppSettings) -> Void)] {
    [
      ("highlightMode", { $0.promptHighlightMode = .off }),
      ("typedEffect", { $0.typedCharacterEffect = .hide }),
      ("blindMode", { $0.blindMode = true }),
      ("indicateTypos", { $0.typoIndicatorStyle = .below }),
      ("tapeMode", { $0.practiceTapeMode = .word }),
      ("hideExtraLetters", { $0.hideExtraLetters = true }),
      ("flipTestColors", { $0.flipTestColors = true }),
      ("colorfulMode", { $0.colorfulMode = true }),
      ("showAllLines", { $0.showAllPracticeLines = true }),
      ("fontSize", { $0.fontSize = 32 }),
      ("maxLineWidth", { $0.customPracticeLineColumns = 70 }),
      ("tapeMargin", { $0.practiceTapeMargin = 0.4 }),
      ("keymapSize", { $0.keyboardGuideScale = 1.5 }),
    ]
  }

  func testEveryWrapperSettingProducesAnObservablePresentationEvent() throws {
    try withSettings { settings, _ in
      for (key, change) in changes {
        let before = settings.practiceWrapperRevision
        change(settings)
        XCTAssertEqual(settings.practiceWrapperRevision, before + 1, key)
      }
    }
  }

  func testSameValueAndCoalescedABAStillProduceEventsButFontFamilyAndThemeDoNot() throws {
    try withSettings { settings, _ in
      let before = settings.practiceWrapperRevision
      settings.hideExtraLetters = false
      settings.hideExtraLetters = true
      settings.hideExtraLetters = false
      XCTAssertEqual(settings.practiceWrapperRevision, before + 3)
      let after = settings.practiceWrapperRevision
      settings.practiceFont = .serif
      settings.installedPracticeFontName = "Georgia"
      settings.theme = .paper
      settings.smoothPracticeLineScroll = true
      XCTAssertEqual(settings.practiceWrapperRevision, after)
    }
  }

  func testLineWidthPresetAndCustomWidthBothDispatchWithoutPersistingTheEventCounter() throws {
    try withSettings { settings, defaults in
      let before = settings.practiceWrapperRevision
      settings.practiceLineWidth = .custom
      settings.customPracticeLineColumns = 70
      XCTAssertEqual(settings.practiceWrapperRevision, before + 2)
      let reload = AppSettings(defaults: defaults)
      XCTAssertEqual(reload.practiceLineWidth, .custom)
      XCTAssertEqual(reload.customPracticeLineColumns, 70)
      for key in [AppSettings.legacyStorageKey, AppSettings.expandedPaceStorageKey, AppSettings.accountPaceStorageKey] {
        if let data = defaults.data(forKey: key) {
          let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
          XCTAssertNil(object["practiceWrapperRevision"])
        }
      }
    }
  }

  func testFunboxRejectedHighlightAndUIRestorationDoNotDispatchWrapperEvents() throws {
    try withSettings { settings, _ in
      settings.testModifiers = [.readAhead]
      let before = settings.practiceWrapperRevision
      settings.promptHighlightMode = .word
      settings.promptHighlightMode = .letter // Existing presentation guard restores the previous value.
      XCTAssertEqual(settings.practiceWrapperRevision, before)
      settings.promptHighlightMode = .off
      XCTAssertEqual(settings.practiceWrapperRevision, before + 1)
      settings.testModifiers = []
      settings.promptHighlightMode = .word
      XCTAssertEqual(settings.practiceWrapperRevision, before + 2)
    }
  }

  func testNormalizedFontAndKeyboardSizeStillDispatchAndPersistExactlyOnce() throws {
    try withSettings { settings, defaults in
      let before = settings.practiceWrapperRevision
      settings.fontSize = 0
      XCTAssertEqual(settings.fontSize, PracticeFontSizePolicy.minimumSize)
      XCTAssertEqual(settings.practiceWrapperRevision, before + 1)
      settings.keyboardGuideScale = 99
      XCTAssertEqual(settings.keyboardGuideScale, KeyboardGuideScalePolicy.normalized(99))
      XCTAssertEqual(settings.practiceWrapperRevision, before + 2)
      let reload = AppSettings(defaults: defaults)
      XCTAssertEqual(reload.fontSize, settings.fontSize)
      XCTAssertEqual(reload.keyboardGuideScale, settings.keyboardGuideScale)
    }
  }

  private final class Document: NSView { override var isFlipped: Bool { true } }

  func testFontFamilyOnlyRemeasuresButNextWrapperEventRetiresTheNewlyWrappedPrefix() throws {
    let system = NSFont.systemFont(ofSize: 28)
    let mono = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let text = AttributedString("iiii iiii iiii iiii iiii iiii")
    let words = (0..<6).map { PromptLineScrollWord(index: $0, glyphID: $0 * 5) }
    let offsets = Dictionary(uniqueKeysWithValues: (0..<6).map { ($0 * 5, $0 * 5) })
    let first = try XCTUnwrap(PromptLineScrollGeometry.measure(in: text, activeOffset: 20,
      previousOffset: nil, width: 240, font: system, lineSpacing: 12, rightToLeft: false))
    let second = try XCTUnwrap(PromptLineScrollGeometry.measure(in: text, activeOffset: 20,
      previousOffset: nil, width: 240, font: mono, lineSpacing: 12, rightToLeft: false))
    XCTAssertEqual(first.activeTop, 0)
    XCTAssertGreaterThan(second.activeTop, 45)
    let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 240, height: 135))
    let document = Document(frame: .init(x: 0, y: 0, width: 240, height: 600))
    scroll.documentView = document
    let follower = PromptAutoScrollView(frame: document.bounds); document.addSubview(follower)
    defer { follower.removeFromSuperview() }
    let attempt = UUID()
    var retired: [PromptWordRetirement] = []
    func update(_ font: NSFont, revision: UInt64) {
      follower.update(text: text, characterOffset: 20, font: font, lineSpacing: 12, isRightToLeft: false,
        lineScroll: .init(attemptID: attempt, activeWordID: 20, characterOffsets: offsets,
          smoothScroll: false, reducesMotion: false, words: words, onRetire: { retired.append($0) },
          wrapperRevision: revision))
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    update(system, revision: 0)
    XCTAssertTrue(retired.isEmpty)
    update(mono, revision: 0)
    XCTAssertTrue(retired.isEmpty, "Source fontFamily applies font and joining, not updateWordWrapperClasses")
    retired.removeAll()
    update(mono, revision: 1)
    XCTAssertEqual(retired, [.init(attemptID: attempt, firstRetainedWordIndex: 2)],
      "A color/highlight-only wrapper event must center even with unchanged text, font and active word")
  }

  func testPinnedSetterSubscriberAndResizeFixturesMatchNativeInteractiveEvents() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference checkout")
    }
    struct Fixture: Decodable {
      let key: String, showAllLines: Bool, nosave: Bool, boundary: Int
    }
    struct Output: Decodable { let cases: [Fixture], repeatedEvents: Int, rejectedEvents: Int }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), out = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-wrapper-configuration.mjs").path, reference, "--emit-fixtures"]
    process.standardOutput = out
    try process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.cases.count, 64)
    XCTAssertEqual(output.repeatedEvents, 4); XCTAssertEqual(output.rejectedEvents, 0)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let text = AttributedString("a\nb\nc\nd\ne\nf")
    let offsets = Dictionary(uniqueKeysWithValues: (0..<6).map { ($0 * 2, $0 * 2) })
    // Native interactive settings have no nosave option. Source nosave cases
    // still run above, but do not imply native import/preview scheduling parity.
    for value in output.cases where !value.nosave {
      try withSettings { settings, _ in
        settings.showAllPracticeLines = value.showAllLines
        let scroll = NSScrollView(frame: .init(x: 0, y: 0, width: 240, height: 135))
        let document = Document(frame: .init(x: 0, y: 0, width: 240, height: 600))
        scroll.documentView = document
        let follower = PromptAutoScrollView(frame: document.bounds); document.addSubview(follower)
        defer { follower.removeFromSuperview() }
        let attempt = UUID()
        var retired: [PromptWordRetirement] = []
        @MainActor func update(notify: Bool) {
          follower.update(text: text, characterOffset: 6, font: font, lineSpacing: 12, isRightToLeft: false,
            lineScroll: .init(attemptID: attempt, activeWordID: 6, characterOffsets: offsets,
              smoothScroll: false, reducesMotion: false,
              words: (0..<6).map { .init(index: $0, glyphID: $0 * 2) },
              onRetire: notify ? { retired.append($0) } : nil,
              centersActiveLine: !settings.showAllPracticeLines, wrapperRevision: settings.practiceWrapperRevision))
          RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        update(notify: false)
        if value.key == "showAllLines" { settings.showAllPracticeLines = value.showAllLines }
        else if let change = changes.first(where: { $0.0 == value.key }) { change.1(settings) }
        else if value.key == "fontFamily" { settings.practiceFont = .serif }
        else if value.key == "theme" { settings.theme = .paper }
        else if value.key == "smoothLineScroll" { settings.smoothPracticeLineScroll = false }
        else { XCTFail("Unmapped source fixture \(value.key)") }
        update(notify: true)
        XCTAssertEqual(retired.last?.firstRetainedWordIndex ?? 0, value.boundary, "\(value.key), raw show-all \(value.showAllLines)")
      }
    }
  }

  @Observable final class Model {
    let settings: AppSettings
    let asl: Bool
    var session: TypingSession
    let word: String
    init(settings: AppSettings, asl: Bool) {
      self.settings = settings; self.asl = asl
      // TextKit may break between punctuation characters. ASCII letters give
      // ordinary Text a whole-word witness; punctuation exercises ASL fallback.
      word = asl ? "!!!!" : "iiii"
      session = TypingSession(configuration: .words(6, rules: .init(freedomMode: true)),
        prompt: Array(repeating: word, count: 6).joined(separator: " "))
    }
    var rendering: PromptRendering {
      let glyphs = session.promptGlyphs
      return PromptRendering.make(glyphs: glyphs,
        indices: PromptGlyphLayout.indices(glyphs: glyphs, words: session.promptWordPresentations,
          hideExtraLetters: false, firstRetainedWordIndex: session.firstRetainedPromptWordIndex)) { _, glyph in
        var text = AttributedString(PromptControlCharacterPresentation.plan(for: glyph, style: .off).text)
        text.foregroundColor = .black
        return text
      }
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let settings = model.settings, rendering = model.rendering, words = model.session.promptWordPresentations
      let font = settings.practiceFont == .defaultSystem ? NSFont.systemFont(ofSize: settings.fontSize)
        : NSFont.monospacedSystemFont(ofSize: settings.fontSize, weight: .regular)
      let context = PromptLineScrollContext(attemptID: model.session.automaticInputAttemptID,
        activeWordID: words.first(where: { $0.phase == .active })?.range.lowerBound,
        characterOffsets: rendering.glyphCharacterOffsets, smoothScroll: true, reducesMotion: false,
        words: words.enumerated().map { .init(index: $0.offset, glyphID: $0.element.range.lowerBound) },
        firstRetainedWordIndex: model.session.firstRetainedPromptWordIndex,
        onRetire: { model.session.retirePromptWords($0) }, centersActiveLine: !settings.showAllPracticeLines,
        wrapperRevision: settings.practiceWrapperRevision)
      PracticePromptViewport(text: rendering.text, font: font, lineSpacing: 12, isRightToLeft: false,
        lineCount: 3, measuresTextRows: !model.asl, measuresCustomRows: model.asl) {
        if model.asl {
          ASLPracticePrompt(glyphs: model.session.promptGlyphsInDisplayOrder,
            fontSize: settings.fontSize, accent: .blue,
            glyphIDs: PromptGlyphLayout.indices(glyphs: model.session.promptGlyphs, words: words, hideExtraLetters: false),
            rendering: rendering, font: font, lineScroll: context,
            caretGlyphID: model.session.promptCaretGlyphIndex, viewportLineCount: 3, words: words)
        } else {
          Text(rendering.text).font(Font(font)).lineSpacing(12)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
              PromptAutoScrollOverlay(text: rendering.text,
                characterOffset: rendering.characterOffset(forGlyphAt: model.session.promptCaretGlyphIndex),
                font: font, lineSpacing: 12, isRightToLeft: false, lineScroll: context)
            }
        }
      }.frame(width: 240).foregroundStyle(.black).background(.white)
    }
  }

  private func verifyMounted(asl: Bool) throws {
    try withSettings { settings, _ in
      settings.practiceFont = .defaultSystem; settings.fontSize = 28
      let model = Model(settings: settings, asl: asl), start = Date(timeIntervalSinceReferenceDate: 913_000_000)
      let word = model.word, original = model.session.prompt
      let accepted = String(repeating: word + " ", count: 4)
      model.session.insertBatch(accepted, at: start)
      if !asl {
        let measured = try XCTUnwrap(PromptLineScrollGeometry.measure(in: model.rendering.text,
          activeOffset: 20, previousOffset: nil, width: 240,
          font: .monospacedSystemFont(ofSize: 28, weight: .regular), lineSpacing: 12, rightToLeft: false))
        XCTAssertGreaterThan(measured.activeTop, 45, "Fixture must have a removable earlier row")
      }
      let attempt = model.session.automaticInputAttemptID
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 400),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
      let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
      defer { window.contentView = nil; window.close() }
      @MainActor func pump() { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.25)); host.layoutSubtreeIfNeeded() }
      @MainActor func capture(_ phase: String) throws {
        if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
          let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
          host.cacheDisplay(in: host.bounds, to: bitmap)
          try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("wrapper-\(asl ? "asl" : "text")-\(phase).png"))
        }
      }
      pump(); pump()
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0)
      settings.practiceFont = .monospaced; pump(); pump()
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 0, "Font family alone must not force source centering")
      try capture("font")
      settings.colorfulMode = true; pump(); pump()
      XCTAssertEqual(model.session.firstRetainedPromptWordIndex, 2)
      XCTAssertEqual(model.session.automaticInputAttemptID, attempt)
      XCTAssertEqual(model.session.typed, accepted)
      XCTAssertEqual(model.session.prompt, original)
      XCTAssertEqual(String(model.rendering.text.characters), Array(repeating: word, count: 4).joined(separator: " "))
      XCTAssertFalse(window.isVisible)
      try capture("event")
      model.session.deleteWordBackward(at: start.addingTimeInterval(1))
      model.session.deleteWordBackward(at: start.addingTimeInterval(2))
      model.session.deleteBackward(at: start.addingTimeInterval(3))
      XCTAssertEqual(model.session.typed, String(repeating: word + " ", count: 2))
      model.session.insertBatch(Array(repeating: word, count: 4).joined(separator: " "), at: start.addingTimeInterval(4))
      let result = try XCTUnwrap(model.session.result())
      XCTAssertEqual(result.prompt, original)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), model.session.typed)
    }
  }

  func testMountedOrdinaryFontFamilyThenColorEventPreservesSessionAndReplay() throws { try verifyMounted(asl: false) }
  func testMountedASLFallbackFontFamilyThenColorEventPreservesSessionAndReplay() throws { try verifyMounted(asl: true) }

  func testProductionFactoryAndBothNativeBridgesCarryWrapperEventIdentity() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    for (file, expression) in [("TypebarApp.swift", "wrapperRevision: settings.practiceWrapperRevision"),
      ("PromptCaretOverlay.swift", "wrapperRevision: $0.wrapperRevision"),
      ("ASLPromptPresentation.swift", "wrapperRevision: $0.wrapperRevision")] {
      XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("Sources/Typebar/" + file), encoding: .utf8).contains(expression), file)
    }
  }
}
