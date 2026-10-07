import Foundation
import XCTest
import XCTVapor
@testable import TypebarServerCore

final class ResultPerformanceChartTests: XCTestCase {
  private let now = Date(timeIntervalSince1970:1_800_000_000)
  private func chartObject(speed: Double = 60) -> [String:Any] {
    ["version":1, "samples":(1...15).map { ["elapsed":Double($0),"wpm":speed,"burst":12.0,"errors":0] }]
  }
  private func request(_ chart: Any? = nil, id: UUID = UUID(), at date: Date? = nil) throws -> ResultSubmissionRequest {
    let date = date ?? now
    let base = ResultSubmissionRequest(id:id,mode:"time",language:"english",durationSeconds:15,wordLimit:nil,
      wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,startedAt:date.addingTimeInterval(-15),finishedAt:date)
    var object = try json(base); object["performanceChart"] = chart
    return try JSONDecoder().decode(ResultSubmissionRequest.self,from:JSONSerialization.data(withJSONObject:object))
  }
  private func json<T:Encodable>(_ value:T) throws -> [String:Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as? [String:Any])
  }
  func testAcceptedChartSurvivesPrivateSingleRead() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"chart@example.invalid",password:"a secure password",displayName:"Owner"),now:now)
    let input = try request(chartObject())
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let value = try await store.result(id:input.id,credential:.accessToken(owner.accessToken),now:now)
    XCTAssertNotNil(try json(value)["performanceChart"])
  }

  func testListIsCompactAndPrivateReadIsOwnerScoped() async throws {
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"owner@example.invalid",password:"a secure password",displayName:"Owner"),now:now)
    let other = try await store.register(.init(email:"other@example.invalid",password:"a secure password",displayName:"Other"),now:now)
    let input = try request(chartObject())
    _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let page = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    let row = try json(XCTUnwrap(page.results.first))
    XCTAssertEqual(row["hasPerformanceChart"] as? Bool,true); XCTAssertNil(row["performanceChart"])
    do { _ = try await store.result(id:input.id,credential:.accessToken(other.accessToken),now:now); XCTFail("Foreign result leaked") }
    catch let error as AuthStoreError { XCTAssertEqual(error,.resultNotFound) }
    _ = try await store.submitResult(request(chartObject(speed:99),id:input.id),accessToken:other.accessToken,now:now)
    let otherDetail = try await store.result(id:input.id,credential:.accessToken(other.accessToken),now:now)
    XCTAssertEqual(otherDetail.performanceChart?.samples.first?.wpm,99)
    let detail = try json(await store.result(id:input.id,credential:.accessToken(owner.accessToken),now:now))
    for key in ["prompt","replayEvents","inputField","text","accessToken"] { XCTAssertNil(detail[key]) }
    let publicProfile = try json(await store.publicProfile(id:owner.user.id,now:now))
    XCTAssertFalse(String(decoding:try JSONSerialization.data(withJSONObject:publicProfile),as:UTF8.self).contains("performanceChart"))
  }

  func testFirstAcceptedTraceWinsRetryAndColdReloadWithoutBackfillingLegacy() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-chart-cold-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"cold@example.invalid",password:"a secure password",displayName:"Owner"),now:now)
    let input = try request(chartObject()), old = try request()
    let first = try await store.submitResult(input,accessToken:owner.accessToken,now:now)
    let duplicate = try await store.submitResult(request(chartObject(speed:99),id:input.id),accessToken:owner.accessToken,now:now)
    XCTAssertEqual(first,duplicate)
    _ = try await store.submitResult(old,accessToken:owner.accessToken,now:now)
    _ = try await store.submitResult(request(chartObject(),id:old.id),accessToken:owner.accessToken,now:now)
    let bytes = try Data(contentsOf:file), loaded = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let detail = try await loaded.result(id:input.id,credential:.accessToken(owner.accessToken),now:now)
    XCTAssertEqual(detail.performanceChart?.samples.first?.wpm,60)
    let legacy = try await loaded.result(id:old.id,credential:.accessToken(owner.accessToken),now:now)
    XCTAssertNil(legacy.performanceChart); XCTAssertEqual(legacy.hasPerformanceChart,false)
    XCTAssertEqual(try Data(contentsOf:file),bytes,"Opening and reading must not rewrite or invent old charts")
  }

  func testMalformedPresentDataAndWrongDurationAreRejectedWithoutNewResults() async throws {
    let sample = ResultPerformanceChart.Sample(elapsed:1,wpm:0,burst:0,errors:0)
    for chart in [ResultPerformanceChart(version:2,samples:[sample]),.init(samples:[sample,sample]),
      .init(samples:(1...123).map { .init(elapsed:Double($0),wpm:0,burst:0,errors:0) }),
      .init(samples:[.init(elapsed:1,wpm:-1,burst:0,errors:0)]),
      .init(samples:[.init(elapsed:1,wpm:0,burst:1_000_000_001,errors:0)]),
      .init(samples:[.init(elapsed:1,wpm:0,burst:0,errors:1_800_001)])] {
      XCTAssertFalse(chart.isValid); XCTAssertThrowsError(try JSONEncoder().encode(chart))
    }
    for value: Any in [NSNull(),"toolong",["version":2,"samples":[]],
      ["version":1,"samples":[["elapsed":0,"wpm":0,"burst":0,"errors":0]]]] {
      XCTAssertThrowsError(try request(value))
    }
    let store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"invalid@example.invalid",password:"a secure password",displayName:"Owner"),now:now)
    let values = [ResultPerformanceChart(samples:[.init(elapsed:16,wpm:0,burst:0,errors:0)]),
      .init(samples:[]),.init(samples:[.init(elapsed:1,wpm:.infinity,burst:0,errors:0)])]
    for chart in values {
      let input = ResultSubmissionRequest(id:UUID(),mode:"time",language:"english",durationSeconds:15,wordLimit:nil,
        wpm:60,rawWpm:60,accuracy:100,errorCount:0,eventCount:75,performanceChart:chart,
        startedAt:now.addingTimeInterval(-15),finishedAt:now)
      do { _ = try await store.submitResult(input,accessToken:owner.accessToken,now:now); XCTFail("Invalid chart accepted") }
      catch let error as ResultStoreError { XCTAssertEqual(error,.invalidResult) }
    }
    let page = try await store.results(.init(),credential:.accessToken(owner.accessToken),now:now)
    XCTAssertEqual(page.total,0)
    let boundary = ResultPerformanceChart(samples:[.init(elapsed:122,wpm:0,burst:0,errors:0)])
    XCTAssertTrue(boundary.matches(duration:122)); XCTAssertFalse(boundary.matches(duration:122.001))
  }

  func testColdReadRejectsPresentCorruptionWithoutRewritingDisk() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-chart-corrupt-\(UUID())")
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    defer { try? FileManager.default.removeItem(at:directory) }
    let file = directory.appendingPathComponent("store.json"), store = try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"corrupt@example.invalid",password:"a secure password",displayName:"Owner"),now:now)
    _ = try await store.submitResult(request(chartObject()),accessToken:owner.accessToken,now:now)
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
    for invalid: Any in [NSNull(),"toolong",["version":99,"samples":[]],
      ["version":1,"samples":[["elapsed":16,"wpm":0,"burst":0,"errors":0]]]] {
      var object = original, rows = try XCTUnwrap(object["results"] as? [[String:Any]])
      rows[0]["performanceChart"] = invalid; object["results"] = rows
      let bytes = try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
      try bytes.write(to:file,options:.atomic)
      XCTAssertThrowsError(try AuthStore(fileURL:file,bcryptCost:4,rankingEnvironment:.development))
      XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
  }

  func testHTTPNegotiatesAndLazilyReadsOnlyOwnersNumericChart() async throws {
    let live = Date.now, store = try AuthStore(fileURL:nil,bcryptCost:4,rankingEnvironment:.development)
    let owner = try await store.register(.init(email:"httpchart@example.invalid",password:"a secure password",displayName:"Owner"),now:live)
    let other = try await store.register(.init(email:"httpother@example.invalid",password:"a secure password",displayName:"Other"),now:live)
    let input = try request(chartObject(),at:live), app = try await Application.make(.testing)
    do {
      try configure(app,authStore:store)
      try await app.test(.GET,"v1/capabilities") { response async throws in
        XCTAssertEqual(try response.content.decode(ServiceCapabilitiesResponse.self).capabilities["resultPerformanceChart"],.available)
      }
      try await app.test(.POST,"v1/results",beforeRequest:{ request async throws in
        request.headers.bearerAuthorization = .init(token:owner.accessToken); try request.content.encode(input)
      },afterResponse:{ response async in XCTAssertEqual(response.status,.ok) })
      try await app.test(.GET,"v1/results/\(input.id)") { response async in XCTAssertEqual(response.status,.unauthorized) }
      for (token,status) in [(owner.accessToken,HTTPResponseStatus.ok),(other.accessToken,.notFound)] {
        try await app.test(.GET,"v1/results/\(input.id)",beforeRequest:{ request async in
          request.headers.bearerAuthorization = .init(token:token)
        },afterResponse:{ response async throws in
          XCTAssertEqual(response.status,status)
          if status == .ok { XCTAssertEqual(try response.content.decode(AccountResultResponse.self).performanceChart?.samples.count,15) }
        })
      }
      try await app.test(.GET,"v1/results",beforeRequest:{ request async in
        request.headers.bearerAuthorization = .init(token:owner.accessToken)
      },afterResponse:{ response async throws in
        let first = try XCTUnwrap(response.content.decode(ResultListResponse.self).results.first)
        XCTAssertEqual(first.hasPerformanceChart,true); XCTAssertNil(first.performanceChart)
      })
      try await app.asyncShutdown()
    } catch { try? await app.asyncShutdown(); throw error }
  }
}
