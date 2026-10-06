import Foundation
import XCTest
@testable import Typebar

final class SpeedPrecisionPublicationTests: XCTestCase {
  private func result(wpm: Double = 60.41, raw: Double = 60.49) -> CompletedTestResult {
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    return .init(id: UUID(), configuration: .words(25), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(900 / wpm), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: Int(wpm.rounded()), rawWpm: Int(raw.rounded()),
      accuracy: 100, preciseWpm: wpm, preciseRawWpm: raw, prompt: "private text", replayEvents: [])
  }
  private var capabilities: RemoteServiceCapabilities {
    .init(apiVersion: "v1", service: "typebar", capabilities: ["resultSpeedPrecision":"available"])
  }
  private func object<T: Encodable>(_ value: T) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  }
  @MainActor func testNegotiatedSubmissionPreservesCapturedSpeedAndCSVUsesIt() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities)
    let json = try object(wire)
    XCTAssertEqual(json["speedPrecision"] as? NSDictionary,
      ["version":1,"wpm":60.41,"rawWpm":60.49] as NSDictionary)
    var historyJSON = json
    historyJSON["speedPrecision"] = ["version":1,"wpm":60.41,"rawWpm":60.49]
    let history = try JSONDecoder().decode(RemoteAccountResult.self, from: JSONSerialization.data(withJSONObject:historyJSON))
    let cells = RemoteResultCSVExport.csvString(for: [history]).components(separatedBy:"\r\n")[1].components(separatedBy:",")
    XCTAssertEqual(cells[5],"60.41"); XCTAssertEqual(cells[6],"60.49")
    XCTAssertFalse(String(describing:json).contains("private text"))
  }
  @MainActor func testOldServiceCannotSilentlyRoundAwayCapturedFractions() async throws {
    do { _ = try await ResultConsistencyPublication.prepare(result:result(),capabilities:nil)
      XCTFail("A fraction cannot become an integer-only submission")
    } catch { XCTAssertTrue(error is RemoteAccountError) }
    let safe = try await ResultConsistencyPublication.prepare(result:result(wpm:60,raw:60),capabilities:nil)
    XCTAssertNil(try object(safe)["speedPrecision"])
  }
  func testExplicitInvalidPrecisionCannotBecomeUnknownHistory() throws {
    let base = try object(RemoteResultSubmission(result:result()))
    for report: Any in [NSNull(),["version":2,"wpm":60.41,"rawWpm":60.49],
      ["version":1,"wpm":60.41],["version":1,"wpm":61.41,"rawWpm":62.0]] {
      var json = base; json["speedPrecision"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:json)))
    }
  }

  @MainActor func testExactCapabilityAndEarlyRefusal() async throws {
    for (api,service,status) in [("v1","typebar","partial"),("v1","typebar","planned"),
      ("v2","typebar","available"),("v1","other","available")] {
      let cap = RemoteServiceCapabilities(apiVersion:api,service:service,
        capabilities:["resultSpeedPrecision":status,"resultConsistency":"available"])
      do { _ = try await ResultConsistencyPublication.prepare(result:result(),capabilities:cap) { _ in
        XCTFail("Refuse before statistics work"); return 0
      }; XCTFail("Do not silently lose fractions") } catch { XCTAssertTrue(error is RemoteAccountError) }
      let legacy = try await ResultConsistencyPublication.prepare(result:result(wpm:60,raw:60),capabilities:cap)
      XCTAssertNil(legacy.speedPrecision)
    }
  }

  @MainActor func testSourceRoundingAndDatePrecisionSurviveISOAndPortableSnapshots() async throws {
    let saved = result(wpm:60.495,raw:60.495)
    let portable = try XCTUnwrap(TestResultRecord(result:saved).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from:TypebarDataTransfer.exportArchive(
      settings:.init(),results:[saved],presets:[],at:saved.finishedAt))
    XCTAssertEqual(archive.version,TypebarArchive.currentVersion)
    for value in [saved,portable,try XCTUnwrap(archive.results.first)] {
      let wire = try await ResultConsistencyPublication.prepare(result:value,capabilities:capabilities)
      XCTAssertEqual(wire.speedPrecision?.wpm,60.5); XCTAssertEqual(wire.wpm,61)
      let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
      let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
      let history = try decoder.decode(RemoteAccountResult.self,from:encoder.encode(wire))
      XCTAssertEqual(history.startedAt,value.startedAt); XCTAssertEqual(history.finishedAt,value.finishedAt)
      XCTAssertEqual(history.speedText,"60.50"); XCTAssertEqual(value.preciseWpm,saved.preciseWpm)
    }
  }

  @MainActor func testBoundariesAndRequiredCounterCapability() async throws {
    for value in [0.0,420] {
      // Zero needs a finite fixture duration, but publication never recalculates the score.
      let saved = value == 0 ? result(wpm:1,raw:1) : result(wpm:value,raw:value)
      var json = try object(saved); json["preciseWpm"] = value; json["preciseRawWpm"] = value
      let input = try JSONDecoder().decode(CompletedTestResult.self,from:JSONSerialization.data(withJSONObject:json))
      let wire = try await ResultConsistencyPublication.prepare(result:input,capabilities:capabilities)
      XCTAssertEqual(wire.speedPrecision?.wpm,value)
    }
    for saved in [result(wpm:420.01,raw:420.01),result(wpm:60.41,raw:60.4)] {
      do { _ = try await ResultConsistencyPublication.prepare(result:saved,capabilities:capabilities)
        XCTFail("Out of bounds or inverted speeds must remain local")
      } catch { XCTAssertTrue(error is RemoteAccountError) }
    }
    var json = try object(result())
    json["inputMetrics"] = ["version":2,"correctAttempts":75,"totalAttempts":75,"creditedUnits":75,
      "retainedUnits":75,"retainedInputUnits":75,"scoringUnitBasis":"utf16"] as [String:Any]
    let counted = try JSONDecoder().decode(CompletedTestResult.self,from:JSONSerialization.data(withJSONObject:json))
    do { _ = try await ResultConsistencyPublication.prepare(result:counted,capabilities:capabilities)
      XCTFail("A v2 counter cannot be dropped beside precision")
    } catch { XCTAssertTrue(error is RemoteAccountError) }
    let cap = RemoteServiceCapabilities(apiVersion:"v1",service:"typebar",
      capabilities:["resultSpeedPrecision":"available","resultInputMetricsV2":"available"])
    let wire = try await ResultConsistencyPublication.prepare(result:counted,capabilities:cap)
    XCTAssertEqual(wire.inputMetrics?.version,2); XCTAssertNotNil(wire.speedPrecision)
  }

  func testEveryReportFieldAndDateSupplementIsMandatory() throws {
    var base = try object(RemoteResultSubmission(result:result()))
    base["startedAtReferenceTime"] = result().startedAt.timeIntervalSinceReferenceDate
    base["finishedAtReferenceTime"] = result().finishedAt.timeIntervalSinceReferenceDate
    let good: [String:Any] = ["version":1,"wpm":60.41,"rawWpm":60.49]
    for (key,value): (String,Any) in [("version",2),("wpm",-1.0),("rawWpm",421.0),("wpm",60.411),
      ("wpm","NaN"),("rawWpm",true)] {
      var report = good; report[key] = value; var json = base; json["speedPrecision"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:json)))
    }
    for key in good.keys {
      var report = good; report.removeValue(forKey:key); var json = base; json["speedPrecision"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:json)))
    }
    for key in ["startedAtReferenceTime","finishedAtReferenceTime"] {
      for value: Any? in [nil,NSNull(),"NaN",900_000_100.0] {
        var json = base; json["speedPrecision"] = good; json[key] = value
        XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:json)))
      }
    }
  }

  func testPublicConsumersValidatePrecisionAndKeepLegacyPresentation() throws {
    let identifier = UUID().uuidString, date = 900_000_000.0
    var best: [String:Any] = ["id":identifier,"mode":"words","wordLimit":25,"language":"english",
      "wpm":60,"accuracy":100,"consistency":0,"finishedAt":date]
    var leaderboard = best; leaderboard["rank"] = 1; leaderboard["userID"] = UUID().uuidString
    leaderboard["displayName"] = "Owned"
    var profile: [String:Any] = ["id":identifier,"displayName":"Owned","joinedAt":date,
      "completedResultCount":1,"bestWPM":60,"highestConsistency":0]
    for precision in [false,true] {
      best["preciseWpm"] = precision ? 60.49 : nil; leaderboard["preciseWpm"] = precision ? 60.49 : nil
      profile["preciseBestWPM"] = precision ? 60.49 : nil; profile["personalBests"] = [best]
      let pb = try JSONDecoder().decode(RemotePublicProfileBest.self,from:JSONSerialization.data(withJSONObject:best))
      let entry = try JSONDecoder().decode(RemoteLeaderboardEntry.self,from:JSONSerialization.data(withJSONObject:leaderboard))
      let publicProfile = try JSONDecoder().decode(RemotePublicProfile.self,from:JSONSerialization.data(withJSONObject:profile))
      XCTAssertEqual(pb.speedText,precision ? "60.49" : "60")
      XCTAssertEqual(entry.speedText,pb.speedText); XCTAssertEqual(publicProfile.bestSpeedText,pb.speedText)
    }
    for value: Any in [NSNull(),"NaN",61.49,60.499] {
      best["preciseWpm"] = value; leaderboard["preciseWpm"] = value; profile["preciseBestWPM"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(RemotePublicProfileBest.self,from:JSONSerialization.data(withJSONObject:best)))
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteLeaderboardEntry.self,from:JSONSerialization.data(withJSONObject:leaderboard)))
      XCTAssertThrowsError(try JSONDecoder().decode(RemotePublicProfile.self,from:JSONSerialization.data(withJSONObject:profile)))
    }
  }

  @MainActor func testCancelledPrecisionPreparationCannotProduceAPayload() async throws {
    let saved = result(), cap = capabilities
    let task = Task { try await ResultConsistencyPublication.prepare(result:saved,capabilities:cap) }; task.cancel()
    do { _ = try await task.value; XCTFail("Cancelled request cannot escape") } catch is CancellationError {}
  }

  func testCalculationAndRoundingAgainstCompletePinnedSourceModules() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned source") }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-speed-precision.mjs")
    let process = Process(), pipe = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,reference,"--emit-fixtures"]
    process.standardOutput = pipe; process.standardError = errors; try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile(), error = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0,String(decoding:error,as:UTF8.self))
    struct Round: Decodable { let input:Double; let expected:Double }
    struct Speed: Decodable { let units:Int; let seconds:Double; let expected:Double }
    struct Document: Decodable { let referenceCommit:String; let rounding:[Round]; let speeds:[Speed] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.rounding.count,8); XCTAssertEqual(document.speeds.count,6)
    for fixture in document.rounding { XCTAssertEqual(ResultTerminalTiming.round(fixture.input),fixture.expected) }
    for fixture in document.speeds { XCTAssertEqual(ResultTerminalTiming.round(Double(fixture.units) / 5 / fixture.seconds * 60),fixture.expected) }
  }
}
