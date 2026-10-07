import Foundation
import XCTest
@testable import Typebar

final class AccountResultChartTests: XCTestCase {
  private func rowObject() -> [String: Any] {
    ["id": UUID().uuidString, "mode": "time", "mode2": "15", "durationSeconds": 15,
      "language": "english", "wpm": 60, "rawWpm": 60, "accuracy": 100,
      "consistency": 80, "errorCount": 0, "eventCount": 75, "tags": [],
      "startedAt": 100, "finishedAt": 115]
  }
  private func chart(_ count: Int = 15) -> AccountResultChartData {
    .init(samples:(1...count).map { .init(elapsed:Double($0),wpm:60.25,burst:84.5,errors:$0 == 2 ? 2 : 0) })
  }
  private func row(chart: AccountResultChartData? = nil, available: Bool? = nil) throws -> RemoteAccountResult {
    var object = rowObject()
    if let chart { object["performanceChart"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(chart)) }
    object["hasPerformanceChart"] = available
    return try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:object))
  }
  private func result(duration: Double = 15, hasReplay: Bool = true) -> CompletedTestResult {
    let start = Date(timeIntervalSinceReferenceDate:900_000_000)
    return .init(id:UUID(),configuration:.timed(seconds:duration),outcome:.completed,
      startedAt:start,finishedAt:start.addingTimeInterval(duration),typedCharacterCount:75,
      correctCharacterCount:75,errorCount:0,wpm:60,rawWpm:60,accuracy:100,prompt:"ab cd x",
      replayEvents:hasReplay ? [.init(offset:0,kind:.insert,text:"ab ",inputField:.init(index:0,value:"ab "))] : [])
  }
  func testMalformedPresentChartCannotSilentlyBecomeLegacyMissing() throws {
    for malformed: Any in [NSNull(), ["version": 99, "samples": []], "toolong"] {
      var object = rowObject(); object["performanceChart"] = malformed
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
        from: JSONSerialization.data(withJSONObject: object)))
    }
  }

  func testDecoderBindsAvailabilityAndDurationAndPreservesUnknown() throws {
    XCTAssertFalse(try row().canViewPerformanceChart)
    XCTAssertTrue(try row(available:true).canViewPerformanceChart)
    XCTAssertEqual(try row(chart:chart(),available:true).performanceChart,chart())
    XCTAssertThrowsError(try row(chart:chart(),available:false))
    var object = rowObject(); object["hasPerformanceChart"] = NSNull()
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:object)))
    object = rowObject(); object["performanceChart"] = try JSONSerialization.jsonObject(with:JSONEncoder().encode(chart(16)))
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:object)))
  }

  func testValidationRejectsOversizedUnorderedNegativeNonfiniteAndOutOfDurationSamples() throws {
    let valid = chart()
    XCTAssertTrue(valid.matches(duration:15)); XCTAssertFalse(valid.matches(duration:14))
    XCTAssertTrue(chart(122).matches(duration:122)); XCTAssertFalse(chart(122).matches(duration:122.001))
    let bad: [AccountResultChartData] = [.init(version:2,samples:valid.samples),.init(samples:[]),chart(123),
      .init(samples:valid.samples.reversed()),.init(samples:[valid.samples[0],valid.samples[0]])]
    for data in bad { XCTAssertFalse(data.isValid); XCTAssertThrowsError(try JSONEncoder().encode(data)) }
    for sample in [AccountResultChartData.Sample(elapsed:.nan,wpm:1,burst:1,errors:0),
      .init(elapsed:1,wpm:.infinity,burst:1,errors:0),.init(elapsed:1,wpm:1,burst:-1,errors:0),
      .init(elapsed:1,wpm:1_000_000_001,burst:1,errors:0),.init(elapsed:1,wpm:1,burst:1,errors:-1)] {
      XCTAssertFalse(AccountResultChartData(samples:[sample]).isValid)
    }
  }

  func testProducerUsesSavedReplayAndDoesNotInferFromFinalScores() throws {
    let saved = result(), data = try XCTUnwrap(AccountResultChartInput(saved).calculate())
    let points = ResultPerformanceTrace.points(prompt:saved.prompt,events:saved.replayEvents,duration:saved.chartDuration,
      configuration:saved.configuration,targetWordDirectory:saved.targetWordDirectory,sourceScoringBasis:saved.characterStats.sourceUnitBasis)
    XCTAssertEqual(data.samples.map(\.elapsed),points.map(\.elapsed))
    XCTAssertEqual(data.samples.map(\.wpm),points.map { Double($0.wpm) })
    XCTAssertEqual(data.samples.map(\.burst),points.map(\.burstWpm)); XCTAssertEqual(data.samples.map(\.errors),points.map(\.errorCount))
    XCTAssertEqual(data.samples.count,15); XCTAssertEqual(data.samples.first?.elapsed,1)
    XCTAssertNil(try AccountResultChartInput(result(hasReplay:false)).calculate())
    XCTAssertNil(try AccountResultChartInput(result(duration:123)).calculate())
    XCTAssertNotNil(try AccountResultChartInput(result(duration:122)).calculate())
    let portable = try XCTUnwrap(TestResultRecord(result:saved).portableResult)
    XCTAssertEqual(try AccountResultChartInput(portable).calculate(),data)
  }

  @MainActor func testOnlyExactCapabilityPublishesNumericChartAndOldServicesRemainUsable() async throws {
    let saved = result(), caps = RemoteServiceCapabilities(apiVersion:"v1",service:"typebar",capabilities:["resultPerformanceChart":"available"])
    let submission = try await ResultConsistencyPublication.prepare(result:saved,capabilities:caps)
    XCTAssertNotNil(submission.performanceChart)
    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(submission)) as? [String:Any])
    for forbidden in ["prompt","replayEvents","inputField","text","textUTF16","accessToken"] { XCTAssertNil(wire[forbidden]) }
    let encoded = String(decoding:try JSONEncoder().encode(try XCTUnwrap(submission.performanceChart)),as:UTF8.self)
    XCTAssertFalse(encoded.contains(saved.prompt)); XCTAssertFalse(encoded.contains("inputField"))
    for capabilities in [nil,RemoteServiceCapabilities(apiVersion:"v2",service:"typebar",capabilities:["resultPerformanceChart":"available"]),
      .init(apiVersion:"v1",service:"other",capabilities:["resultPerformanceChart":"available"]),
      .init(apiVersion:"v1",service:"typebar",capabilities:["resultPerformanceChart":"partial"])] {
      let legacy = try await ResultConsistencyPublication.prepare(result:saved,capabilities:capabilities)
      XCTAssertNil(legacy.performanceChart)
      XCTAssertNil((try JSONSerialization.jsonObject(with:JSONEncoder().encode(legacy)) as? [String:Any])?["performanceChart"])
    }
  }

  func testSelectionAndIndependentAxesPreserveFiveUnitsAndZeroPreference() {
    let data = chart()
    XCTAssertEqual(data.nearest(to:1.5)?.elapsed,1); XCTAssertEqual(data.nearest(to:-1)?.elapsed,1)
    XCTAssertEqual(data.nearest(to:999)?.elapsed,15); XCTAssertNil(data.nearest(to:.nan))
    for unit in TypingSpeedUnit.allCases { for zero in [false,true] {
      let scale = AccountResultChartScale(data:data,unit:unit,startsAtZero:zero)
      XCTAssertEqual(scale.speed(at:scale.speedPosition(60.25)),unit.converted(wpm:60.25),accuracy:1e-9)
      XCTAssertEqual(scale.errors(at:scale.errorPosition(2)),2,accuracy:1e-9)
      XCTAssertGreaterThan(scale.speedUpper,scale.speedLower); XCTAssertGreaterThan(scale.errorUpper,scale.errorLower)
      XCTAssertFalse(scale.errorTickPositions.isEmpty)
      for tick in scale.errorTickPositions { XCTAssertEqual(scale.errors(at:tick),scale.errors(at:tick).rounded(),accuracy:1e-9) }
      if zero { XCTAssertEqual(scale.speedLower,0); XCTAssertEqual(scale.errorLower,0) }
    } }
  }

  @MainActor func testReadRejectsDifferentResultRefreshDeletionAndAccountABARoundTrip() throws {
    let suite = "TypebarTests.chart-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName:suite))
    defer { defaults.removePersistentDomain(forName:suite) }
    let account = AccountSession(defaults:defaults)
    let user = RemoteAccountUser(id:UUID(),email:"chart@example.invalid",displayName:"Owner",totalExperience:0)
    account.currentUser = user
    let scope = try XCTUnwrap(account.resultPublicationScope), detail = try row(chart:chart(),available:true)
    account.remoteResults = [detail]
    let read = try account.beginAccountResultChartRead(id:detail.id,scope:scope)
    XCTAssertEqual(try account.acceptAccountResultChart(detail,read:read),chart())
    XCTAssertThrowsError(try account.acceptAccountResultChart(row(chart:chart(),available:true),read:read))
    _ = try account.beginAccountTagHistoryRead()
    XCTAssertThrowsError(try account.acceptAccountResultChart(detail,read:read))
    let next = try account.beginAccountResultChartRead(id:detail.id,scope:scope)
    account.remoteResults = []
    XCTAssertThrowsError(try account.acceptAccountResultChart(detail,read:next))
    account.remoteResults = [detail]
    account.currentUser = nil; account.currentUser = user; account.remoteResults = [detail]
    XCTAssertThrowsError(try account.acceptAccountResultChart(detail,read:next))
    XCTAssertTrue(account.updateEndpoint("https://another.invalid"))
    XCTAssertThrowsError(try account.acceptAccountResultChart(detail,read:next))
  }

  @MainActor func testLoaderCannotReplaceNewerReadWithOlderCompletionAndKeepsRetryState() async {
    let loader = AccountResultChartLoader(), expected = chart()
    var continuation: CheckedContinuation<AccountResultChartData?,Never>?
    let first = Task { await loader.load { await withCheckedContinuation { continuation = $0 } } }
    while continuation == nil { await Task.yield() }
    await loader.load { expected }
    continuation?.resume(returning:nil); await first.value
    XCTAssertEqual(loader.state,.ready(expected))
    await loader.load { throw RemoteAccountError.unexpectedResponse }
    if case .failed = loader.state {} else { XCTFail("A read failure must expose retry, not synthetic data") }
    await loader.load { nil }; XCTAssertEqual(loader.state,.unavailable)
    let canceled = Task { await loader.load { expected } }; canceled.cancel(); await canceled.value
    XCTAssertEqual(loader.state,.loading,"Cancellation must never publish its completed value")
  }

  func testPinnedSourceDatasetsUnitsPositiveErrorsAndTimeLabels() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference for QA-only source configuration execution")
    }
    struct Fixture: Decodable {
      let unit:String; let zero:Bool; let wpm:[Double]; let burst:[Double]; let errors:[Int]
      let labels:[String]; let speeds:[Double]; let bursts:[Double]; let radii:[Int]
    }
    let project = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath:"/usr/bin/env")
    process.arguments = ["node",project.appendingPathComponent("Scripts/check-source-account-result-chart.mjs").path,reference,"--emit-fixtures"]
    process.standardOutput = output; try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus,0)
    let fixtures = try JSONDecoder().decode([Fixture].self,from:bytes)
    XCTAssertEqual(fixtures.count,40)
    for fixture in fixtures {
      let unit = try XCTUnwrap(TypingSpeedUnit(rawValue:fixture.unit))
      XCTAssertEqual(fixture.labels,fixture.wpm.indices.map { String($0+1) })
      let data = AccountResultChartData(samples:fixture.wpm.indices.map {
        .init(elapsed:Double($0+1),wpm:fixture.wpm[$0],burst:fixture.burst[$0],errors:fixture.errors[$0])
      })
      XCTAssertEqual(data.isValid,!data.samples.isEmpty)
      let scale = AccountResultChartScale(data:data,unit:unit,startsAtZero:fixture.zero)
      for index in fixture.wpm.indices {
        XCTAssertEqual(unit.converted(wpm:fixture.wpm[index]),fixture.speeds[index],accuracy:1e-9)
        XCTAssertEqual(unit.converted(wpm:fixture.burst[index]),fixture.bursts[index],accuracy:1e-9)
        XCTAssertEqual(fixture.errors[index]>0,fixture.radii[index]>0)
        XCTAssertEqual(scale.errors(at:scale.errorPosition(fixture.errors[index])),Double(fixture.errors[index]),accuracy:1e-9)
      }
    }
  }
}
