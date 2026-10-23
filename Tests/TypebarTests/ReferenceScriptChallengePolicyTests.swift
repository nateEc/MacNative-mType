import CryptoKit
import Foundation
import XCTest

@testable import Typebar

final class ReferenceScriptChallengePolicyTests: XCTestCase {
  private func ownedScript(_ text: String) throws -> ReferenceScriptChallengePolicy.VerifiedScript {
    let digest = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(legacyName: "owned",
      fileName: "owned.txt", byteCount: text.utf8.count, normalizedCharacterCount: text.unicodeScalars.count,
      normalizedSHA256: digest)
    return try ReferenceScriptChallengePolicy.verifiedScript(Data(text.utf8), for: specification)
  }

  func testClearedQualificationRetainsOnlyItsUnchangedCustomSource() throws {
    let script = try ownedScript("amber harbor willow")
    XCTAssertTrue(script.retainsSource(mode: .custom, editorText: script.text, challengeID: nil))
    XCTAssertFalse(script.retainsSource(mode: .words, editorText: script.text, challengeID: nil))
    XCTAssertFalse(script.retainsSource(mode: .custom, editorText: "new text", challengeID: nil))
    XCTAssertFalse(script.retainsSource(mode: .custom, editorText: script.text, challengeID: "unknown"))
    XCTAssertFalse(script.retainsSource(mode: .custom, editorText: script.text, challengeID: "clean-twenty-five"))
  }

  func testRetainedScriptCompletesAndRepeatsAsUnqualifiedFullTextNotPreviewOnly() throws {
    let source = String(repeating: "amber harbor ", count: 800) + "end"
    let script = try ownedScript(source)
    let preview = LongSavedTextProgress.nextChunk(in: source, after: 0)
    XCTAssertLessThan(preview.count, source.count)
    XCTAssertTrue(script.retainsSource(mode: .custom, editorText: preview, challengeID: nil))
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), customTextCompletion: .finish)
    var session = TestSessionFactory.make(configuration: configuration, customText: preview, verifiedScript: script)
    let start = Date(timeIntervalSince1970: 100)
    session.insertBatch(preview, at: start)
    XCTAssertFalse(session.isFinished)
    session.insertBatch(String(source.dropFirst(preview.count)), at: start.addingTimeInterval(1))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertNil(result.configuration.challengeID)
    XCTAssertEqual(session.prompt, source)
    XCTAssertEqual(session.repeatedAttempt().prompt, preview)
  }

  func testFixedScriptLengthCountsUnicodeScalarsRatherThanSwiftGraphemes() throws {
    let normalized = "cafe\u{301} harbor"
    XCTAssertNotEqual(normalized.count, normalized.unicodeScalars.count)
    let digest = SHA256.hash(data: Data(normalized.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(
      legacyName: "synthetic", fileName: "synthetic.txt", byteCount: normalized.utf8.count,
      normalizedCharacterCount: normalized.unicodeScalars.count, normalizedSHA256: digest)
    XCTAssertEqual(try ReferenceScriptChallengePolicy.verifiedText(
      Data(normalized.utf8), for: specification), normalized)
    XCTAssertTrue(ReferenceScriptChallengePolicy.matchesNormalizedPrompt(
      normalized, for: specification))
  }

  func testUserProvidedScriptMatchesOnlyItsNormalizedPinnedContent() throws {
    let normalized = "amber harbor willow"
    let digest = SHA256.hash(data: Data(normalized.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(
      legacyName: "synthetic", fileName: "synthetic.txt", byteCount: 32,
      normalizedCharacterCount: normalized.count, normalizedSHA256: digest)
    XCTAssertTrue(ReferenceScriptChallengePolicy.matchesNormalizedPrompt(
      normalized, for: specification))
    XCTAssertFalse(ReferenceScriptChallengePolicy.matchesNormalizedPrompt(
      "amber  harbor willow", for: specification))

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

  func testMetadataCoversEachPinnedReferenceScriptWithoutBundlingItsText() throws {
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

  func testFileImportVerifiesContentWithoutRetainingItsPath() throws {
    let normalized = "amber harbor willow"
    let digest = SHA256.hash(data: Data(normalized.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let specification = ReferenceScriptChallengePolicy.Specification(
      legacyName: "synthetic", fileName: "synthetic.txt", byteCount: normalized.utf8.count,
      normalizedCharacterCount: normalized.count, normalizedSHA256: digest)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("typebar-script-\(UUID().uuidString).txt")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("  amber\n harbor  willow  ".utf8).write(to: url)
    let verified = try ReferenceScriptChallengePolicy.verifiedScript(at: url, for: specification)
    XCTAssertEqual(verified.text, normalized)
    XCTAssertEqual(verified.specification, specification)
  }
}
