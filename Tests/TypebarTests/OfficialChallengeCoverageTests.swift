import Foundation
import XCTest

@testable import Typebar

final class OfficialChallengeCoverageTests: XCTestCase {
  private struct Fixture: Decodable {
    let referenceRepository: String
    let referenceCommit: String
    let sourceFiles: [String]
    let officialCount: Int
    let officialNames: [String]
    let nativeEquivalent: [String: String]
    let pending: [String]
  }

  func testPinnedChallengeIdentitiesArePartitionedAndNativeLinksResolve() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let data = try Data(
      contentsOf: repositoryRoot.appendingPathComponent("Compatibility/official-challenges.json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: data)
    let official = Set(fixture.officialNames)
    let mapped = Set(fixture.nativeEquivalent.keys)
    let pending = Set(fixture.pending)

    XCTAssertEqual(fixture.referenceRepository, "monkeytypegame/monkeytype")
    XCTAssertEqual(fixture.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(fixture.sourceFiles.count, 3)
    XCTAssertEqual(fixture.officialCount, 58)
    XCTAssertEqual(fixture.officialNames.count, fixture.officialCount)
    XCTAssertEqual(official.count, fixture.officialCount)
    XCTAssertEqual(mapped.count, 27)
    XCTAssertEqual(fixture.pending.count, pending.count)
    XCTAssertTrue(mapped.isDisjoint(with: pending))
    XCTAssertEqual(mapped.union(pending), official)
    XCTAssertEqual(
      Set(TypebarChallengeLibrary.all.flatMap(\.legacyURLNames)), mapped)

    for (officialName, nativeID) in fixture.nativeEquivalent {
      let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: nativeID), officialName)
      XCTAssertTrue(challenge.legacyURLNames.contains(officialName), officialName)
      XCTAssertEqual(
        try LegacyChallengeLinkImporter.challenge(
          from: "https://example.invalid/?challenge=\(officialName)",
          challenges: TypebarChallengeLibrary.all)?.id,
        nativeID, officialName)
    }
  }

  func testOfficialFunboxChallengesPreservePinnedPresetsAndRequirements() throws {
    let hourLong: [(String, TestModifier, TimeInterval)] = [
      ("rollercoaster", .roundVisual, 3_600),
      ("oneHourMirror", .mirrorVisual, 3_600),
      ("chooChoo", .chooVisual, 3_600),
      ("earfquake", .earthquakeVisual, 3_600),
      ("simonSez", .simonSays, 3_600),
      ("accountant", .accountingStream, 3_600),
      ("whatAreWordsAtThisPoint", .gibberishStream, 60),
      ("specials", .specialCharacterStream, 60),
      ("aeiou", .listening, 60),
      ("asciiWarrior", .asciiStream, 60),
      ("iKiNdAlIkEhOwInEfFiCiEnTqWeRtYiS", .alternatingCase, 60),
      ("oneNauseousMonkey", .nauseaVisual, 60),
    ]
    for (name, modifier, minimumDuration) in hourLong {
      let challenge = try officialChallenge(name)
      XCTAssertEqual(challenge.preset.configuration.mode, .time, name)
      XCTAssertEqual(challenge.preset.configuration.duration, 3_600, name)
      XCTAssertEqual(challenge.preset.configuration.modifiers, [modifier], name)
      XCTAssertEqual(challenge.requirements.minimumDuration, minimumDuration, name)
      XCTAssertEqual(challenge.requirements.exactFunboxes, [modifier], name)
      XCTAssertFalse(challenge.dailyEligible, name)
    }

    for (name, modifier) in [
      ("hidden", TestModifier.readAhead),
      ("iCanSeeTheFuture", .readAheadHard),
    ] {
      let challenge = try officialChallenge(name)
      XCTAssertEqual(challenge.preset.configuration.mode, .time, name)
      XCTAssertEqual(challenge.preset.configuration.duration, 60, name)
      XCTAssertEqual(challenge.preset.configuration.modifiers, [modifier], name)
      XCTAssertEqual(challenge.requirements.minimumDuration, 60, name)
      XCTAssertEqual(challenge.requirements.wpm, .minimum(100), name)
      XCTAssertEqual(challenge.requirements.exactFunboxes, [modifier], name)
      XCTAssertEqual(challenge.requirements.configuration?.tapeMode, .off, name)
      XCTAssertFalse(challenge.dailyEligible, name)
    }

    let mnemonist = try officialChallenge("mnemonist")
    XCTAssertEqual(mnemonist.preset.configuration.mode, .words)
    XCTAssertEqual(mnemonist.preset.configuration.wordLimit, 25)
    XCTAssertEqual(mnemonist.preset.configuration.difficulty, .master)
    XCTAssertEqual(mnemonist.preset.configuration.modifiers, [.memory])
    XCTAssertEqual(mnemonist.requirements.configuration?.tapeMode, .off)
    XCTAssertNil(mnemonist.requirements.wpm)
    XCTAssertNil(mnemonist.requirements.accuracy)
    XCTAssertNil(mnemonist.requirements.exactFunboxes)
    XCTAssertFalse(mnemonist.dailyEligible)
  }

  private func officialChallenge(_ name: String) throws -> TypebarChallenge {
    try XCTUnwrap(LegacyChallengeLinkImporter.challenge(
      from: "https://example.invalid/?challenge=\(name)",
      challenges: TypebarChallengeLibrary.all), name)
  }
}
