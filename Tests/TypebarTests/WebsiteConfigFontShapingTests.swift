import AppKit
import CoreText
import Observation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigFontShapingTests: XCTestCase {
  private struct Shape {
    let storage: NSTextStorage
    let manager: NSLayoutManager
    let container: NSTextContainer
    var width: CGFloat { manager.usedRect(for: container).width }
  }
  private func shape(_ storage: NSTextStorage, width: CGFloat = 2000) -> Shape {
    let manager = NSLayoutManager(), container = NSTextContainer(size: .init(width: width, height: 2000))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    return .init(storage: storage, manager: manager, container: container)
  }
  private func resource(name: String, advance: Int = 600, character: UInt32 = 120, size: Double = 28) throws -> WebsiteConfigFontResource {
    var values = try WebsiteConfigNativeProfile.defaultDocument().values
    values["fontFamily"] = .string("Courier")
    values["fontSize"] = .number(size / 16)
    return try .prepare(typography: .init(runtime: values, pointsPerRem: 16), language: .english,
      local: .data(OwnedTestFontFixture.make(postScriptName: name, advanceWidth: advance, character: character)))
  }
  private func uniqueName() -> String { "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
  private func advance(_ font: NSFont, character: UniChar = 120) throws -> CGFloat {
    var character = character, glyph: CGGlyph = 0, value = CGSize.zero
    XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1))
    CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &value, 1)
    return value.width
  }
  private func assertNoMissingGlyphs(_ shape: Shape, file: StaticString = #filePath, line: UInt = #line) {
    for glyph in 0..<shape.manager.numberOfGlyphs {
      if shape.manager.propertyForGlyph(at: glyph).contains(.null)
        || shape.manager.propertyForGlyph(at: glyph).contains(.controlCharacter) { continue }
      let character = shape.manager.characterIndexForGlyph(at: glyph)
      let font = shape.storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont
      XCTAssertNotEqual(shape.manager.glyph(at: glyph), 0, "Missing glyph", file: file, line: line)
      XCTAssertNotEqual(font?.fontName, "LastResort", file: file, line: line)
    }
  }

  func testActualTextKitUsesOrderedUnregisteredSameNameFallbackFaces() throws {
    let name = uniqueName()
    let x = try resource(name: name)
    let y = try resource(name: name, advance: 900, character: 121)
    let laterY = try resource(name: name, advance: 1200, character: 121)
    let first = WebsiteConfigFontResource.compose(primary: x.primary.font, fallback: [y.primary.font, laterY.primary.font])
    let second = WebsiteConfigFontResource.compose(primary: x.primary.font, fallback: [laterY.primary.font, y.primary.font])
    let a = shape(TapePromptTextStorage.prepare(AttributedString("xyx"), font: first))
    let b = shape(TapePromptTextStorage.prepare(AttributedString("xyx"), font: second))
    assertNoMissingGlyphs(a)
    assertNoMissingGlyphs(b)
    XCTAssertEqual(a.width, 28 * 2.1, accuracy: 0.01)
    XCTAssertEqual(b.width, 28 * 2.4, accuracy: 0.01)
    XCTAssertNotEqual(first, second, "Layout's NSFont metric comparison must distinguish the ordered fallback")
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }

  func testPrimaryIdentitySizeAndCacheComparisonSurviveCascadeComposition() throws {
    let name = uniqueName()
    for size in [8.0, 28, 72] {
      let narrow = try resource(name: name, size: size)
      let wide = try resource(name: name, advance: 900, size: size)
      XCTAssertEqual(narrow.renderingFont.fontName, name)
      XCTAssertEqual(narrow.renderingFont.pointSize, size)
      XCTAssertEqual(try advance(narrow.renderingFont), size * 0.6, accuracy: 0.001)
      XCTAssertEqual(try advance(wide.renderingFont), size * 0.9, accuracy: 0.001)
      XCTAssertNotEqual(narrow.renderingFont, wide.renderingFont)
      let unchanged = WebsiteConfigFontResource.compose(primary: narrow.primary.font, fallback: [])
      XCTAssertTrue(unchanged === narrow.primary.font)
    }
  }

  func testPreparedResourceEntersTapeAndCaretStorageWithTheSameOwnedFace() throws {
    let resource = try resource(name: uniqueName(), advance: 900)
    let text = AttributedString("xxx")
    let tape = shape(TapePromptTextStorage.prepare(text, fontResource: resource))
    let caret = shape(PromptCaretLayout.preparedStorage(in: text, fontResource: resource, lineSpacing: 0, isRightToLeft: false))
    XCTAssertEqual(tape.width, 28 * 2.7, accuracy: 0.01)
    XCTAssertEqual(caret.width, tape.width, accuracy: 0.01)
    for offset in 0..<3 {
      let rect = try XCTUnwrap(PromptCaretLayout.rect(in: text, characterOffset: offset,
        containerSize: .init(width: 2000, height: 2000), font: resource.renderingFont, lineSpacing: 0))
      XCTAssertEqual(rect.minX, floor(Double(offset) * 25.2), accuracy: 0.01)
    }
    XCTAssertEqual(tape.storage.string, "xxx")
    XCTAssertEqual(caret.storage.string, "xxx")
  }

  func testSupplementaryScalarKeepsUTF16OwnershipAndUsesExplicitDataFallback() throws {
    let name = uniqueName(), text = "x\u{1D400}x"
    let x = try resource(name: name)
    let extra = try resource(name: name, advance: 900, character: 0x1D400)
    let font = WebsiteConfigFontResource.compose(primary: x.primary.font, fallback: [extra.primary.font])
    let result = shape(TapePromptTextStorage.prepare(AttributedString(text), font: font))
    assertNoMissingGlyphs(result)
    XCTAssertEqual(result.storage.string, text)
    XCTAssertEqual(result.storage.length, 4)
    XCTAssertEqual(result.width, 28 * 2.1, accuracy: 0.01)
    let all = result.manager.glyphRange(for: result.container)
    XCTAssertEqual(result.manager.characterRange(forGlyphRange: all, actualGlyphRange: nil), .init(location: 0, length: 4))
  }

  func testMixedScriptsCombiningAndEmojiUseActualNativeGlyphStream() throws {
    let resource = try resource(name: uniqueName())
    for rtl in [false, true] {
      let text = "x 中文かな한글 سلام עולם 👩‍💻 e\u{301}"
      let result = shape(TapePromptTextStorage.prepare(AttributedString(text), fontResource: resource, rightToLeft: rtl))
      assertNoMissingGlyphs(result)
      XCTAssertEqual(result.storage.string, text)
      XCTAssertTrue(result.width.isFinite && result.width > 0)
      let primary = result.storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
      XCTAssertEqual(primary?.fontName, resource.primary.font.fontName)
    }
    let missing = shape(TapePromptTextStorage.prepare(AttributedString("\u{0378}"), fontResource: resource))
    let containsMissing = (0..<missing.manager.numberOfGlyphs).contains { glyph in
      let character = missing.manager.characterIndexForGlyph(at: glyph)
      let font = missing.storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont
      return missing.manager.glyph(at: glyph) == 0 || font?.fontName == "LastResort"
    }
    XCTAssertTrue(containsMissing, "The missing-glyph probe must not accept a LastResort box as coverage")
  }

  func testCascadeOwnsItsFacesAfterPreparationResourcesLeaveScope() throws {
    let font: NSFont = try autoreleasepool {
      let name = uniqueName()
      let x = try resource(name: name)
      let y = try resource(name: name, advance: 900, character: 121)
      return WebsiteConfigFontResource.compose(primary: x.primary.font, fallback: [y.primary.font])
    }
    let result = shape(TapePromptTextStorage.prepare(AttributedString("xyx"), font: font))
    assertNoMissingGlyphs(result)
    XCTAssertEqual(result.width, 58.8, accuracy: 0.01)
  }

  @MainActor @Observable fileprivate final class Model {
    var fontResource: WebsiteConfigFontResource
    let session: TypingSession
    var ready: [PromptViewportPresentationReady] = []
    init(resource: WebsiteConfigFontResource) {
      fontResource = resource
      var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit]),
        prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
      session.insertBatch("x", at: Date(timeIntervalSince1970: 3000))
      self.session = session
    }
  }
  private struct Root: View {
    let model: Model
    var body: some View {
      let font = model.fontResource.renderingFont
      ScrollView {
        PromptViewportPracticePrompt(session: model.session,
          style: .init(theme: AppTheme.serika_dark.resolvedTheme, fontSize: 28), font: font,
          carets: .init(text: AttributedString(model.session.prompt), mainOffset: nil, paceOffset: nil,
            mainStyle: .off, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
            accent: .blue, motion: .off, reducesMotion: true, frameRate: 60,
            attemptID: model.session.automaticInputAttemptID, coordinator: .init()),
          onFailure: { _ in XCTFail("Prepared-font viewport failed") },
          onReady: { model.ready.append($0) })
          .frame(width: 220)
      }.frame(width: 220, height: 400)
    }
  }

  func testMountedHiddenViewportReflowsPreparedSameNameFaceWithoutRestartingAttempt() throws {
    let name = uniqueName(), first = try resource(name: name), wide = try resource(name: name, advance: 900)
    let model = Model(resource: first)
    let attempt = model.session.automaticInputAttemptID, target = model.session.promptTargetID
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: Root(model: model))
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func waitUntil(_ condition: () -> Bool) {
      let deadline = Date().addingTimeInterval(10)
      while !condition(), Date() < deadline {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
      XCTAssertTrue(condition())
    }
    waitUntil { model.ready.last?.font == first.renderingFont }
    let height = try XCTUnwrap(model.ready.last?.height)
    model.fontResource = wide
    waitUntil { model.ready.last?.font == wide.renderingFont && (model.ready.last?.height ?? 0) > height }
    let ready = try XCTUnwrap(model.ready.last)
    XCTAssertGreaterThan(ready.height, height)
    XCTAssertEqual(try advance(ready.font), 25.2, accuracy: 0.001)
    XCTAssertEqual(ready.attemptID, attempt)
    XCTAssertEqual(ready.targetID, target)
    XCTAssertEqual(model.session.typed, "x")
    XCTAssertFalse(window.isVisible, "This is a hidden test host, never a Typebar app launch")
    XCTAssertFalse((CTFontManagerCopyAvailablePostScriptNames() as? [String] ?? []).contains(name))
  }
}
