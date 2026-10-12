import AppKit
import CoreText
import XCTest
@testable import Typebar

@MainActor final class NativeLocalFontRegistrationTests: XCTestCase {
  func testPostRegistrationFailureUnregistersNewFontBeforeRestoringPreviousFont() throws {
    try checkPostRegistrationFailure(sameName: false)
  }

  func testSameNamePostRegistrationFailureRestoresPreviousFontSource() throws {
    try checkPostRegistrationFailure(sameName: true)
  }

  private func checkPostRegistrationFailure(sameName: Bool) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-native-font-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let oldName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let newName = sameName ? oldName : "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let oldBytes = OwnedTestFontFixture.make(postScriptName: oldName)
    let newBytes = sameName ? OwnedTestFontFixture.makeOTF(postScriptName: newName)
      : OwnedTestFontFixture.make(postScriptName: newName)
    var failedURL: URL?
    defer {
      // Clean a registration leak even when the failing implementation removed its file.
      if let failedURL {
        if !FileManager.default.fileExists(atPath: failedURL.path) { try? newBytes.write(to: failedURL) }
        _ = CTFontManagerUnregisterFontsForURL(failedURL as CFURL, .process, nil)
      }
      for url in LocalPracticeFontImport.storedURLs(in: directory) {
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
      }
      try? FileManager.default.removeItem(at: directory)
    }
    var enables = 0
    let oldInfo = try LocalPracticeFontImport.save(oldBytes, originalFilename: "old.ttf",
      directory: directory, readInfo: LocalPracticeFontRegistration.fontInfo(at:),
      register: LocalPracticeFontRegistration.read(url:),
      unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
      enable: { enables += 1 })
    let oldURL = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
    XCTAssertThrowsError(try LocalPracticeFontImport.save(newBytes, originalFilename: sameName ? "new.otf" : "new.ttf",
      directory: directory, readInfo: LocalPracticeFontRegistration.fontInfo(at:), register: { url in
        if url.lastPathComponent == oldURL.lastPathComponent {
          // Recovery must not run while the rejected generation remains registered.
          if let failedURL { XCTAssertEqual(CTFontManagerGetScopeForURL(failedURL as CFURL), .none) }
          return LocalPracticeFontRegistration.read(url: url)
        }
        failedURL = url
        XCTAssertEqual(LocalPracticeFontRegistration.read(url: url)?.postScriptName, newName)
        XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .process)
        let selected = CTFontCreateWithName(newName as CFString, 28, nil)
        let selectedURL = CTFontCopyAttribute(selected, kCTFontURLAttribute) as? URL
        XCTAssertEqual(selectedURL?.resolvingSymlinksInPath(), url.resolvingSymlinksInPath(),
          "The temporary replacement must actually resolve to the new file")
        return nil // Inject a failure after the real native registration succeeded.
      }, unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
      enable: { enables += 1 })) { error in
        guard case LocalPracticeFontError.couldNotLoad = error else {
          return XCTFail("Expected load failure, received \(error)")
        }
      }
    let rejectedURL = try XCTUnwrap(failedURL)
    XCTAssertEqual(CTFontManagerGetScopeForURL(rejectedURL as CFURL), .none)
    XCTAssertEqual(CTFontManagerGetScopeForURL(oldURL as CFURL), .process)
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: oldURL), oldInfo)
    let restored = CTFontCreateWithName(oldName as CFString, 28, nil)
    let restoredURL = CTFontCopyAttribute(restored, kCTFontURLAttribute) as? URL
    XCTAssertEqual(restoredURL?.resolvingSymlinksInPath(), oldURL.resolvingSymlinksInPath(),
      "Name availability alone must not mask a stale rejected font source")
    XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
    XCTAssertEqual(enables, 1)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [oldURL.lastPathComponent])
  }

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

  func testNativeSameNameImportRequiresSelectedSourceAndPreservesUnrelatedRegistration() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-native-conflict-\(UUID())", isDirectory: true)
    let directory = root.appendingPathComponent("store", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let externalURL = root.appendingPathComponent("separately-registered.ttf")
    defer {
      _ = CTFontManagerUnregisterFontsForURL(externalURL as CFURL, .process, nil)
      for url in LocalPracticeFontImport.storedURLs(in: directory) {
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
      }
      try? FileManager.default.removeItem(at: root)
    }
    let conflictName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let externalBytes = OwnedTestFontFixture.make(postScriptName: conflictName)
    try externalBytes.write(to: externalURL)
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: externalURL)?.postScriptName, conflictName)
    let oldName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let oldBytes = OwnedTestFontFixture.make(postScriptName: oldName)
    var enables = 0
    func save(_ bytes: Data, filename: String,
      register: (URL) -> LocalPracticeFontInfo? = LocalPracticeFontRegistration.read(url:)) throws -> LocalPracticeFontInfo {
      try LocalPracticeFontImport.save(bytes, originalFilename: filename, directory: directory,
        readInfo: LocalPracticeFontRegistration.fontInfo(at:), register: register,
        unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
        enable: { enables += 1 })
    }
    let oldInfo = try save(oldBytes, filename: "old.ttf")
    let oldURL = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
    var rejectedURL: URL?
    let newBytes = OwnedTestFontFixture.makeOTF(postScriptName: conflictName)
    var imported: LocalPracticeFontInfo?
    do {
      imported = try save(newBytes, filename: "conflict.otf", register: { url in
          let result = LocalPracticeFontRegistration.read(url: url)
          if url.lastPathComponent != oldURL.lastPathComponent {
            rejectedURL = url
            if result != nil {
              let selected = CTFontCreateWithName(conflictName as CFString, 1, nil)
              XCTAssertEqual((CTFontCopyAttribute(selected, kCTFontURLAttribute) as? URL)?.resolvingSymlinksInPath(),
                url.resolvingSymlinksInPath(), "Success requires the imported file, not merely its name")
            }
          }
          return result
        })
    } catch {
        guard case LocalPracticeFontError.couldNotLoad = error else {
          return XCTFail("Expected registration failure, received \(error)")
        }
    }
    let attemptedURL = try XCTUnwrap(rejectedURL)
    XCTAssertEqual(CTFontManagerGetScopeForURL(externalURL as CFURL), .process)
    XCTAssertEqual(try Data(contentsOf: externalURL), externalBytes)
    if let imported {
      XCTAssertEqual(imported.postScriptName, conflictName)
      XCTAssertEqual(CTFontManagerGetScopeForURL(attemptedURL as CFURL), .process)
      XCTAssertEqual(CTFontManagerGetScopeForURL(oldURL as CFURL), .none)
      XCTAssertEqual(try Data(contentsOf: attemptedURL), newBytes)
      XCTAssertEqual(enables, 2)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [attemptedURL.lastPathComponent])
    } else {
      XCTAssertEqual(CTFontManagerGetScopeForURL(attemptedURL as CFURL), .none)
      XCTAssertEqual(CTFontManagerGetScopeForURL(oldURL as CFURL), .process)
      XCTAssertEqual(LocalPracticeFontRegistration.read(url: oldURL), oldInfo)
      XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
      XCTAssertEqual(enables, 1)
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [oldURL.lastPathComponent])
    }
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

  func testOwnedTrueTypeWOFF2RegistersIdempotentlyAndUsesItsOwnFileWithoutUserStore() throws {
    try checkOwnedFont(format: "woff2", make: { name in
      let data = OwnedTestFontFixture.makeWOFF2(postScriptName: name, cff: false)
      XCTAssertEqual(Array(data.prefix(8)), [0x77, 0x4F, 0x46, 0x32, 0, 1, 0, 0])
      let bytes = Array(data)
      let count = Int(bytes[12]) << 8 | Int(bytes[13])
      XCTAssertEqual(count, 10)
      var offset = 48, flags: [UInt8] = []
      for _ in 0..<count {
        flags.append(bytes[offset])
        offset += 1
        // Every table has only origLength: all transforms are null.
        while bytes[offset] & 0x80 != 0 { offset += 1 }
        offset += 1
      }
      XCTAssertTrue(flags.contains(0xCA), "glyf must use null transform version 3")
      XCTAssertTrue(flags.contains(0xCB), "loca must use null transform version 3")
      XCTAssertFalse(flags.contains(13), "TrueType coverage must not reuse CFF data")
      return data
    })
  }

  func testMalformedWebFontImportsPreservePreviouslyRegisteredFont() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-native-font-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      for url in LocalPracticeFontImport.storedURLs(in: directory) {
        _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
      }
      try? FileManager.default.removeItem(at: directory)
    }
    var enables = 0
    func save(_ bytes: Data, extension suffix: String) throws -> LocalPracticeFontInfo {
      try LocalPracticeFontImport.save(bytes, originalFilename: "owned." + suffix,
        directory: directory, readInfo: LocalPracticeFontRegistration.fontInfo(at:),
        register: LocalPracticeFontRegistration.read(url:),
        unregister: { _ = CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil) },
        enable: { enables += 1 })
    }
    let oldName = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let oldBytes = OwnedTestFontFixture.make(postScriptName: oldName)
    let oldInfo = try save(oldBytes, extension: "ttf")
    let oldURL = try XCTUnwrap(LocalPracticeFontImport.storedURLs(in: directory).first)
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    let formats = [("woff", OwnedTestFontFixture.makeWOFF(postScriptName: name, compressed: true)),
      ("woff2", OwnedTestFontFixture.makeWOFF2(postScriptName: name)),
      ("woff2", OwnedTestFontFixture.makeWOFF2(postScriptName: name, cff: false))]
    for (suffix, valid) in formats {
      var badSignature = valid
      badSignature.replaceSubrange(0..<4, with: [0, 0, 0, 0])
      for malformed in [Data(valid.prefix(24)), badSignature] {
        XCTAssertThrowsError(try save(malformed, extension: suffix)) { error in
          XCTAssertTrue(error is LocalPracticeFontError, "Unexpected error: \(error)")
        }
        XCTAssertEqual(enables, 1)
        XCTAssertEqual(LocalPracticeFontImport.storedURLs(in: directory), [oldURL])
        XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
        XCTAssertEqual(CTFontManagerGetScopeForURL(oldURL as CFURL), .process)
        XCTAssertEqual(LocalPracticeFontRegistration.read(url: oldURL), oldInfo)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
          [oldURL.lastPathComponent], "Failed candidates must not remain on disk")
      }
    }
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
