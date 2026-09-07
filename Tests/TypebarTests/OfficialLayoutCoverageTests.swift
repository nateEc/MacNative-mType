import Foundation
import XCTest

@testable import Typebar

final class OfficialLayoutCoverageTests: XCTestCase {
  private struct Fixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let officialCount: Int
    let officialNames: [String]
    let nativeExact: [String: String]
    let nativeRelated: [String: String]
    let unlistedPolicy: String
  }

  func testPinnedOfficialLayoutCoverageIsCompleteUniqueAndResolvable() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-layouts.json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let officialNames = Set(fixture.officialNames)
    let exactNames = Set(fixture.nativeExact.keys)
    let relatedNames = Set(fixture.nativeRelated.keys)

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.officialCount, 239)
    XCTAssertEqual(fixture.officialNames.count, fixture.officialCount)
    XCTAssertEqual(officialNames.count, fixture.officialCount)
    XCTAssertEqual(fixture.nativeExact.count, 62)
    XCTAssertEqual(fixture.nativeRelated.count, 3)
    XCTAssertTrue(exactNames.isSubset(of: officialNames))
    XCTAssertTrue(relatedNames.isSubset(of: officialNames))
    XCTAssertTrue(exactNames.isDisjoint(with: relatedNames))
    XCTAssertEqual(
      fixture.officialCount - exactNames.count - relatedNames.count,
      174)
    XCTAssertEqual(fixture.unlistedPolicy, "systemInputOrCustom")

    for rawValue in Array(fixture.nativeExact.values) + Array(fixture.nativeRelated.values) {
      XCTAssertNotNil(KeyboardLayout(rawValue: rawValue), "Unknown Typebar layout: \(rawValue)")
    }
  }
}
