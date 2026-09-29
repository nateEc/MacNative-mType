import Foundation
import XCTest

@testable import Typebar

final class OfficialChallengeCoverageTests: XCTestCase {
  private struct Fixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let sourceFiles: [String]
    let officialCount: Int
    let officialNames: [String]
    let nativeEquivalent: [String: String]
    let pending: [String]
  }

  func testPinnedChallengeIdentitiesArePartitionedAndNativeLinksResolve() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-challenges.json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let official = Set(fixture.officialNames)
    let mapped = Set(fixture.nativeEquivalent.keys)
    let pending = Set(fixture.pending)

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.sourceFiles.count, 3)
    XCTAssertEqual(fixture.officialCount, 58)
    XCTAssertEqual(fixture.officialNames.count, fixture.officialCount)
    XCTAssertEqual(official.count, fixture.officialCount)
    XCTAssertEqual(mapped.count, 12)
    XCTAssertEqual(fixture.pending.count, pending.count)
    XCTAssertTrue(mapped.isDisjoint(with: pending))
    XCTAssertEqual(mapped.union(pending), official)
    XCTAssertEqual(
      Set(TypebarChallengeLibrary.all.flatMap(\.legacyURLNames)), mapped)

    for (officialName, nativeID) in fixture.nativeEquivalent {
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: nativeID), officialName)
      XCTAssertTrue(challenge.legacyURLNames.contains(officialName), officialName)
      XCTAssertEqual(
        try LegacyChallengeLinkImporter.challenge(
          from: "https://example.invalid/?challenge=\(officialName)",
          challenges: TypebarChallengeLibrary.all)?.id,
        nativeID, officialName)
    }
  }
}
