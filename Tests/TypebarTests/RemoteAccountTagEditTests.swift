import Foundation
import XCTest
@testable import Typebar

final class RemoteAccountTagEditTests: XCTestCase {
  func testFlatEditResponseSeparatesAwardsFromImmutableMetadataAndRejectsUnknownIDs() throws {
    let tag = UUID(), foreign = UUID()
    var root: [String: Any] = ["id": UUID().uuidString, "mode": "time", "language": "english",
      "durationSeconds": 15, "wpm": 60, "rawWpm": 70, "accuracy": 98, "consistency": 80,
      "errorCount": 1, "eventCount": 75, "tags": ["owned text"], "startedAt": 100, "finishedAt": 115,
      "accountTagIDs": [tag.uuidString], "tagPbs": [tag.uuidString]]
    func decode() throws -> RemoteAccountTagEditResponse {
      try JSONDecoder().decode(RemoteAccountTagEditResponse.self, from: JSONSerialization.data(withJSONObject: root))
    }
    let response = try decode()
    XCTAssertEqual(response.tagPbs, [tag]); XCTAssertEqual(response.result.accountTagIDs, [tag])
    let old = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject: root))
    XCTAssertEqual(response.result, old)
    XCTAssertFalse(String(decoding: try JSONEncoder().encode(response.result), as: UTF8.self).contains("tagPbs"))
    for value: Any in [[foreign.uuidString], [tag.uuidString, tag.uuidString], NSNull()] {
      root["tagPbs"] = value; XCTAssertThrowsError(try decode())
    }
    root.removeValue(forKey: "tagPbs"); XCTAssertThrowsError(try decode())
    root["tagPbs"] = []; XCTAssertTrue(try decode().tagPbs.isEmpty)
  }
  func testOldOrForeignCapabilityCannotSilentlyPerformNoAwardEdit() throws {
    let ready = RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["accountTags": "available", "accountTagEditPersonalBests": "available"])
    XCTAssertNoThrow(try RemoteAccountTagEditPolicy.requireCapabilities(ready))
    for value in [RemoteServiceCapabilities(apiVersion: "v1", service: "typebar", capabilities: ["accountTags": "available"]),
      .init(apiVersion: "v2", service: "typebar", capabilities: ready.capabilities),
      .init(apiVersion: "v1", service: "owned-other", capabilities: ready.capabilities),
      .init(apiVersion: "v1", service: "typebar", capabilities: ["accountTagEditPersonalBests": "available"])] {
      XCTAssertThrowsError(try RemoteAccountTagEditPolicy.requireCapabilities(value))
    }
  }
}
