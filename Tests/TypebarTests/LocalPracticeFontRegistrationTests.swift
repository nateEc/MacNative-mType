import Foundation
import XCTest
@testable import Typebar

final class LocalPracticeFontRegistrationTests: XCTestCase {
  private let url = URL(fileURLWithPath: "/typebar-isolated-registration-fixture.ttf")
  private let info = LocalPracticeFontInfo(postScriptName: "SameName", displayName: "Owned Fixture")

  func testUsableFileDoesNotRequireGlobalNameAvailability() {
    var fileChecks = 0
    let result = LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in self.info },
      isSelectedSource: { name, url in
        fileChecks += 1
        XCTAssertEqual(name, self.info.postScriptName)
        XCTAssertEqual(url, self.url)
        return true
      })
    XCTAssertEqual(result, info, "The verified file-bound font must not depend on global name matching")
    XCTAssertEqual(fileChecks, 1)
  }

  func testAvailableSameNameDoesNotTurnFailedFileRegistrationIntoSuccess() {
    let result = LocalPracticeFontRegistration.read(url: url, register: { _ in false },
      isRegistered: { requested in XCTAssertEqual(requested, self.url); return false },
      readInfo: { _ in self.info }, isSelectedSource: { _, _ in true })
    XCTAssertNil(result, "A different installed font with the same name is not proof that this file registered")
  }

  func testAlreadyRegisteredSameFileRemainsReadable() {
    let result = LocalPracticeFontRegistration.read(url: url, register: { _ in false },
      isRegistered: { requested in XCTAssertEqual(requested, self.url); return true },
      readInfo: { _ in self.info }, isSelectedSource: { _, _ in true })
    XCTAssertEqual(result, info)
  }

  func testSuccessfulRegistrationStillRequiresDescriptorAndAvailableFont() {
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in XCTFail("Successful registration needs no scope fallback"); return false },
      readInfo: { _ in self.info }, isSelectedSource: { _, _ in true }), info)
    XCTAssertNil(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in nil },
      isSelectedSource: { _, _ in XCTFail("Missing descriptor must stop source lookup"); return true }))
    XCTAssertNil(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in self.info },
      isSelectedSource: { _, _ in false }))
  }

  func testSuccessfulRegistrationRejectsSelectionFromAnotherSameNameFile() {
    XCTAssertNil(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in self.info },
      isSelectedSource: { name, url in
        XCTAssertEqual(name, self.info.postScriptName)
        XCTAssertEqual(url, self.url)
        return false
      }))
  }
}
