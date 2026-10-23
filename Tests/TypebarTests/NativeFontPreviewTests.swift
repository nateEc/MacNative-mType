import AppKit
import XCTest
@testable import Typebar

final class NativeFontPreviewTests: XCTestCase {
  private func hasMissingGlyphs(_ storage: NSTextStorage, _ manager: NSLayoutManager,
    _ range: NSRange) -> Bool {
    (range.location..<NSMaxRange(range)).contains { index in
      guard !manager.propertyForGlyph(at: index).contains(.null) else { return false }
      let character = manager.characterIndexForGlyph(at: index)
      let font = storage.attribute(.font, at: character, effectiveRange: nil) as? NSFont
      return manager.glyph(at: index) == 0 || font?.fontName == "LastResort"
    }
  }

  @MainActor func testMissingGlyphProbeDistinguishesNotdefFromSuppressedLigatureSlots() {
    let storage = NSTextStorage(string: "\u{0378}",
      attributes: [.font: NSFont.systemFont(ofSize: 28)])
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: .init(width: 2000, height: 2000))
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    let range = manager.glyphRange(for: container)
    XCTAssertGreaterThan(range.length, 0)
    XCTAssertTrue(hasMissingGlyphs(storage, manager, range),
      "An unassigned scalar must exercise the missing-glyph check, including LastResort's nonzero boxes")
  }

  @MainActor func testCommonNamedFontsUseNativeFallbackWithoutMissingGlyphsForMixedScripts() throws {
    // A nonzero bounding box also measures .notdef boxes. Inspect the actual
    // TextKit glyph stream instead, without registering or importing any font.
    for name in ["Menlo", "Courier", "Georgia"] {
      let primary = try XCTUnwrap(NSFont(name: name, size: 28))
      for sample in ["quiet harbor", "中文かな한글", "سلام עולם", "quiet 中文 سلام עולם"] {
        let source = NSAttributedString(string: sample, attributes: [.font: primary])
        let storage = NSTextStorage(attributedString: source)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .init(width: 2000, height: 2000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let range = manager.glyphRange(for: container)
        XCTAssertGreaterThan(range.length, 0, "\(name): \(sample)")
        XCTAssertEqual(manager.characterRange(forGlyphRange: range, actualGlyphRange: nil),
          NSRange(location: 0, length: sample.utf16.count))
        XCTAssertFalse(hasMissingGlyphs(storage, manager, range),
          "Missing glyph or LastResort box in native fallback: \(name), \(sample)")
        let bounds = manager.usedRect(for: container)
        XCTAssertTrue(bounds.width.isFinite && bounds.width > 0)
        XCTAssertTrue(bounds.height.isFinite && bounds.height > 0)
        XCTAssertEqual(source.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, primary,
          "TextKit font fixing may change layout storage, not the original font request")
      }
    }
  }

  @MainActor func testEveryInstalledCatalogFamilyResolvesAndMeasuresWithoutLocalOverride() throws {
    let families = NativeFontCatalog.installedFamilies
    XCTAssertFalse(families.isEmpty)
    let resolver = NativePracticeFont.Resolver(localFont: { _ in
      XCTFail("Catalog traversal must not register or access the imported font")
      return nil
    })
    for family in families {
      let resolved = try XCTUnwrap(NativePracticeFont.postScriptName(for: family),
        "Installed family must resolve: \(family)")
      let expected = try XCTUnwrap(NSFont(name: resolved, size: 15))
      let preview = NativeFontCatalog.previewFont(for: family, size: 15, resolver: resolver)
      XCTAssertEqual(preview.fontName, expected.fontName, family)
      XCTAssertEqual(preview.pointSize, 15, family)
      XCTAssertEqual(NativeFontCatalog.selectedFamily(for: resolved, in: families), family)
      for sample in ["Aa 123", "中文かな한글", "العربية עברית", "ລາວ سنڌي"] {
        let measured = NSAttributedString(string: sample, attributes: [.font: preview])
          .boundingRect(with: .init(width: 2000, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        XCTAssertTrue(measured.width.isFinite && measured.width > 0, family)
        XCTAssertTrue(measured.height.isFinite && measured.height > 0, family)
      }
    }
    print("Installed catalog runtime acceptance: \(families.count) families, four script samples each; no GUI")
  }

  func testNormalizedFamilyNameKeepsTheSameDefaultFaceAsItsCanonicalName() throws {
    let canonical = try XCTUnwrap(NSFont(name: "Apple Braille", size: 28))
    for alias in ["applebraille", "Ａｐｐｌｅ Ｂｒａｉｌｌｅ"] {
      XCTAssertEqual(NativePracticeFont.postScriptName(for: alias,
        installedFamilies: ["Apple Braille"]), canonical.fontName,
        "Normalizing a family identity must not select an outline variant")
    }
  }

  func testEmptyAndDirectFontNamesDoNotEnumerateInstalledFamilies() throws {
    let direct = try XCTUnwrap(NSFont(name: "Courier", size: 15))
    var enumerations = 0
    func families() -> [String] { enumerations += 1; return [] }
    XCTAssertNil(NativePracticeFont.postScriptName(for: "  ", installedFamilies: families()))
    XCTAssertNil(NativePracticeFont.postScriptName(for: "bad\nname", installedFamilies: families()))
    XCTAssertEqual(NativePracticeFont.postScriptName(for: direct.fontName,
      installedFamilies: families()), direct.fontName)
    XCTAssertEqual(enumerations, 0,
      "Empty, invalid and directly resolvable names must not load the system family catalog")
    XCTAssertNil(NativePracticeFont.postScriptName(for: "TypebarMissingFont_928713",
      installedFamilies: families()))
    XCTAssertEqual(enumerations, 1, "Unresolved names must still consult current installed families")
  }

  func testCatalogRowsPreviewTheirRequestedFontDespiteAnActiveLocalOverride() throws {
    let local = try XCTUnwrap(NSFont(name: "Courier", size: 15))
    let serif = try XCTUnwrap(NSFont(name: "Georgia", size: 15))
    var localLookups = 0
    let resolver = NativePracticeFont.Resolver(
      localFont: { _ in localLookups += 1; return local },
      installedFontName: { NSFont(name: $0, size: 15)?.fontName })
    let preview = NativeFontCatalog.previewFont(for: "Georgia", resolver: resolver)
    XCTAssertEqual(preview.fontName, serif.fontName)
    XCTAssertEqual(localLookups, 0, "Browsing fonts must not load or register the local practice font")
    XCTAssertTrue(resolver.font(for: "Georgia", size: 15) === local,
      "Actual practice must retain the active local override")
  }

  func testMissingCatalogFontFallsBackWithoutSubstitutingTheActiveLocalFont() throws {
    let local = try XCTUnwrap(NSFont(name: "Courier", size: 15))
    let resolver = NativePracticeFont.Resolver(
      localFont: { _ in local }, installedFontName: { _ in nil })
    XCTAssertEqual(NativeFontCatalog.previewFont(for: "Missing", size: 19, resolver: resolver),
      NSFont.systemFont(ofSize: 19))
  }

  func testNamedPracticeFontResolvesNormallyWhenNoLocalOverrideIsActive() throws {
    let installed = try XCTUnwrap(NSFont(name: "Georgia", size: 15))
    let resolver = NativePracticeFont.Resolver(
      localFont: { _ in nil }, installedFontName: { _ in installed.fontName })
    XCTAssertEqual(resolver.font(for: "Georgia", size: 15)?.fontName, installed.fontName)
    XCTAssertEqual(NativeFontCatalog.previewFont(for: "Georgia", size: 22, resolver: resolver).pointSize, 22)
  }
}
