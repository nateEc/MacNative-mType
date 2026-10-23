import XCTest
import SwiftData
@testable import Typebar

final class ChallengePaceModeTests: XCTestCase {
  private func presentation(mode: String?, style: TypingCaretStyle) throws -> ChallengePresentationSnapshot {
    var payload: [String: Any] = ["liveSpeedStyle": "off", "paceCaretStyle": style.rawValue, "tapeMode": "off"]
    if let mode { payload["paceGuideMode"] = mode }
    return try JSONDecoder().decode(ChallengePresentationSnapshot.self,
      from: JSONSerialization.data(withJSONObject: payload))
  }

  private func result(mode: String?, style: TypingCaretStyle) throws -> CompletedTestResult {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "steady-sixty"))
    let start = Date(timeIntervalSince1970: 100)
    return CompletedTestResult(id: UUID(),
      configuration: challenge.preset.configuration.with(challengeID: challenge.id), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(300), typedCharacterCount: 1_500,
      correctCharacterCount: 1_500, errorCount: 0, wpm: 60, rawWpm: 60, accuracy: 100,
      challengePresentation: try presentation(mode: mode, style: style))
  }

  private func evaluation(mode: String?, style: TypingCaretStyle) throws -> ChallengeEvaluation {
    ChallengeEvaluator.evaluate(try result(mode: mode, style: style),
      challenge: try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "steady-sixty")))
  }

  func testDisabledPaceModePassesRegardlessOfUnusedMarkerStyle() throws {
    XCTAssertTrue(try evaluation(mode: "off", style: .bar).passed)
  }

  func testEnabledPaceModeCannotPassByHidingItsMarkerStyle() throws {
    XCTAssertFalse(try evaluation(mode: "custom", style: .off).passed)
  }

  func testOlderStyleOnlyEvidenceDoesNotInventAnUnrecordedPaceMode() throws {
    XCTAssertFalse(try evaluation(mode: nil, style: .off).passed)
  }

  func testConfiguredModeIsRequiredEvenWhenNoTargetOrVisibleMarkerExists() throws {
    for mode in ["personalBest", "average", "lastTest"] {
      XCTAssertFalse(try evaluation(mode: mode, style: .off).passed, mode)
    }
    XCTAssertThrowsError(try presentation(mode: "unknown-mode", style: .off))
  }

  func testNativeStyleConditionRemainsIndependentOfConfiguredMode() throws {
    let original = try result(mode: "custom", style: .off)
    let native = TypebarChallenge(id: "native-style", title: "Native style", description: "Owned style condition",
      preset: .init(configuration: original.configuration),
      requirements: .init(configuration: .init(paceCaretStyle: .off)))
    XCTAssertTrue(ChallengeEvaluator.evaluate(original, challenge: native).passed)
  }

  @MainActor
  func testModeEvidenceSurvivesSavedRecordFreshContextAndOfficialNativeArchive() throws {
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    container.mainContext.autosaveEnabled = false
    let completed = try result(mode: "off", style: .bar)
    container.mainContext.insert(TestResultRecord(result: completed))
    try container.mainContext.save()
    let reader = ModelContext(container)
    let restored = try XCTUnwrap(reader.fetch(FetchDescriptor<TestResultRecord>()).first?.portableResult)
    XCTAssertEqual(restored.challengePresentation?.paceGuideMode, .off)
    XCTAssertEqual(restored.challengePresentation?.paceCaretStyle, .bar)
    let archive = TypebarArchive(exportedAt: Date(timeIntervalSince1970: 500), settings: .init(),
      results: [restored], presets: [], savedTexts: [])
    let decoded = try TypebarDataTransfer.importArchive(from: TypebarArchiveDocument(archive: archive).archiveData())
    XCTAssertEqual(decoded.results.first?.challengePresentation?.paceGuideMode, .off)
    XCTAssertEqual(decoded.results.first?.challengePresentation?.paceCaretStyle, .bar)
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "steady-sixty"))
    XCTAssertTrue(ChallengeEvaluator.evaluate(try XCTUnwrap(decoded.results.first), challenge: challenge).passed)
  }

  func testMainRecordsModeSeparatelyFromStyleAndReferenceConditionUsesMode() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(source.contains("paceGuideMode: settings.paceGuideMode)"))
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "steady-sixty"))
    XCTAssertEqual(challenge.requirements.configuration?.paceGuideMode, .off)
    XCTAssertNil(challenge.requirements.configuration?.paceCaretStyle)
  }
}
