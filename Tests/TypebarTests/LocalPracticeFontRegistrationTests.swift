import Foundation
import XCTest
@testable import Typebar

final class LocalPracticeFontRegistrationTests: XCTestCase {
  private let url = URL(fileURLWithPath: "/typebar-isolated-registration-fixture.ttf")
  private let info = LocalPracticeFontInfo(postScriptName: "SameName", displayName: "Owned Fixture")

  func testAvailableSameNameDoesNotTurnFailedFileRegistrationIntoSuccess() {
    let result = LocalPracticeFontRegistration.read(url: url, register: { _ in false },
      isRegistered: { requested in XCTAssertEqual(requested, self.url); return false },
      readInfo: { _ in self.info }, isAvailable: { _ in true })
    XCTAssertNil(result, "A different installed font with the same name is not proof that this file registered")
  }

  func testAlreadyRegisteredSameFileRemainsReadable() {
    let result = LocalPracticeFontRegistration.read(url: url, register: { _ in false },
      isRegistered: { requested in XCTAssertEqual(requested, self.url); return true },
      readInfo: { _ in self.info }, isAvailable: { _ in true })
    XCTAssertEqual(result, info)
  }

  func testSuccessfulRegistrationStillRequiresDescriptorAndAvailableFont() {
    XCTAssertEqual(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in XCTFail("Successful registration needs no scope fallback"); return false },
      readInfo: { _ in self.info }, isAvailable: { _ in true }), info)
    XCTAssertNil(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in nil }, isAvailable: { _ in true }))
    XCTAssertNil(LocalPracticeFontRegistration.read(url: url, register: { _ in true },
      isRegistered: { _ in false }, readInfo: { _ in self.info }, isAvailable: { _ in false }))
  }
}
