import Foundation
import XCTest
@testable import TypebarServerCore

final class WeeklyExperiencePartitionTests: XCTestCase {
  private let password = "a secure password"
  private func date(_ text: String) throws -> Date {
    try XCTUnwrap(ISO8601DateFormatter().date(from:text))
  }
  private func zone(_ text: String) throws -> TimeZone { try XCTUnwrap(TimeZone(identifier:text)) }
  private func request(at end: Date) -> ResultSubmissionRequest {
    .init(id:UUID(),mode:"words",language:"english",durationSeconds:nil,wordLimit:25,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,
      startedAt:end.addingTimeInterval(-15),finishedAt:end)
  }
  private func directory() throws -> URL {
    let value = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-week-partition-\(UUID())")
    try FileManager.default.createDirectory(at:value,withIntermediateDirectories:false)
    return value
  }
  private func json(_ file: URL) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
  }

  func testActualPinnedDateUtilityAndControllerWeekSelector() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the read-only pinned source")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-partition.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Fixture: Decodable { let zone:String; let timestamp:Int; let currentKey:Int; let previousKey:Int }
    struct Document: Decodable { let referenceCommit:String; let fixtures:[Fixture]; let subtractionDifferences:Int }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertGreaterThan(document.fixtures.count,20_000)
    XCTAssertGreaterThan(document.subtractionDifferences,0)
    for fixture in document.fixtures {
      let value = try WeeklyExperiencePartition.capture(at:Date(timeIntervalSince1970:Double(fixture.timestamp)/1_000),
        timeZone:zone(fixture.zone))
      XCTAssertEqual(value.keyMilliseconds,fixture.currentKey,"\(fixture.zone)/\(fixture.timestamp)")
      XCTAssertEqual(value.keyMilliseconds - WeeklyExperiencePartition.week,fixture.previousKey)
    }
  }

  func testDeploymentTimeZoneIsExplicitAndInvalidConfigurationFails() throws {
    XCTAssertEqual(try WeeklyExperiencePartition.configuredTimeZone("Asia/Shanghai").identifier,"Asia/Shanghai")
    XCTAssertEqual(try WeeklyExperiencePartition.configuredTimeZone(nil),TimeZone.current)
    for value in ["", "unknown/invalid", " Asia/Shanghai", "Asia/Shanghai "] {
      XCTAssertThrowsError(try WeeklyExperiencePartition.configuredTimeZone(value))
    }
  }

  func testUnsafeClocksAndMismatchedAcceptanceAreRejected() throws {
    let utc = try zone("UTC"), now = try date("2026-10-05T12:00:00Z")
    let value = try WeeklyExperiencePartition.capture(at:now,timeZone:utc)
    for seconds in [Double.nan,Double.infinity,-Double.infinity,8_640_000_000_001] {
      let bad = Date(timeIntervalSince1970:seconds)
      XCTAssertThrowsError(try WeeklyExperiencePartition.capture(at:bad,timeZone:utc))
      XCTAssertThrowsError(try value.validate(acceptedAt:bad))
    }
    XCTAssertThrowsError(try value.validate(acceptedAt:nil))
    XCTAssertThrowsError(try value.validate(acceptedAt:now.addingTimeInterval(1)))
  }

  func testInvalidQueryClockDoesNotBecomeAnEmptyLeaderboard() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4)
    do {
      _ = try await store.experienceLeaderboard(now:Date(timeIntervalSince1970:.infinity))
      XCTFail("Invalid week selection must fail, not return a plausible empty page")
    } catch let error as ExperienceCalculationError {
      XCTAssertEqual(error,.invalidInput)
    }
  }

  func testShanghaiUTCWeekBoundaryUsesAcceptanceAndPreviousKeyNotLocalISOInterval() async throws {
    let start = try date("2026-10-05T00:00:00Z"), before = start.addingTimeInterval(-1)
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("Asia/Shanghai"))
    let owner = try await store.register(.init(email:"week@example.com",password:password,displayName:"Week"),now:before)
    _ = try await store.submitResult(request(at:before),accessToken:owner.accessToken,now:before)
    let boundary = try await store.experienceLeaderboard(now:start)
    let previous = try await store.experienceLeaderboard(period:"lastWeek",now:start)
    XCTAssertTrue(boundary.entries.isEmpty)
    XCTAssertEqual(previous.entries.map(\.userID),[owner.user.id])
    // The result itself ended before the UTC boundary; accepting it after the
    // boundary belongs to the new key, not the client's finish or start date.
    let receipt = try await store.submitResult(request(at:before),accessToken:owner.accessToken,now:start)
    let current = try await store.experienceLeaderboard(now:start)
    XCTAssertEqual(current.entries.first?.totalExperience,receipt.experienceGained)
  }

  func testFrozenPartitionSurvivesFractionalClockReloadTimeZoneChangeHistoryDeletionAndRetry() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json")
    let now = try date("2026-10-05T12:00:00Z").addingTimeInterval(0.875)
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("America/Los_Angeles"))
    let owner = try await store.register(.init(email:"frozen@example.com",password:password,displayName:"Frozen"),now:now)
    let input = request(at:now)
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    _ = try await store.deleteResults(.init(currentPassword:password),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file)
    let shifted = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("UTC"))
    let wrongKey = try await shifted.experienceLeaderboard(now:now)
    XCTAssertTrue(wrongKey.entries.isEmpty,"A new server time zone must not recalculate saved partitions")
    XCTAssertEqual(try Data(contentsOf:file),bytes,"Pure reads and reloads never migrate the file")
    _ = try await shifted.submitResult(input,accessToken:owner.accessToken,now:now.addingTimeInterval(7 * 86_400))
    let awards = try XCTUnwrap(json(file)["experienceAwards"] as? [[String:Any]])
    XCTAssertEqual(awards.count,1)
    let partition = try XCTUnwrap(awards[0]["weeklyPartition"] as? [String:Any])
    XCTAssertEqual(partition["timeZoneIdentifier"] as? String,"America/Los_Angeles")
    XCTAssertEqual(partition["acceptedMilliseconds"] as? Int,Int(now.timeIntervalSince1970 * 1_000))
    let restored = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("America/Los_Angeles"))
    let board = try await restored.experienceLeaderboard(now:now)
    XCTAssertEqual(board.entries.map(\.userID),[owner.user.id])
  }

  func testMissingLegacyPartitionKeepsOldFinishedAtReadPathAndDoesNotBackfill() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), now = try date("2026-10-05T12:00:00Z")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("UTC"))
    let owner = try await store.register(.init(email:"legacy@example.com",password:password,displayName:"Legacy"),now:now)
    _ = try await store.submitResult(request(at:now.addingTimeInterval(-6 * 86_400)),accessToken:owner.accessToken,now:now)
    var object = try json(file), awards = try XCTUnwrap(object["experienceAwards"] as? [[String:Any]])
    awards[0].removeValue(forKey:"weeklyPartition"); object["experienceAwards"] = awards
    let legacy = try JSONSerialization.data(withJSONObject:object)
    try legacy.write(to:file,options:.atomic)
    let loaded = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("UTC"))
    let current = try await loaded.experienceLeaderboard(now:now)
    let previous = try await loaded.experienceLeaderboard(period:"lastWeek",now:now)
    XCTAssertTrue(current.entries.isEmpty); XCTAssertEqual(previous.entries.map(\.userID),[owner.user.id])
    XCTAssertEqual(try Data(contentsOf:file),legacy)
  }

  func testMalformedExplicitPartitionRejectsReloadWithoutChangingBytes() async throws {
    let dir = try directory(); defer { try? FileManager.default.removeItem(at:dir) }
    let file = dir.appendingPathComponent("store.json"), now = try date("2026-10-05T12:00:00Z")
    let store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development,
      weeklyExperienceTimeZone:zone("UTC"))
    let owner = try await store.register(.init(email:"invalid@example.com",password:password,displayName:"Invalid"),now:now)
    _ = try await store.submitResult(request(at:now),accessToken:owner.accessToken,now:now)
    let original = try json(file), originalAwards = try XCTUnwrap(original["experienceAwards"] as? [[String:Any]])
    let valid = try XCTUnwrap(originalAwards[0]["weeklyPartition"] as? [String:Any])
    var shapes:[Any] = [NSNull(), "invalid"]
    for (field,value) in [("version",2),("keyMilliseconds",1),("acceptedMilliseconds",1),
      ("anchorOffsetSeconds",Int.max),("projectedOffsetSeconds",Int.min),("gapSeconds",-1)] {
      var corrupt = valid; corrupt[field] = value; shapes.append(corrupt)
    }
    for shape in shapes {
      var object = original, awards = originalAwards
      awards[0]["weeklyPartition"] = shape; object["experienceAwards"] = awards
      let bytes = try JSONSerialization.data(withJSONObject:object); try bytes.write(to:file,options:.atomic)
      XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4))
      XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }
}
