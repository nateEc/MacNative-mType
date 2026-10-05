import Foundation
import XCTest
@testable import Typebar

final class RankingEvidencePublicationTests: XCTestCase {
  private func result(stop: StopOnErrorMode = .off, modifiers: [TestModifier] = [],
    language: TypingLanguage = .english, configuration override: TestConfiguration? = nil) -> CompletedTestResult {
    let start = Date(timeIntervalSinceReferenceDate: 900_000_000)
    return .init(id: UUID(), configuration: override ?? .words(25, rules: .init(stopOnErrorMode: stop),
      language: language).with(modifiers: modifiers), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(15), typedCharacterCount: 75,
      correctCharacterCount: 75, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      prompt: "private prompt", replayEvents: [])
  }
  private var capabilities: RemoteServiceCapabilities {
    .init(apiVersion: "v1", service: "typebar", capabilities: ["resultRankingEvidence":"available"])
  }
  func testWordStopDoesNotRejectAnImperfectPersonalBest() {
    let configuration = TestConfiguration.words(25, rules: .init(stopOnErrorMode: .word))
    XCTAssertTrue(CurrentPersonalBestPolicy.isResultEligible(configuration: configuration, accuracy: 98.5))
    var letter = configuration; letter.rules.stopOnErrorMode = .letter; letter.rules.stopOnError = true
    XCTAssertFalse(CurrentPersonalBestPolicy.isResultEligible(configuration: letter, accuracy: 98.5))
  }
  @MainActor func testLegacyBooleanOnlyMemorySnapshotUsesLetterStopInPBAndPublication() async throws {
    var legacy = TestConfiguration.words(25)
    legacy.rules.stopOnError = true
    XCTAssertEqual(legacy.rules.stopOnErrorMode,.off)
    XCTAssertFalse(CurrentPersonalBestPolicy.isResultEligible(configuration:legacy,accuracy:99.99))
    let saved = result(configuration:legacy)
    let wire = try await ResultConsistencyPublication.prepare(result:saved,capabilities:capabilities)
    XCTAssertEqual(wire.rankingEvidence?.stopOnLetter,true)
    do {
      _ = try await ResultConsistencyPublication.prepare(result:saved,capabilities:nil)
      XCTFail("Legacy Boolean-only controls must not silently disappear on an older service")
    } catch { XCTAssertTrue(error is RemoteAccountError) }
  }
  @MainActor func testNegotiatedControlProjectionUsesLetterNotWordAndOmitsPrivateData() async throws {
    for stop in [StopOnErrorMode.off, .letter, .word] {
      let saved = result(stop: stop, modifiers: [.mirrorVisual, .lazyLatin])
      let wire = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capabilities)
      XCTAssertEqual(wire.rankingEvidence, .init(stopOnLetter: stop == .letter, modifiers: ["mirrorVisual"]))
      let bytes = try JSONEncoder().encode(wire)
      let history = try JSONDecoder().decode(RemoteAccountResult.self, from: bytes)
      XCTAssertEqual(history.rankingEvidence, wire.rankingEvidence)
      for forbidden in ["private prompt", "replayEvents", "accountExcluded", "speedEligible", "previousTypingSeconds"] {
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains(forbidden))
      }
    }
    let mixed = try await ResultConsistencyPublication.prepare(result: result(language: .mixedLanguages), capabilities: capabilities)
    XCTAssertEqual(mixed.rankingEvidence?.modifiers, ["polyglot"])
  }
  @MainActor func testUnsupportedServiceNeverSilentlyDropsUnsafeControls() async throws {
    for capability in [nil, RemoteServiceCapabilities(apiVersion:"v2",service:"typebar",capabilities:["resultRankingEvidence":"available"]),
      .init(apiVersion:"v1",service:"other",capabilities:["resultRankingEvidence":"available"]),
      .init(apiVersion:"v1",service:"typebar",capabilities:["resultRankingEvidence":"partial"])] {
      for saved in [result(stop: .letter), result(modifiers: [.uppercase]), result(language: .mixedLanguages)] {
        do {
          _ = try await ResultConsistencyPublication.prepare(result: saved, capabilities: capability) { _ in
            XCTFail("Controls must fail before metric work"); return 0
          }
          XCTFail("Unsupported controls must retain local record")
        } catch { XCTAssertTrue(error is RemoteAccountError) }
      }
      let safe = try await ResultConsistencyPublication.prepare(result: result(stop: .word), capabilities: capability)
      XCTAssertNil(safe.rankingEvidence)
    }
  }
  @MainActor func testPortableArchiveRoundTripKeepsControlProjectionWithoutSchemaChange() async throws {
    let saved = result(stop: .letter, modifiers: [.uppercase])
    let record = try XCTUnwrap(TestResultRecord(result: saved).portableResult)
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [saved], presets: [], at: saved.finishedAt))
    XCTAssertEqual(archive.version, TypebarArchive.currentVersion)
    for restored in [record,try XCTUnwrap(archive.results.first)] {
      let wire = try await ResultConsistencyPublication.prepare(result: restored, capabilities: capabilities)
      XCTAssertEqual(wire.rankingEvidence, .init(stopOnLetter: true, modifiers: ["uppercase"]))
    }
  }
  @MainActor func testHistoryRejectsExplicitBadReportButAcceptsAbsentLegacyReport() async throws {
    let wire = try await ResultConsistencyPublication.prepare(result: result(), capabilities: capabilities)
    let base = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wire)) as? [String:Any])
    for report: Any in [NSNull(), ["version":2,"stopOnLetter":false,"modifiers":[]] as [String:Any],
      ["version":1,"stopOnLetter":false,"modifiers":["unknown"]],
      ["version":1,"stopOnLetter":false,"modifiers":["crtVisual","crtVisual"]],
      ["version":1,"stopOnLetter":false,"modifiers":["polyglot"]]] {
      var json = base; json["rankingEvidence"] = report
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:json)))
    }
    var legacy = base; legacy.removeValue(forKey:"rankingEvidence")
    XCTAssertNil(try JSONDecoder().decode(RemoteAccountResult.self,from:JSONSerialization.data(withJSONObject:legacy)).rankingEvidence)
    var disagreement = base
    disagreement["experienceEvidence"] = ["version":1,"characterCounts":[75,0,0,0],"scoringUnitBasis":"utf16",
      "durationSeconds":15,"afkSeconds":0,"punctuation":false,"numbers":false,"modifiers":["mirrorVisual"]] as [String:Any]
    disagreement["practiceTiming"] = ["version":1,"terminalEngagedMilliseconds":15_000,"priorAttemptEngagedMilliseconds":0]
    XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountResult.self,
      from:JSONSerialization.data(withJSONObject:disagreement)), "Separate reports cannot disagree on modifier identity")
  }

  func testEveryNativeFunboxPBFlagAgainstActualSourceCatalog() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness provides pinned source for actual Funbox PB comparison")
    }
    let script = URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Scripts/check-source-ranking-admission.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    let node = ProcessInfo.processInfo.environment["TYPEBAR_RANKING_SOURCE_NODE"]
    process.executableURL = URL(fileURLWithPath:node ?? "/usr/bin/env")
    process.arguments = (node == nil ? ["node"] : []) + ["--experimental-vm-modules",script.path,reference,"--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus,0,String(decoding:errorData,as:UTF8.self))
    struct Flag: Decodable { let name: String; let allowsPersonalBest: Bool }
    struct Document: Decodable { let referenceCommit: String; let catalog: [Flag] }
    let document = try JSONDecoder().decode(Document.self,from:data)
    XCTAssertEqual(document.referenceCommit,"91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.catalog.count,48)
    for flag in document.catalog {
      let target = try XCTUnwrap(FunboxCommandCatalog.target(for:"funbox.changeFunbox\(flag.name)"))
      let configuration: TestConfiguration
      switch target {
      case .modifier(let modifier): configuration = .words(25).with(modifiers:[modifier])
      case .polyglot: configuration = .words(25,language:.mixedLanguages)
      case .clear: XCTFail("No source funbox is clear"); continue
      }
      XCTAssertEqual(CurrentPersonalBestPolicy.isResultEligible(configuration:configuration,accuracy:100),
        flag.allowsPersonalBest,flag.name)
    }
  }
}
