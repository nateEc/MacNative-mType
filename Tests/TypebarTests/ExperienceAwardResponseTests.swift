import Foundation
import XCTest
@testable import Typebar

final class ExperienceAwardResponseTests: XCTestCase {
  func testFractionalReceiptAndOlderWeeklyResponseDecodeWithoutTruncation() throws {
    let id = UUID().uuidString
    let receipt = Data("""
      {"id":"\(id)","accepted":true,"leaderboardEligible":true,
       "experienceGained":52.5,"totalExperience":70,"dailyXpBonus":true,
       "xpBreakdown":{"base":26,"daily":0.5}}
      """.utf8)
    let decoded = try JSONDecoder().decode(RemoteResultSubmissionResponse.self, from: receipt)
    XCTAssertEqual(decoded.experienceGained, 52.5); XCTAssertEqual(decoded.totalExperience, 70)
    XCTAssertEqual(decoded.dailyXpBonus, true); XCTAssertEqual(decoded.xpBreakdown?["daily"], 0.5)
    let entry = Data("""
      {"id":"\(id)","userID":"\(id)","rank":1,"displayName":"Award","totalExperience":52.5}
      """.utf8)
    XCTAssertEqual(try JSONDecoder().decode(RemoteExperienceLeaderboardEntry.self, from: entry).totalExperience, 52.5)
  }

  func testLegacyIntegerAndMissingMetadataKeepTheirMeaning() throws {
    let id = UUID().uuidString
    let data = Data("""
      {"id":"\(id)","accepted":true,"leaderboardEligible":false,"experienceGained":18,"totalExperience":36}
      """.utf8)
    let receipt = try JSONDecoder().decode(RemoteResultSubmissionResponse.self, from: data)
    XCTAssertEqual(receipt.experienceGained, 18); XCTAssertEqual(receipt.totalExperience, 36)
    XCTAssertNil(receipt.dailyXpBonus); XCTAssertNil(receipt.xpBreakdown)
    let roundTrip = try JSONDecoder().decode(RemoteResultSubmissionResponse.self, from: JSONEncoder().encode(receipt))
    XCTAssertEqual(roundTrip.experienceGained, receipt.experienceGained)
  }

  func testFractionalPresentationDoesNotLoseSmallBonuses() {
    XCTAssertEqual(ExperiencePresentation.compact(52.5), "52.5")
    XCTAssertEqual(ExperiencePresentation.compact(0.001), "0.001")
    XCTAssertEqual(ExperiencePresentation.compact(52.0), "52")
    XCTAssertEqual(ExperiencePresentation.compact(1_234.5), "1.2k")
    XCTAssertEqual(ExperiencePresentation.compact(Double.nan), "—")
  }

  func testBadRewardNumbersAndBreakdownRefuseDecoding() throws {
    let id = UUID().uuidString
    for (key, value): (String, Any) in [("experienceGained", -1), ("experienceGained", "NaN"),
      ("experienceGained", 9_007_199_254_740_992.0), ("totalExperience", -1),
      ("xpBreakdown", ["base":"Infinity"]), ("dailyXpBonus", "true")] {
      var object: [String: Any] = ["id":id,"accepted":true,"leaderboardEligible":true,"experienceGained":52.5,"totalExperience":52]
      object[key] = value
      let decoder = JSONDecoder()
      decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
      XCTAssertThrowsError(try decoder.decode(RemoteResultSubmissionResponse.self,
        from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testWeeklyLeaderboardRejectsUnsafeAndNonfiniteScores() throws {
    let id = UUID().uuidString
    for score: Any in [-1, 9_007_199_254_740_992.0, "NaN", "Infinity", NSNull()] {
      let object: [String: Any] = ["id":id,"userID":id,"rank":1,"displayName":"Award","totalExperience":score]
      let decoder = JSONDecoder()
      decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
      XCTAssertThrowsError(try decoder.decode(RemoteExperienceLeaderboardEntry.self,
        from: JSONSerialization.data(withJSONObject: object)))
    }
  }
}
