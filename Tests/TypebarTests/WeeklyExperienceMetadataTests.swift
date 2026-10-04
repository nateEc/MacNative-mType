import Foundation
import XCTest
@testable import Typebar

final class WeeklyExperienceMetadataTests: XCTestCase {
  private func entry(_ metadata: [String:Any] = [:]) throws -> RemoteExperienceLeaderboardEntry {
    let id = UUID().uuidString
    var object: [String:Any] = ["id":id,"userID":id,"rank":1,"displayName":"Metadata","totalExperience":52]
    object.merge(metadata) { _,value in value }
    return try JSONDecoder().decode(RemoteExperienceLeaderboardEntry.self,
      from:JSONSerialization.data(withJSONObject:object))
  }
  func testWeeklyTimeAndActivityAreNotDroppedByNativeResponseCodec() throws {
    let value = try entry(["timeTypedSeconds":45.75,"lastActivityTimestamp":1_800_000_030_875])
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
    XCTAssertEqual(object["timeTypedSeconds"] as? Double,45.75)
    XCTAssertEqual(object["lastActivityTimestamp"] as? Int,1_800_000_030_875)
  }
  func testOldMissingAndExplicitNullMetadataRemainUnknownRatherThanZero() throws {
    for object in [[:], ["timeTypedSeconds":NSNull(),"lastActivityTimestamp":NSNull()]] {
      let value = try entry(object)
      XCTAssertNil(value.timeTypedSeconds); XCTAssertNil(value.lastActivityTimestamp)
      XCTAssertEqual(WeeklyExperiencePresentation.duration(value.timeTypedSeconds),"—")
      XCTAssertEqual(WeeklyExperiencePresentation.activityLabel(value.lastActivityTimestamp),"活动时间未知")
    }
  }
  func testInvalidTimingTypesAndBoundsAreRejectedInsteadOfDropped() throws {
    for value: Any in [-1,9_007_199_254_740_992,"15",true] {
      XCTAssertThrowsError(try entry(["timeTypedSeconds":value]))
    }
    for value: Any in [8_640_000_000_000_001,Int.max,1.5,"1800000000000",true] {
      XCTAssertThrowsError(try entry(["lastActivityTimestamp":value]))
    }
  }
  func testClockUsesWholeSecondsHoursAndJavaScriptNonnegativeHalfRounding() {
    for (seconds,expected) in [(0.0,"00:00:00"),(0.49,"00:00:00"),(0.5,"00:00:01"),
      (59.49,"00:00:59"),(59.5,"00:01:00"),(3599.5,"01:00:00"),(86400.0,"24:00:00"),
      (360_000.0,"100:00:00")] {
      XCTAssertEqual(WeeklyExperiencePresentation.duration(seconds),expected)
    }
    for value in [Double.nan,.infinity,-1,9_007_199_254_740_992] {
      XCTAssertEqual(WeeklyExperiencePresentation.duration(value),"—")
    }
  }
  func testActivityUsesEpochMillisecondsWithoutDroppingFractionalSeconds() {
    XCTAssertEqual(WeeklyExperiencePresentation.activityDate(1_800_000_030_875)?.timeIntervalSince1970,1_800_000_030.875)
    XCTAssertEqual(WeeklyExperiencePresentation.activityDate(-875)?.timeIntervalSince1970,-0.875)
    XCTAssertNil(WeeklyExperiencePresentation.activityDate(nil))
    XCTAssertNil(WeeklyExperiencePresentation.activityDate(Int.min))
  }
  func testActualPinnedFrontendDurationFormatter() throws {
    guard let root = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned read-only source and date runtime")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-weekly-xp-presentation.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node","--experimental-vm-modules",script.path,root,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let diagnostics = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:diagnostics,as:UTF8.self))
    struct Fixture: Decodable { let seconds:Double; let label:String }
    struct Document: Decodable { let referenceCommit:String; let fixtures:[Fixture] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.fixtures.count,18)
    for fixture in document.fixtures { XCTAssertEqual(WeeklyExperiencePresentation.duration(fixture.seconds),fixture.label) }
  }
}
