import AppKit
import CoreText
import XCTest
@testable import Typebar

@MainActor final class NativeLocalFontRegistrationTests: XCTestCase {
  func testNativeReplacementAndInvalidImportKeepCorrectFileAndRegistration() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-native-font-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      for url in LocalPracticeFontImport.storedURLs(in: directory) {
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
      }
      try? FileManager.default.removeItem(at: directory)
    }
    let firstName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let secondName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    var enables = 0
    func save(_ bytes: Data) throws -> LocalPracticeFontInfo {
      try LocalPracticeFontImport.save(bytes, originalFilename: "owned.ttf", directory: directory,
        readInfo: LocalPracticeFontRegistration.fontInfo(at:), register: LocalPracticeFontRegistration.read(url:),
        unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
        enable: { enables += 1 })
    }
    let firstBytes = OwnedTestFontFixture.make(postScriptName: firstName)
    XCTAssertEqual(try save(firstBytes).postScriptName, firstName)
    let firstURL = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
    XCTAssertThrowsError(try save(Data("not a font".utf8))) { error in
      switch error {
      case LocalPracticeFontError.invalidFont: break
      default: XCTFail("Expected invalid font, received \(error)")
      }
    }
    XCTAssertEqual(enables, 1)
    XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
    XCTAssertEqual(CTFontManagerGetScopeForURL(firstURL as CFURL), .process)
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: firstURL)?.postScriptName, firstName)
    XCTAssertEqual(try save(OwnedTestFontFixture.make(postScriptName: secondName)).postScriptName, secondName)
    let stored = LocalPracticeFontImport.storedURLs(in: directory)
    XCTAssertEqual(stored.count, 1)
    let secondURL = try XCTUnwrap(stored.first)
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    XCTAssertEqual(CTFontManagerGetScopeForURL(firstURL as CFURL), .none)
    XCTAssertEqual(CTFontManagerGetScopeForURL(secondURL as CFURL), .process)
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: secondURL)?.postScriptName, secondName)
    XCTAssertEqual(enables, 2)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [secondURL.lastPathComponent])
    XCTAssertTrue(CTFontManagerUnregisterFontsForURL(secondURL as CFURL, .process, nil))
    XCTAssertEqual(CTFontManagerGetScopeForURL(secondURL as CFURL), .none)
  }

  func testOwnedFontRegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-native-font-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var active: URL?
    defer {
      if let active { _ = CTFontManagerUnregisterFontsForURL(active as CFURL, .process, nil) }
      try? FileManager.default.removeItem(at: directory)
    }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    XCTAssertNil(NSFont(name: name, size: 28), "The original fixture must not collide with an installed font")
    var enables = 0
    let info = try LocalPracticeFontImport.save(OwnedTestFontFixture.make(postScriptName: name),
      originalFilename: "owned.ttf", directory: directory,
      readInfo: LocalPracticeFontRegistration.fontInfo(at:), register: LocalPracticeFontRegistration.read(url:),
      unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
      enable: { enables += 1 })
    active = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
    let url = try XCTUnwrap(active)
    XCTAssertEqual(info.postScriptName, name)
    XCTAssertEqual(enables, 1)
    XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .process)
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: url), info,
      "Repeated production reads must tolerate the same file already being registered")
    let font = CTFontCreateWithName(name as CFString, 28, nil)
    let loadedURL = try XCTUnwrap(CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)
    XCTAssertEqual(loadedURL.resolvingSymlinksInPath(), url.resolvingSymlinksInPath(),
      "An available same-name font is not enough: the selected font must originate from our file")
    var character: UniChar = 120, glyph: CGGlyph = 0
    XCTAssertTrue(CTFontGetGlyphsForCharacters(font, &character, &glyph, 1))
    XCTAssertNotEqual(glyph, 0)
    XCTAssertTrue(CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil))
    XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .none)
    active = nil
  }
}
