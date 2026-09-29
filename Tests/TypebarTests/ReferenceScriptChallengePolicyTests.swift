import CryptoKit
import Foundation
import XCTest

@testable import Typebar

final class ReferenceScriptChallengePolicyTests: XCTestCase {
  func testUserProvidedScriptMatchesOnlyItsNormalizedPinnedContent() throws {
    let normalized = "amber harbor willow"
    let digest = SHA256.hash(data: Data(normalized.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(
      legacyName: "synthetic", fileName: "synthetic.txt", byteCount: 32,
      normalizedCharacterCount: normalized.count, normalizedSHA256: digest)

    XCTAssertEqual(try ReferenceScriptChallengePolicy.verifiedText(
      Data(" \n amber  harbor\r\nwillow \t".utf8), for: specification), normalized)
    XCTAssertThrowsError(try ReferenceScriptChallengePolicy.verifiedText(
      Data("amber harbor planet".utf8), for: specification)) { error in
        XCTAssertEqual(error as? ReferenceScriptChallengePolicy.ImportError, .contentMismatch)
      }
    XCTAssertThrowsError(try ReferenceScriptChallengePolicy.verifiedText(
      Data([0xFF, 0xFE]), for: specification))
    XCTAssertThrowsError(try ReferenceScriptChallengePolicy.verifiedText(
      Data(repeating: 0x61, count: ReferenceScriptChallengePolicy.maximumImportedBytes + 1),
      for: specification)) { error in
        XCTAssertEqual(error as? ReferenceScriptChallengePolicy.ImportError, .tooLarge)
      }
  }

  func testMetadataCoversEachStillPendingReferenceScriptWithoutBundlingItsText() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let fixture = try JSONDecoder().decode([ReferenceScriptChallengePolicy.Specification].self,
      from: Data(contentsOf: root.appendingPathComponent(
        "Compatibility/official-script-challenges.json")))
    XCTAssertEqual(fixture, ReferenceScriptChallengePolicy.specifications)
    XCTAssertEqual(Set(fixture.map(\.legacyName)), Set([
      "inAGalaxyFarFarAway", "whosYourDaddy", "itsATrap", "gottaCatchEmAll",
      "rapGod", "navySeal", "littleChef", "crosstalk", "bees",
      "getOffMySwamp", "lookAtMeIAmTheDeveloperNow",
    ]))
    XCTAssertEqual(fixture.count, 11)
    XCTAssertTrue(fixture.allSatisfy { $0.normalizedSHA256.count == 64 })
    XCTAssertEqual(fixture.first { $0.legacyName == "lookAtMeIAmTheDeveloperNow" }?.byteCount,
      798_026)
  }
}
