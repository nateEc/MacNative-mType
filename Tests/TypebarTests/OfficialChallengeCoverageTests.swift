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
    XCTAssertEqual(mapped.count, 38)
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

  func testOfficialMetricAndSingleWordCustomChallengesLoadAndPractice() throws {
    let sixtyNine = try officialChallenge("69")
    XCTAssertEqual(sixtyNine.preset.configuration.mode, .time)
    XCTAssertEqual(sixtyNine.preset.configuration.duration, 69)
    XCTAssertEqual(sixtyNine.requirements.wpm, .exact(69))
    XCTAssertEqual(sixtyNine.requirements.rawWPM, .exact(69))
    XCTAssertEqual(sixtyNine.requirements.accuracy, .exact(69))
    XCTAssertEqual(sixtyNine.requirements.consistency, .exact(69))
    XCTAssertFalse(sixtyNine.dailyEligible)

    for (name, word, count, minimumWPM) in [
      ("antidiseWhat", "antidisestablishmentarianism", 1, 200),
      ("iveGotThePower", "power", 10, 400),
      ("developd", "develop", 1_000, nil),
      ("whatsThisWebsiteCalledAgain", "monkeytype", 1_000, nil),
    ] as [(String, String, Int, Int?)] {
      let challenge = try officialChallenge(name)
      let configuration = challenge.preset.configuration
      XCTAssertEqual(configuration.mode, .custom, name)
      XCTAssertEqual(configuration.customTextCompletion, .words, name)
      XCTAssertEqual(configuration.customTextOrdering, .inOrder, name)
      XCTAssertEqual(configuration.wordLimit, count, name)
      XCTAssertEqual(challenge.preset.customText, word, name)
      XCTAssertEqual(challenge.requirements.wpm, minimumWPM.map(ChallengeMetricRequirement.minimum), name)
      XCTAssertFalse(challenge.dailyEligible, name)
      let session = TestSessionFactory.make(configuration: configuration, customText: word)
      XCTAssertTrue(session.prompt.hasPrefix(word), name)
      XCTAssertTrue(session.usesIncrementalPromptExtension, name)
      var practice = TestSessionFactory.make(
        configuration: configuration.with(challengeID: challenge.id), customText: word)
      let start = Date(timeIntervalSince1970: 100)
      for index in 0..<count {
        practice.insert(word + (index == count - 1 ? "" : " "),
          at: start.addingTimeInterval(Double(index) * 0.1))
      }
      XCTAssertEqual(practice.result()?.outcome, .completed, name)
      XCTAssertEqual(practice.result()?.configuration.challengeID, challenge.id, name)
    }
  }

  func testSpeedSpacerUsesOneHundredFreshAlphabetSelections() throws {
    let challenge = try officialChallenge("speedSpacer")
    let alphabet = (97...122).compactMap(UnicodeScalar.init).map(String.init)
    let source = alphabet.joined(separator: " ")
    let configuration = challenge.preset.configuration
    XCTAssertEqual(configuration.mode, .custom)
    XCTAssertEqual(configuration.customTextCompletion, .words)
    XCTAssertEqual(configuration.customTextOrdering, .random)
    XCTAssertEqual(configuration.wordLimit, 100)
    XCTAssertEqual(challenge.preset.customText, source)
    XCTAssertEqual(challenge.requirements.wpm, .minimum(100))
    XCTAssertFalse(challenge.dailyEligible)

    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let generated = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(generated.count, 100)
    XCTAssertTrue(generated.allSatisfy(Set(alphabet).contains))
    for index in 2..<generated.count {
      XCTAssertNotEqual(generated[index], generated[index - 1])
      XCTAssertNotEqual(generated[index], generated[index - 2])
    }
    let start = Date(timeIntervalSince1970: 100)
    for (index, word) in generated.enumerated() {
      session.insert(word + (index == generated.count - 1 ? "" : " "),
        at: start.addingTimeInterval(Double(index) * 0.1))
    }
    XCTAssertEqual(session.result()?.outcome, .completed)
  }

  func testBigramSaladDrawsOneHundredShortWordsAndRequiresSpeed() throws {
    let challenge = try officialChallenge("bigramSalad")
    let configuration = challenge.preset.configuration
    XCTAssertEqual(configuration.mode, .custom)
    XCTAssertEqual(configuration.customTextCompletion, .words)
    XCTAssertEqual(configuration.customTextOrdering, .random)
    XCTAssertEqual(configuration.wordLimit, 100)
    XCTAssertEqual(challenge.requirements.wpm, .minimum(100))
    XCTAssertFalse(challenge.dailyEligible)

    let source = try XCTUnwrap(challenge.preset.customText)
    let candidates = source.split(separator: " ").map(String.init)
    XCTAssertEqual(Set(candidates).count, 20)
    XCTAssertTrue(candidates.allSatisfy {
      $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isLowercase }
    })
    var session = TestSessionFactory.make(
      configuration: configuration.with(challengeID: challenge.id), customText: source)
    let generated = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(generated.count, 100)
    XCTAssertTrue(generated.allSatisfy(Set(candidates).contains))
    XCTAssertFalse(session.usesIncrementalPromptExtension)
    for index in 2..<generated.count {
      XCTAssertNotEqual(generated[index], generated[index - 1])
      XCTAssertNotEqual(generated[index], generated[index - 2])
    }
    let start = Date(timeIntervalSince1970: 100)
    for (index, word) in generated.enumerated() {
      session.insert(word + (index == generated.count - 1 ? "" : " "),
        at: start.addingTimeInterval(Double(index) * 0.1))
    }
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
    let slow = CompletedTestResult(
      id: result.id, configuration: result.configuration, outcome: result.outcome,
      startedAt: result.startedAt, finishedAt: result.finishedAt,
      typedCharacterCount: result.typedCharacterCount,
      correctCharacterCount: result.correctCharacterCount,
      errorCount: result.errorCount, wpm: 99, rawWpm: result.rawWpm,
      accuracy: result.accuracy, prompt: result.prompt,
      replayEvents: result.replayEvents)
    XCTAssertFalse(ChallengeEvaluator.evaluate(slow, challenge: challenge).passed)
  }

  func testRepeatedWordEnduranceChallengeFamilyKeepsOfficialWordCounts() throws {
    for (name, count) in [
      ("simp", 1_000),
      ("trueSimp", 10_000),
      ("simpLord", 100_000),
    ] {
      let challenge = try officialChallenge(name)
      let configuration = challenge.preset.configuration
      XCTAssertEqual(configuration.mode, .custom, name)
      XCTAssertEqual(configuration.customTextCompletion, .words, name)
      XCTAssertEqual(configuration.customTextOrdering, .inOrder, name)
      XCTAssertEqual(configuration.wordLimit, count, name)
      XCTAssertEqual(challenge.preset.customText, "typebar", name)
      XCTAssertNil(challenge.requirements.wpm, name)
      XCTAssertFalse(challenge.dailyEligible, name)

      var session = TestSessionFactory.make(
        configuration: configuration.with(challengeID: challenge.id),
        customText: try XCTUnwrap(challenge.preset.customText))
      XCTAssertTrue(session.usesIncrementalPromptExtension, name)
      XCTAssertEqual(session.prompt.split(separator: " ").count, 100, name)
      XCTAssertLessThan(session.prompt.count, 1_000, name)
      session.insert("typebar typebar ", at: Date(timeIntervalSince1970: 100))
      XCTAssertEqual(session.completedWordCount, 2, name)
      XCTAssertFalse(session.isFinished, name)
      XCTAssertTrue(session.prompt.hasPrefix("typebar typebar typebar"), name)
    }
  }

  func testFiniteRandomCustomWordsDoNotCycleAnInitialChunk() {
    let draws = [0, 0, 1, 0, 2, 1, 3]
    var drawIndex = 0
    XCTAssertEqual(CustomTextOrderPolicy.prompt(
      from: "amber harbor quiet lake", ordering: .random, wordCount: 4,
      random: {
        defer { drawIndex += 1 }
        return draws[drawIndex]
      }), "amber harbor quiet lake")

    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 100, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    let session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    XCTAssertEqual(session.prompt.split(separator: " ").count, 100)
    XCTAssertFalse(session.usesIncrementalPromptExtension)
  }

  func testLargeImportedRandomWordLimitKeepsBoundedIncrementalPrompt() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 1_001, difficulty: .normal,
      rules: .init(), customTextCompletion: .words, customTextOrdering: .random)
    let session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor quiet lake")
    XCTAssertLessThan(session.prompt.split(separator: " ").count, 200)
    XCTAssertTrue(session.usesIncrementalPromptExtension)
  }

  func testThreeLayoutChallengeRequiresRecordedPerLayoutEvidence() throws {
    let challenge = try officialChallenge("beLikeWater")
    XCTAssertEqual(challenge.preset.configuration.mode, .time)
    XCTAssertEqual(challenge.preset.configuration.duration, 60)
    XCTAssertEqual(challenge.preset.configuration.modifiers, [.layoutFluid])
    XCTAssertEqual(challenge.requirements.minimumDuration, 60)
    XCTAssertEqual(challenge.requirements.exactFunboxes, [.layoutFluid])
    XCTAssertEqual(challenge.requirements.layoutFluidMinimumWPM, 50)
    XCTAssertFalse(challenge.dailyEligible)

    let layouts = LayoutFluidPolicy.defaultLayouts
    let missing = layoutResult(configuration: challenge.preset.configuration, counts: [90, 90, 90])
    let missingEvaluation = ChallengeEvaluator.evaluate(missing, challenge: challenge)
    XCTAssertFalse(missingEvaluation.passed)
    XCTAssertTrue(missingEvaluation.failedRequirements.contains { $0.contains("布局") })

    let passing = layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 90, 90], layouts: layouts)
    XCTAssertEqual(LayoutFluidChallengePolicy.segmentSpeeds(passing, layouts: layouts)?.map { $0.1 },
      [54, 54, 54])
    XCTAssertTrue(ChallengeEvaluator.evaluate(passing, challenge: challenge).passed)

    let slowMiddle = layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 80, 100], layouts: layouts)
    let slowEvaluation = ChallengeEvaluator.evaluate(slowMiddle, challenge: challenge)
    XCTAssertFalse(slowEvaluation.passed)
    XCTAssertTrue(slowEvaluation.failedRequirements.contains { $0.contains("Colemak") })
    let mistypedMiddle = layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 90, 90],
      layouts: layouts, forcedErrorSegment: 1)
    XCTAssertFalse(ChallengeEvaluator.evaluate(mistypedMiddle, challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 90, 90],
      layouts: [.ansiQwerty, .ansiQwerty, .ansiDvorak]), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 90, 90],
      layouts: [.ansiQwerty, .ansiDvorak]), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(layoutResult(
      configuration: .timed(seconds: 90).with(modifiers: [.layoutFluid]),
      counts: [90, 90, 90], layouts: layouts), challenge: challenge).passed)

    let atBoundaries = layoutResult(
      configuration: challenge.preset.configuration, counts: [90, 90, 90],
      layouts: layouts, offsets: [10, 20, 40])
    XCTAssertEqual(LayoutFluidChallengePolicy.segmentSpeeds(atBoundaries, layouts: layouts)?
      .map { $0.1 }, [54, 54, 54])

    let encoded = try JSONEncoder().encode(passing)
    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: encoded)
    XCTAssertEqual(restored.challengePresentation?.layoutFluidLayouts, layouts)
    XCTAssertTrue(ChallengeEvaluator.evaluate(restored, challenge: challenge).passed)
    var archived = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var oldPresentation = try XCTUnwrap(archived["challengePresentation"] as? [String: Any])
    oldPresentation.removeValue(forKey: "layoutFluidLayouts")
    archived["challengePresentation"] = oldPresentation
    let oldResult = try JSONDecoder().decode(
      CompletedTestResult.self, from: JSONSerialization.data(withJSONObject: archived))
    XCTAssertNil(oldResult.challengePresentation?.layoutFluidLayouts)
    XCTAssertFalse(ChallengeEvaluator.evaluate(oldResult, challenge: challenge).passed)
    let legacySnapshot = try JSONDecoder().decode(
      ChallengePresentationSnapshot.self,
      from: Data(#"{"liveSpeedStyle":"off","paceCaretStyle":"off","tapeMode":"off"}"#.utf8))
    XCTAssertNil(legacySnapshot.layoutFluidLayouts)
  }

  func testThreeLayoutChallengePassesFromNativeSessionReplay() throws {
    let challenge = try officialChallenge("beLikeWater")
    var session = TestSessionFactory.make(
      configuration: challenge.preset.configuration.with(challengeID: challenge.id))
    let prompt = Array(session.prompt)
    XCTAssertGreaterThanOrEqual(prompt.count, 300)
    let start = Date(timeIntervalSince1970: 100)
    for second in 0..<60 {
      let offset = second * 5
      session.insert(String(prompt[offset..<(offset + 5)]),
        at: start.addingTimeInterval(Double(second)))
    }
    session.tick(at: start.addingTimeInterval(60))
    let result = try XCTUnwrap(session.result(
      challengePresentation: .init(
        liveSpeedStyle: .off, paceCaretStyle: .off, tapeMode: .off,
        layoutFluidLayouts: LayoutFluidPolicy.defaultLayouts)))
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
  }

  private func layoutResult(
    configuration: TestConfiguration, counts: [Int], layouts: [KeyboardLayout]? = nil,
    offsets: [TimeInterval] = [10, 30, 50], forcedErrorSegment: Int? = nil
  ) -> CompletedTestResult {
    let start = Date(timeIntervalSince1970: 100)
    let characters = counts.reduce(0, +)
    return .init(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(60),
      typedCharacterCount: characters, correctCharacterCount: characters,
      errorCount: 0, wpm: characters / 5, rawWpm: characters / 5, accuracy: 100,
      prompt: String(repeating: "a", count: max(300, characters)),
      replayEvents: counts.indices.map { index in
        .init(offset: offsets[index], kind: .insert,
          text: String(repeating: "a", count: counts[index]),
          forceError: index == forcedErrorSegment)
      },
      challengePresentation: layouts.map {
        .init(liveSpeedStyle: .off, paceCaretStyle: .off, tapeMode: .off,
          layoutFluidLayouts: $0)
      })
  }

  private func officialChallenge(_ name: String) throws -> TypebarChallenge {
    try XCTUnwrap(LegacyChallengeLinkImporter.challenge(
      from: "https://example.invalid/?challenge=\(name)",
      challenges: TypebarChallengeLibrary.all), name)
  }
}
