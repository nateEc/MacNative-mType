import Foundation
import XCTest
@testable import Typebar

final class PersonalBestLedgerProfileTests: XCTestCase {
  private func payload() -> [String:Any] {
    let snapshot: [String:Any] = ["id":UUID().uuidString,"mode":"time","mode2":"15","durationSeconds":15,
      "language":"english","wpm":60,"rawWpm":61,"preciseWpm":60.49,"preciseRawWpm":61.49,
      "accuracy":100,"consistency":80,"finishedAt":100,"acceptedAtMilliseconds":1_800_000_000_875,
      "personalBestOrigin":"accepted","personalBestConfiguration":["version":1,"difficulty":"expert",
        "punctuation":false,"numbers":true,"lazyMode":false]]
    return ["id":UUID().uuidString,"displayName":"PB","joinedAt":100,"completedResultCount":1,
      "bestWPM":60,"personalBests":[],"personalBestLedgerVersion":1,"personalBestHistoryComplete":true,
      "personalBestSnapshots":[snapshot]]
  }
  private func decode(_ value: [String:Any]) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self,from:JSONSerialization.data(withJSONObject:value))
  }
  func testCompleteSnapshotsAndVersionSurviveNativeRoundTrip() throws {
    let profile = try decode(payload())
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(profile)) as? [String:Any])
    XCTAssertEqual(json["personalBestLedgerVersion"] as? Int,1)
    XCTAssertEqual((json["personalBestSnapshots"] as? [[String:Any]])?.count,1)
    XCTAssertEqual(json["personalBestHistoryComplete"] as? Bool,true)
    XCTAssertEqual(profile.displayPersonalBests.count,1)
    XCTAssertEqual(profile.displayPersonalBests[0].speedText,"60.49")
    XCTAssertEqual(profile.displayPersonalBests[0].rawSpeedText,"61.49")
    XCTAssertTrue(profile.displayPersonalBests[0].groupingLabel.contains("专家"))
    XCTAssertTrue(profile.displayPersonalBests[0].groupingLabel.contains("数字开"))
    XCTAssertEqual(profile.displayPersonalBests[0].recordedAt.timeIntervalSince1970,1_800_000_000.875)
  }
  func testKnownEmptyNeverFallsBackToOldStandardModeProjection() throws {
    var json = payload(); json["personalBests"] = json["personalBestSnapshots"]; json["personalBestSnapshots"] = []
    let profile = try decode(json)
    XCTAssertEqual(profile.personalBests.count,1); XCTAssertTrue(profile.displayPersonalBests.isEmpty)
  }
  func testAbsentOldLedgerRemainsLegacyAndUnknownControlsAreNotDefaults() throws {
    var json = payload(); json["personalBests"] = json["personalBestSnapshots"]
    for key in ["personalBestLedgerVersion","personalBestHistoryComplete","personalBestSnapshots"] { json.removeValue(forKey:key) }
    let old = try decode(json); XCTAssertNil(old.personalBestLedgerVersion); XCTAssertEqual(old.displayPersonalBests.count,1)
    var snapshots = try XCTUnwrap(json["personalBests"] as? [[String:Any]])
    snapshots[0].removeValue(forKey:"personalBestConfiguration"); json["personalBests"] = snapshots
    let unknown = try decode(json); XCTAssertEqual(unknown.displayPersonalBests[0].groupingLabel,"选项未知")
  }
  func testDuplicateGroupsAndNoncanonicalCompanionRatesCannotRender() throws {
    for key in ["preciseRawWpm","rawWpm","accuracy","consistency","mode2","personalBestOrigin"] {
      var json = payload(), snapshots = try XCTUnwrap(json["personalBestSnapshots"] as? [[String:Any]])
      snapshots[0][key] = NSNull(); json["personalBestSnapshots"] = snapshots
      XCTAssertThrowsError(try decode(json))
    }
    var json = payload(), snapshots = try XCTUnwrap(json["personalBestSnapshots"] as? [[String:Any]])
    var second = snapshots[0]; second["id"] = UUID().uuidString; snapshots.append(second)
    json["personalBestSnapshots"] = snapshots; XCTAssertThrowsError(try decode(json))
  }
  func testClearCapabilityRequiresExactServiceVersionAndAvailableState() {
    XCTAssertTrue(RemoteServiceCapabilities(apiVersion:"v1",service:"typebar",capabilities:["accountPersonalBestLedger":"available"]).supportsPersonalBestLedger)
    for (version,service,state) in [("v2","typebar","available"),("v1","other","available"),
      ("v1","typebar","partial"),("v1","typebar","planned"),("v1","typebar","")] {
      XCTAssertFalse(RemoteServiceCapabilities(apiVersion:version,service:service,
        capabilities:["accountPersonalBestLedger":state]).supportsPersonalBestLedger)
    }
  }
  func testLegacyUnknownModeParameterRemainsUnknownInsteadOfInventingAStandardBucket() throws {
    var json = payload(), snapshots = try XCTUnwrap(json["personalBestSnapshots"] as? [[String:Any]])
    snapshots[0]["mode"] = "words"; snapshots[0]["mode2"] = "unknown"
    snapshots[0].removeValue(forKey:"durationSeconds"); snapshots[0].removeValue(forKey:"personalBestConfiguration")
    json["personalBestSnapshots"] = snapshots
    let profile = try decode(json); XCTAssertEqual(profile.displayPersonalBests[0].configurationLabel,"词数未知")
    XCTAssertEqual(profile.displayPersonalBests[0].groupingLabel,"选项未知")
  }
  func testMalformedOrIncompleteLedgerMetadataCannotBecomeLegacyFallback() throws {
    for key in ["personalBestLedgerVersion","personalBestHistoryComplete","personalBestSnapshots"] {
      for value: Any? in [nil,NSNull(),"bad"] {
        var json = payload(); json[key] = value
        XCTAssertThrowsError(try decode(json))
      }
    }
    var json = payload(); json["personalBestLedgerVersion"] = 2; XCTAssertThrowsError(try decode(json))
  }
  func testMalformedKnownSnapshotCannotHideInsideAValidLedger() throws {
    for (key,value): (String,Any) in [("mode2","60"),("rawWpm",20),("acceptedAtMilliseconds",-1),
      ("personalBestOrigin","unknown"),("personalBestConfiguration",NSNull())] {
      var json = payload(), snapshots = try XCTUnwrap(json["personalBestSnapshots"] as? [[String:Any]])
      snapshots[0][key] = value; json["personalBestSnapshots"] = snapshots
      XCTAssertThrowsError(try decode(json))
    }
  }
}
