import Foundation
import XCTest
@testable import Typebar

final class PublicProfileLeaderboardTests: XCTestCase {
  private func payload() -> [String: Any] {
    ["id": UUID().uuidString, "displayName": "Owned rank profile", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0]
  }
  private func decode(_ value: [String: Any]) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: value))
  }
  func testActualProfileDecoderRetainsPublicRankingFields() throws {
    var value = payload()
    value["leaderboardOptedOut"] = true
    value["allTimeLbs"] = ["time": ["15": ["english": ["rank": 2, "count": 3]], "60": [:]]]
    let profile = try decode(value)
    let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
    XCTAssertEqual(restored["leaderboardOptedOut"] as? Bool, true)
    XCTAssertNotNil(restored["allTimeLbs"])
  }

  func testLegacyAndKnownEmptyDoNotInventRanks() throws {
    let legacy = try decode(payload())
    XCTAssertNil(legacy.leaderboardOptedOut); XCTAssertNil(legacy.allTimeLbs)
    XCTAssertTrue(PublicProfileLeaderboardPolicy.cards(legacy).isEmpty)
    var value = payload(); value["allTimeLbs"] = ["time": ["15": [:], "60": [:]]]
    XCTAssertTrue(PublicProfileLeaderboardPolicy.cards(try decode(value)).isEmpty)
  }
  func testOnlyEnglishStandardBucketsDisplayInFixedOrderAndPrivacyFlagsWin() throws {
    var value = payload()
    value["allTimeLbs"] = ["time": ["60": ["english": ["rank": 1, "count": 3]],
      "15": ["english": ["rank": 2, "count": 3], "french": ["rank": 1, "count": 8]],
      "30": ["english": ["rank": 1, "count": 8]]]]
    let cards = PublicProfileLeaderboardPolicy.cards(try decode(value))
    XCTAssertEqual(cards.map(\.id), [15, 60]); XCTAssertEqual(cards.map(\.rankLabel), ["第 2 名", "第 1 名"])
    XCTAssertEqual(cards.map(\.standingLabel), ["前 66.67%", "GOAT"])
    for flag in ["leaderboardOptedOut", "accountSuspended"] {
      var hidden = value; hidden[flag] = true
      XCTAssertTrue(PublicProfileLeaderboardPolicy.cards(try decode(hidden)).isEmpty)
    }
  }
  func testUnknownRankAndZeroCountStaySafeAndMalformedValuesReject() throws {
    for position in [["count": 0], ["rank": 2, "count": 0]] {
      var value = payload(); value["allTimeLbs"] = ["time": ["15": ["english": position]]]
      let card = try XCTUnwrap(PublicProfileLeaderboardPolicy.cards(try decode(value)).first)
      XCTAssertEqual(card.standingLabel, "—")
      XCTAssertEqual(card.rankLabel, position["rank"].map { "第 \($0) 名" } ?? "—")
    }
    let invalid: [[String: Any]] = [["count": -1], ["rank": -1, "count": 1],
      ["rank": 1.5, "count": 3], ["rank": 1], ["count": "3"]]
    for position in invalid {
      var value = payload(); value["allTimeLbs"] = ["time": ["15": ["english": position]]]
      XCTAssertThrowsError(try decode(value))
    }
  }
  func testPinnedCompleteProfileRankingProjectionAndPercentages() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-profile-ranks.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Document: Decodable {
      struct Projection: Decodable { let profile: RemotePublicProfile; let parameters: [Int]; let ranks: [Int?] }
      struct Format: Decodable { let profile: RemotePublicProfile; let expected: String }
      let projections: [Projection]; let formats: [Format]
    }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.projections.count, 25); XCTAssertEqual(document.formats.count, 24)
    for fixture in document.projections {
      let cards = PublicProfileLeaderboardPolicy.cards(fixture.profile)
      XCTAssertEqual(cards.map(\.seconds), fixture.parameters)
      XCTAssertEqual(cards.map { $0.position.rank }, fixture.ranks)
    }
    for fixture in document.formats {
      let card = try XCTUnwrap(PublicProfileLeaderboardPolicy.cards(fixture.profile).first)
      XCTAssertEqual(card.standingLabel, fixture.expected.replacingOccurrences(of: "Top ", with: "前 ") == "-"
        ? "—" : fixture.expected.replacingOccurrences(of: "Top ", with: "前 "))
    }
  }
}
