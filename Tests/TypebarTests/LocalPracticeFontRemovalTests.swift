import Foundation
import CoreText
import XCTest
@testable import Typebar

final class LocalPracticeFontRemovalTests: XCTestCase {
  func testSuccessClearsSettingOnlyAfterEveryFileIsRemovedWithoutReregistering() throws {
    let urls = [URL(fileURLWithPath: "/owned/a.ttf"), URL(fileURLWithPath: "/owned/b.ttf")]
    var removed: [URL] = [], unregistered: [URL] = [], cleared = false
    try LocalPracticeFontRemoval.remove(urls, unregister: { unregistered.append($0) },
      register: { _ in XCTFail("Successful removal must not register again") },
      removeFile: { removed.append($0) }, didRemove: {
        XCTAssertEqual(removed, urls); cleared = true
      })
    XCTAssertEqual(unregistered, urls)
    XCTAssertTrue(cleared)
  }

  func testUnregistrationFailureKeepsFileAndEnabledSetting() throws {
    let url = URL(fileURLWithPath: "/owned/a.ttf")
    let failure = NSError(domain: "CoreTextUnregisterFailure", code: 9)
    var restored = false
    XCTAssertThrowsError(try LocalPracticeFontRemoval.remove([url], unregister: { _ in
      throw failure
    }, register: { restored = $0 == url }, removeFile: { _ in
      XCTFail("A font still registered by Core Text must not be deleted")
    }, didRemove: {
      XCTFail("A failed removal must keep the user's enabled setting")
    })) { error in
      XCTAssertEqual(error as NSError, failure)
    }
    XCTAssertTrue(restored, "The failed unload might have partially changed native registration")
  }

  func testPartialFailureRestoresOnlyFailedFileAndDoesNotTouchLaterFiles() {
    let urls = ["a", "b", "c"].map { URL(fileURLWithPath: "/owned/\($0).ttf") }
    var unregistered: [URL] = [], restored: [URL] = [], removed: [URL] = []
    XCTAssertThrowsError(try LocalPracticeFontRemoval.remove(urls,
      unregister: { unregistered.append($0) }, register: { restored.append($0) },
      removeFile: {
        if $0 == urls[1] { throw NSError(domain: "OwnedDeletionFailure", code: 7) }
        removed.append($0)
      }, didRemove: { XCTFail("Partial failure must preserve enabled setting") }))
    XCTAssertEqual(unregistered, Array(urls.prefix(2)))
    XCTAssertEqual(removed, [urls[0]])
    XCTAssertEqual(restored, [urls[1]])
  }

  func testRealCoreTextRegistrationIsRestoredWhenDeletionThrows() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-font-remove-native-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("owned.ttf")
    defer {
      _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
      try? FileManager.default.removeItem(at: directory)
    }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    try OwnedTestFontFixture.make(postScriptName: name).write(to: url)
    XCTAssertNotNil(LocalPracticeFontRegistration.read(url: url))
    XCTAssertThrowsError(try LocalPracticeFontRemoval.remove([url], unregister: {
      XCTAssertTrue(CTFontManagerUnregisterFontsForURL($0 as CFURL, .process, nil))
    }, register: {
      XCTAssertNotNil(LocalPracticeFontRegistration.read(url: $0))
    }, removeFile: { _ in
      XCTAssertNotEqual(CTFontManagerGetScopeForURL(url as CFURL), .process)
      throw NSError(domain: "OwnedDeletionFailure", code: 7)
    }, didRemove: { XCTFail("Failure must not clear setting") }))
    XCTAssertEqual(CTFontManagerGetScopeForURL(url as CFURL), .process)
    XCTAssertEqual(LocalPracticeFontRegistration.font(at: url, size: 28)?.fontName, name)
  }

  func testDeletionFailureRestoresStillStoredFontAndPreservesEnabledSetting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-font-removal-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("owned.ttf")
    let bytes = Data("owned fixture".utf8)
    try bytes.write(to: url)
    var registered = true, cleared = false
    let failure = NSError(domain: "OwnedDeletionFailure", code: 7)
    XCTAssertThrowsError(try LocalPracticeFontRemoval.remove([url], unregister: { _ in registered = false },
      register: { restored in
        XCTAssertEqual(restored, url)
        XCTAssertEqual(try? Data(contentsOf: restored), bytes)
        registered = true
      }, removeFile: { _ in throw failure }, didRemove: { cleared = true })) { error in
        XCTAssertEqual(error as NSError, failure)
      }
    XCTAssertTrue(registered, "Deletion failure must not leave the retained font unregistered")
    XCTAssertFalse(cleared)
    XCTAssertEqual(try Data(contentsOf: url), bytes)
  }
}
