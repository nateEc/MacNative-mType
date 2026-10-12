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
    try checkOwnedFont(format: "ttf", make: OwnedTestFontFixture.make(postScriptName:))
  }

  func testOwnedWOFFRegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    try checkOwnedFont(format: "woff", make: { OwnedTestFontFixture.makeWOFF(postScriptName: $0) })
  }

  func testOwnedCFFOpenTypeRegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    try checkOwnedFont(format: "otf", make: { name in
      let data = OwnedTestFontFixture.makeOTF(postScriptName: name)
      XCTAssertEqual(data.prefix(4), Data("OTTO".utf8))
      let bytes = Array(data)
      let count = Int(bytes[4]) << 8 | Int(bytes[5])
      let tags = (0..<count).map { index in
        String(decoding: bytes[(12 + index * 16)..<(16 + index * 16)], as: UTF8.self)
      }
      XCTAssertTrue(tags.contains("CFF "))
      XCTAssertFalse(tags.contains("glyf"), "OTF coverage must use CFF outlines, not a renamed TrueType file")
      return data
    })
  }

  func testOwnedCompressedWOFFRegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    try checkOwnedFont(format: "woff", make: { name in
      let data = OwnedTestFontFixture.makeWOFF(postScriptName: name, compressed: true)
      let bytes = Array(data)
      func integer(at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
      }
      let count = Int(bytes[12]) << 8 | Int(bytes[13])
      XCTAssertTrue((0..<count).contains {
        integer(at: 44 + $0 * 20 + 8) < integer(at: 44 + $0 * 20 + 12)
      }, "The compressed fixture must contain an actually compressed table")
      return data
    })
  }

  func testOwnedWOFF2RegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    try checkOwnedFont(format: "woff2", make: { name in
      let data = OwnedTestFontFixture.makeWOFF2(postScriptName: name)
      XCTAssertEqual(Array(data.prefix(8)), Array("wOF2OTTO".utf8))
      let bytes = Array(data)
      func integer(at offset: Int) -> Int {
        bytes[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
      }
      XCTAssertEqual(integer(at: 8), data.count)
      let privateOffset = integer(at: 40), privateLength = integer(at: 44)
      XCTAssertEqual(privateOffset % 4, 0)
      XCTAssertEqual(privateOffset + privateLength, data.count)
      XCTAssertEqual(Array(bytes[privateOffset...]), Array("QA00".utf8))
      return data
    })
  }

  private func checkOwnedFont(format: String, make: (String) -> Data) throws {
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
    let info = try LocalPracticeFontImport.save(make(name),
      originalFilename: "owned." + format, directory: directory,
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
    let outline = try XCTUnwrap(CTFontCreatePathForGlyph(font, glyph, nil))
    let bounds = outline.boundingBoxOfPath
    XCTAssertEqual(bounds.minX, 2.8, accuracy: 0.001)
    XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
    XCTAssertEqual(bounds.width, 11.2, accuracy: 0.001)
    XCTAssertEqual(bounds.height, 19.6, accuracy: 0.001,
      "The actual loaded outline must match our 400×700 rectangle at 28pt / 1000 units-per-em")
    XCTAssertTrue(CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil))
    XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .none)
    active = nil
  }
}
