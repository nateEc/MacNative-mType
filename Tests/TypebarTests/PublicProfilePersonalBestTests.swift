import Foundation
import CryptoKit
import XCTest
@testable import Typebar

final class PublicProfilePersonalBestTests: XCTestCase {
  private func best(_ mode: String = "time", parameter: Int = 15, speed: Double = 60.49,
    language: String = "english", id: UUID = UUID()) -> [String: Any] {
    var row: [String: Any] = ["id": id.uuidString, "mode": mode,
      "mode2": ["time", "words"].contains(mode) ? String(parameter) : mode,
      "language": language, "wpm": Int(speed.rounded()), "preciseWpm": speed,
      "rawWpm": 120, "preciseRawWpm": 120.0, "accuracy": 99, "preciseAccuracy": 98.75,
      "consistency": 80.25, "finishedAt": 100,
      "acceptedAtMilliseconds": 1_800_000_000_875, "personalBestOrigin": "accepted",
      "personalBestConfiguration": ["version": 1, "difficulty": "expert",
        "punctuation": true, "numbers": false, "lazyMode": true]]
    if mode == "time" { row["durationSeconds"] = parameter }
    if mode == "words" { row["wordLimit"] = parameter }
    return row
  }
  private func payload(_ rows: [[String: Any]]) -> [String: Any] {
    ["id": UUID().uuidString, "displayName": "Owned profile", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0, "personalBests": [],
      "personalBestLedgerVersion": 1, "personalBestHistoryComplete": true,
      "personalBestSnapshots": rows]
  }
  private func decode(_ root: [String: Any]) throws -> RemotePublicProfile {
    try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: root))
  }

  func testActualProfileProjectionKeepsEightOrderedSlotsIncludingMissingAndZeroSpeed() throws {
    let zero = best(speed: 0)
    let input = [best("zen"), best(parameter: 45), zero, best("words", parameter: 25, speed: 70)]
    let profile = try decode(payload(input)), cards = PublicProfilePersonalBestPolicy.cards(profile)
    XCTAssertEqual(cards.map(\.id), ["time/15", "time/30", "time/60", "time/120",
      "words/10", "words/25", "words/50", "words/100"])
    XCTAssertEqual(cards.map(\.parameter), [15, 30, 60, 120, 10, 25, 50, 100])
    XCTAssertEqual(cards.filter { $0.best != nil }.map(\.id), ["words/25"])
    XCTAssertEqual(profile.displayPersonalBests.count, 4, "Full disclosure must retain nonstandard and zero records")
  }

  func testEachSlotSelectsPreciseMaximumWithFirstTieAndUnchangedCompanions() throws {
    let slow = best(speed: 60.48), winner = best(speed: 60.49, language: "french")
    var tied = best(speed: 60.49, language: "german"); tied["preciseAccuracy"] = 98.99
    let profile = try decode(payload([slow, winner, tied]))
    let cards = PublicProfilePersonalBestPolicy.cards(profile), selected = try XCTUnwrap(cards.first?.best)
    XCTAssertEqual(selected.id.uuidString, winner["id"] as? String)
    XCTAssertEqual(selected.preciseWpm, 60.49); XCTAssertEqual(selected.preciseRawWpm, 120)
    XCTAssertEqual(selected.preciseAccuracy, 98.75); XCTAssertEqual(selected.consistency, 80.25)
    XCTAssertEqual(selected.language, "french"); XCTAssertEqual(selected.personalBestConfiguration?.lazyMode, true)
    XCTAssertEqual(selected.recordedAt.timeIntervalSince1970, 1_800_000_000.875)
    XCTAssertEqual(profile.displayPersonalBests.map(\.id.uuidString), [slow, winner, tied].map { $0["id"] as! String })
  }

  func testKnownEmptyLedgerDoesNotResurrectOldSummaryAndLegacyStillUsesKnownValues() throws {
    var root = payload([]); root["personalBests"] = [best()]
    let empty = try decode(root)
    XCTAssertEqual(PublicProfilePersonalBestPolicy.cards(empty).count, 8)
    XCTAssertTrue(PublicProfilePersonalBestPolicy.cards(empty).allSatisfy { $0.best == nil })
    XCTAssertTrue(PublicProfilePersonalBestPolicy.records(empty).isEmpty)
    for key in ["personalBestLedgerVersion", "personalBestHistoryComplete", "personalBestSnapshots"] { root.removeValue(forKey: key) }
    let old = try decode(root)
    XCTAssertEqual(PublicProfilePersonalBestPolicy.cards(old).first?.best?.effectiveWpm, 60.49)
  }

  func testLegacyUnknownAndNoncanonicalParametersNeverBecomeStandardSlots() throws {
    var explicit = best(), unknown = best(language: "french"), noncanonical = best(language: "german")
    explicit.removeValue(forKey: "mode2"); explicit.removeValue(forKey: "rawWpm")
    explicit.removeValue(forKey: "preciseRawWpm"); explicit.removeValue(forKey: "personalBestConfiguration")
    unknown.removeValue(forKey: "mode2"); unknown.removeValue(forKey: "durationSeconds")
    noncanonical["mode2"] = "015"
    let root: [String: Any] = ["id": UUID().uuidString, "displayName": "Old", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0, "personalBests": [unknown, noncanonical, explicit]]
    let profile = try decode(root), selected = try XCTUnwrap(PublicProfilePersonalBestPolicy.cards(profile).first?.best)
    XCTAssertEqual(selected.id.uuidString, explicit["id"] as? String)
    XCTAssertNil(selected.rawWpm); XCTAssertNil(selected.preciseRawWpm)
    XCTAssertEqual(selected.groupingLabel, "选项未知")
    XCTAssertEqual(PublicProfilePersonalBestPolicy.records(profile).count, 3)
  }

  func testFullDisclosureRetainsNonstandardZeroUnknownAndDuplicateLegacyResultIDs() throws {
    let duplicate = UUID()
    var unknown = best(); unknown.removeValue(forKey: "mode2"); unknown.removeValue(forKey: "durationSeconds")
    let input = [best("custom"), best("zen"), best(parameter: 45), best(speed: 0), unknown,
      best(id: duplicate), best(language: "french", id: duplicate)]
    let root: [String: Any] = ["id": UUID().uuidString, "displayName": "Old", "joinedAt": 0,
      "completedResultCount": 0, "bestWPM": 0, "personalBests": input]
    let profile = try decode(root), records = PublicProfilePersonalBestPolicy.records(profile)
    XCTAssertEqual(records.map(\.id), Array(input.indices))
    XCTAssertEqual(records.map(\.best.id.uuidString), input.map { $0["id"] as! String })
    XCTAssertEqual(Set(records.map(\.id)).count, input.count)
    XCTAssertEqual(records[3].best.effectiveWpm, 0); XCTAssertEqual(records[4].best.configurationLabel, "时间未知")
  }

  func testPositiveFractionalSpeedIsNotRoundedAwayBeforeSelectingARecord() throws {
    let profile = try decode(payload([best(speed: 0.01)]))
    let selected = try XCTUnwrap(PublicProfilePersonalBestPolicy.cards(profile).first?.best)
    XCTAssertEqual(selected.wpm, 0); XCTAssertEqual(selected.effectiveWpm, 0.01)
  }

  func testMissingValuesStayMissingAndAccuracyFloorsOnlyWhenDecimalsAreOff() {
    XCTAssertEqual(PublicProfilePersonalBestPresentation.speed(nil, unit: .cpm, decimals: true), "—")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.speed(0, unit: .cpm, decimals: true), "0.00")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(nil, decimals: true), "—")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(98.75, decimals: false, accuracy: true), "98%")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(98.75, decimals: false), "99%")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(98.75, decimals: true, accuracy: true), "98.75%")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(100, decimals: true, accuracy: true), "100.00%")
  }

  func testSharedDisplayConversionUsesPinnedFactorBeforeRoundingDecimalMidpoints() {
    XCTAssertEqual(TypingSpeedUnit.cps.converted(wpm: 24.18), 24.18 * (5.0 / 60.0))
    XCTAssertEqual(AccountHistoryNumberPresentation.text(24.18, unit: .cps, decimals: true), "2.01")
    XCTAssertEqual(PublicProfilePersonalBestPresentation.speed(24.18, unit: .cps, decimals: true), "2.01")
  }

  func testPinnedCompleteSummaryMemoAndFormattingAgainstOwnedProfiles() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else { throw XCTSkip("Readiness supplies pinned reference") }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-profile-pb-summary.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = .init(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors; try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile(), diagnostics = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0, String(decoding: diagnostics, as: UTF8.self))
    struct Fixture: Decodable {
      struct Expected: Decodable { let id: String; let bestID: UUID? }
      let profile: RemotePublicProfile; let expected: [Expected]
    }
    struct Format: Decodable {
      let unit: TypingSpeedUnit; let decimals: Bool; let value: Double?
      let speed: String; let percentage: String; let accuracy: String
    }
    struct Sweep: Decodable { let unit: TypingSpeedUnit; let maximumHundredths: Int; let expectedDigest: String }
    struct Document: Decodable {
      let referenceCommit: String; let fixtures: [Fixture]; let formats: [Format]; let sweeps: [Sweep]
    }
    let document = try JSONDecoder().decode(Document.self, from: data)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.fixtures.count, 16); XCTAssertEqual(document.formats.count, 100)
    XCTAssertEqual(document.sweeps.map(\.unit), TypingSpeedUnit.allCases)
    for fixture in document.fixtures {
      let cards = PublicProfilePersonalBestPolicy.cards(fixture.profile)
      XCTAssertEqual(cards.map(\.id), fixture.expected.map(\.id))
      XCTAssertEqual(cards.map { $0.best?.id }, fixture.expected.map(\.bestID))
    }
    for format in document.formats {
      XCTAssertEqual(PublicProfilePersonalBestPresentation.speed(format.value, unit: format.unit, decimals: format.decimals), format.speed)
      XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(format.value, decimals: format.decimals), format.percentage)
      XCTAssertEqual(PublicProfilePersonalBestPresentation.percentage(format.value, decimals: format.decimals, accuracy: true), format.accuracy)
    }
    for sweep in document.sweeps {
      XCTAssertEqual(sweep.maximumHundredths, 42000)
      var bytes = Data()
      for i in 0...sweep.maximumHundredths {
        let value = Double(i) / 100
        let integer = PublicProfilePersonalBestPresentation.speed(value, unit: sweep.unit, decimals: false)
        let decimal = PublicProfilePersonalBestPresentation.speed(value, unit: sweep.unit, decimals: true)
        bytes.append(contentsOf: "\(i)|\(integer)|\(decimal)\n".utf8)
      }
      let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(digest, sweep.expectedDigest, "\(sweep.unit) entire canonical range")
    }
  }
}
