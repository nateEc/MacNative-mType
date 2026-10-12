import AppKit
import XCTest
@testable import Typebar

final class NativeFontPreviewTests: XCTestCase {
  @MainActor func testEveryInstalledCatalogFamilyResolvesAndMeasuresWithoutLocalOverride() throws {
    let families = NativeFontCatalog.installedFamilies
    XCTAssertFalse(families.isEmpty)
    let resolver = NativePracticeFont.Resolver(localFontName: {
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
      localFontName: { localLookups += 1; return local.fontName },
      installedFontName: { NSFont(name: $0, size: 15)?.fontName })
    let preview = NativeFontCatalog.previewFont(for: "Georgia", resolver: resolver)
    XCTAssertEqual(preview.fontName, serif.fontName)
    XCTAssertEqual(localLookups, 0, "Browsing fonts must not load or register the local practice font")
    XCTAssertEqual(resolver.postScriptName(for: "Georgia"), local.fontName,
      "Actual practice must retain the active local override")
  }

  func testMissingCatalogFontFallsBackWithoutSubstitutingTheActiveLocalFont() throws {
    let local = try XCTUnwrap(NSFont(name: "Courier", size: 15))
    let resolver = NativePracticeFont.Resolver(
      localFontName: { local.fontName }, installedFontName: { _ in nil })
    XCTAssertEqual(NativeFontCatalog.previewFont(for: "Missing", size: 19, resolver: resolver),
      NSFont.systemFont(ofSize: 19))
  }

  func testNamedPracticeFontResolvesNormallyWhenNoLocalOverrideIsActive() throws {
    let installed = try XCTUnwrap(NSFont(name: "Georgia", size: 15))
    let resolver = NativePracticeFont.Resolver(
      localFontName: { nil }, installedFontName: { _ in installed.fontName })
    XCTAssertEqual(resolver.postScriptName(for: "Georgia"), installed.fontName)
    XCTAssertEqual(NativeFontCatalog.previewFont(for: "Georgia", size: 22, resolver: resolver).pointSize, 22)
  }
}
