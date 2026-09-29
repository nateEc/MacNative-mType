import Foundation
import XCTest

@testable import Typebar

final class OfficialChallengeCoverageTests: XCTestCase {
  func testJollyNativeScriptRequiresFull86WordsAndSeventyWPM() throws {
    let challenge = try officialChallenge("jolly")
    let source = try XCTUnwrap(challenge.preset.customText)
    let configuration = challenge.preset.configuration
    XCTAssertEqual(source.split(whereSeparator: \.isWhitespace).count, 86)
    XCTAssertEqual(configuration.mode, .custom)
    XCTAssertEqual(configuration.customTextCompletion, .finish)
    XCTAssertEqual(configuration.customTextOrdering, .inOrder)
    XCTAssertEqual(challenge.requirements.wpm, .minimum(70))
    XCTAssertEqual(challenge.requirements.exactPrompt, source)

    let start = Date(timeIntervalSince1970: 100)
    var session = TestSessionFactory.make(
      configuration: configuration.with(challengeID: challenge.id), customText: source)
    session.insertBatch(String(source.prefix(10)), at: start)
    session.insertBatch(String(source.dropFirst(10)), at: start.addingTimeInterval(1))
    let completed = try XCTUnwrap(session.result())
    XCTAssertEqual(completed.outcome, .completed)
    XCTAssertEqual(completed.prompt, source)
    XCTAssertTrue(ChallengeEvaluator.evaluate(completed, challenge: challenge).passed)

    func result(_ configuration: TestConfiguration, prompt: String, wpm: Int) -> CompletedTestResult {
      .init(id: UUID(), configuration: configuration, outcome: .completed,
        startedAt: start, finishedAt: start.addingTimeInterval(60),
        typedCharacterCount: source.count, correctCharacterCount: source.count,
        errorCount: 0, wpm: wpm, rawWpm: wpm, accuracy: 100, prompt: prompt)
    }
    XCTAssertTrue(ChallengeEvaluator.evaluate(
      result(configuration, prompt: source, wpm: 70), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(configuration, prompt: source, wpm: 69), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(configuration, prompt: "other text", wpm: 100), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(.words(86), prompt: source, wpm: 100), challenge: challenge).passed)
    let looping = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 86, difficulty: .normal,
      rules: .init(), customTextCompletion: .words)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(looping, prompt: source, wpm: 100), challenge: challenge).passed)
  }

  func testPhysicalTechniqueChallengesKeepReferenceDurationsAndHonestScoring() throws {
    let cases: [(String, TimeInterval, Int?)] = [
      ("thumbWarrior", 3_600, nil),
      ("feetWarrior", 3_600, nil),
      ("upsideDown", 60, 60),
    ]
    let start = Date(timeIntervalSince1970: 100)
    for (legacyName, seconds, minimumWpm) in cases {
      let challenge = try officialChallenge(legacyName)
      XCTAssertEqual(challenge.preset.configuration.mode, .time, legacyName)
      XCTAssertEqual(challenge.preset.configuration.duration, seconds, legacyName)
      XCTAssertEqual(challenge.requirements.minimumDuration, seconds, legacyName)
      XCTAssertEqual(challenge.requirements.configuration?.duration, seconds, legacyName)
      XCTAssertEqual(challenge.requirements.wpm, minimumWpm.map(ChallengeMetricRequirement.minimum), legacyName)
      XCTAssertTrue(challenge.description.contains("自觉"), legacyName)

      func result(configuration: TestConfiguration, elapsed: TimeInterval, wpm: Int)
        -> CompletedTestResult {
        .init(id: UUID(), configuration: configuration, outcome: .completed,
          startedAt: start, finishedAt: start.addingTimeInterval(elapsed),
          typedCharacterCount: 200, correctCharacterCount: 200, errorCount: 0,
          wpm: wpm, rawWpm: wpm, accuracy: 100)
      }
      XCTAssertTrue(ChallengeEvaluator.evaluate(result(
        configuration: challenge.preset.configuration, elapsed: seconds,
        wpm: minimumWpm ?? 40), challenge: challenge).passed, legacyName)
      XCTAssertFalse(ChallengeEvaluator.evaluate(result(
        configuration: challenge.preset.configuration, elapsed: seconds - 1,
        wpm: minimumWpm ?? 40), challenge: challenge).passed, legacyName)
      XCTAssertFalse(ChallengeEvaluator.evaluate(result(
        configuration: .timed(seconds: seconds + 60), elapsed: seconds + 60,
        wpm: minimumWpm ?? 40), challenge: challenge).passed, legacyName)
      if let minimumWpm {
        XCTAssertFalse(ChallengeEvaluator.evaluate(result(
          configuration: challenge.preset.configuration, elapsed: seconds,
          wpm: minimumWpm - 1), challenge: challenge).passed, legacyName)
      }
    }
  }

  func testOneHandedChallengeBuildsLayoutSpecificSourceAndDualLimit() throws {
    for side in OneHandedChallengeSide.allCases {
      let selection = OneHandedChallengeSelection(layout: .ansiQwerty, side: side)
      let preset = try XCTUnwrap(OneHandedChallengePolicy.preset(for: selection), "\(side)")
      XCTAssertEqual(preset.configuration.duration, 3_600)
      XCTAssertEqual(preset.configuration.wordLimit, 10_000)
      XCTAssertEqual(preset.configuration.customTextCompletion, .words)
      XCTAssertEqual(OneHandedChallengePolicy.identify(source: try XCTUnwrap(preset.customText)), selection)
      XCTAssertGreaterThan(try XCTUnwrap(preset.customText).split(separator: " ").count, 1)
    }
  }

  func testOneHandedChallengeRequiresSourceAndEitherTerminalEvidence() throws {
    let challenge = try officialChallenge("oneArmedBandit")
    let selection = OneHandedChallengeSelection(layout: .ansiQwerty, side: .right)
    let preset = try XCTUnwrap(OneHandedChallengePolicy.preset(for: selection))
    let validWord = try XCTUnwrap(preset.customText?.split(separator: " ").first).description
    let start = Date(timeIntervalSince1970: 100)
    func result(duration: TimeInterval, words: Int?, prompt: String,
      selection: OneHandedChallengeSelection? = selection) -> CompletedTestResult {
      .init(id: UUID(), configuration: preset.configuration, outcome: .completed,
        startedAt: start, finishedAt: start.addingTimeInterval(duration),
        typedCharacterCount: 4, correctCharacterCount: 4, errorCount: 0,
        wpm: 50, rawWpm: 50, accuracy: 100, prompt: prompt,
        challengePresentation: .init(liveSpeedStyle: .off, paceCaretStyle: .off,
          tapeMode: .off, oneHandedSelection: selection, completedWords: words))
    }
    XCTAssertTrue(ChallengeEvaluator.evaluate(
      result(duration: 3_600, words: 3, prompt: validWord), challenge: challenge).passed)
    XCTAssertTrue(ChallengeEvaluator.evaluate(
      result(duration: 600, words: 10_000, prompt: validWord), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(duration: 600, words: 9_999, prompt: validWord), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(duration: 3_600, words: 3, prompt: "notahandword"), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(
      result(duration: 3_600, words: nil, prompt: validWord, selection: nil), challenge: challenge).passed)
  }

  func testOneHandedSelectionSurvivesActiveTestArchive() throws {
    let selection = OneHandedChallengeSelection(layout: .ansiQwerty, side: .left)
    var preset = try XCTUnwrap(OneHandedChallengePolicy.preset(for: selection))
    preset.configuration = preset.configuration.with(challengeID: "one-handed-bandit")
    XCTAssertTrue(SettingsJSONConfigurationPolicy.isValid(preset.configuration))
    XCTAssertFalse(SettingsJSONConfigurationPolicy.isValid(
      preset.configuration.with(challengeID: nil)))
    let document = ActiveTestSelectionDocument(
      preset: preset, testParameterMemory: .defaults,
      oneHandedChallengeSelection: selection)
    let restored = try JSONDecoder().decode(ActiveTestSelectionDocument.self,
      from: JSONEncoder().encode(document))
    XCTAssertEqual(ActiveTestSelectionPolicy.validated(restored)?.oneHandedChallengeSelection,
      selection)
  }

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
    XCTAssertEqual(mapped.count, 46)
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

  func testWingdingsChallengeRequiresRealFontHiddenGuideAndTenMasterWords() throws {
    let challenge = try officialChallenge("wingdings")
    XCTAssertEqual(challenge.preset.configuration.mode, .words)
    XCTAssertEqual(challenge.preset.configuration.wordLimit, 10)
    XCTAssertEqual(challenge.preset.configuration.difficulty, .master)
    XCTAssertEqual(challenge.requirements.wpm, .minimum(60))
    XCTAssertEqual(challenge.requirements.accuracy, .exact(100))
    XCTAssertEqual(challenge.requirements.configuration?.wordLimit, 10)
    XCTAssertEqual(challenge.requirements.configuration?.fontFamily, "Wingdings")
    XCTAssertEqual(challenge.requirements.configuration?.keyboardGuideMode, .off)
    XCTAssertFalse(challenge.dailyEligible)

    let start = Date(timeIntervalSince1970: 100)
    func result(
      configuration: TestConfiguration? = nil, wpm: Int = 60,
      presentation: ChallengePresentationSnapshot? = nil
    ) -> CompletedTestResult {
      .init(id: UUID(), configuration: configuration ?? challenge.preset.configuration,
        outcome: .completed, startedAt: start,
        finishedAt: start.addingTimeInterval(10),
        typedCharacterCount: 50, correctCharacterCount: 50,
        errorCount: 0, wpm: wpm, rawWpm: wpm, accuracy: 100,
        prompt: "one two three four five six seven eight nine ten",
        challengePresentation: presentation)
    }
    let valid = ChallengePresentationSnapshot(
      liveSpeedStyle: .off, paceCaretStyle: .off, tapeMode: .off,
      fontFamily: "Wingdings", keyboardGuideMode: .off,
      fontStayedAvailable: true)
    var nativeSession = TestSessionFactory.make(
      configuration: challenge.preset.configuration.with(challengeID: challenge.id))
    let nativePrompt = nativeSession.prompt
    XCTAssertEqual(nativePrompt.split(separator: " ").count, 10)
    nativeSession.insertBatch(String(nativePrompt.prefix(5)), at: start)
    nativeSession.insertBatch(String(nativePrompt.dropFirst(5)),
      at: start.addingTimeInterval(1))
    let nativeResult = try XCTUnwrap(nativeSession.result(challengePresentation: valid))
    XCTAssertEqual(nativeResult.outcome, .completed)
    XCTAssertTrue(ChallengeEvaluator.evaluate(nativeResult, challenge: challenge).passed)
    if let installedFont = WingdingsChallengeFont.resolve(size: 12) {
      XCTAssertEqual(installedFont.familyName, "Wingdings")
    }
    XCTAssertTrue(ChallengeEvaluator.evaluate(result(presentation: valid),
      challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(wpm: 59, presentation: valid),
      challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(
      configuration: .words(25, difficulty: .master), presentation: valid),
      challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(
      configuration: .words(10), presentation: valid), challenge: challenge).passed)
    for invalid in [
      ChallengePresentationSnapshot(liveSpeedStyle: .off, paceCaretStyle: .off,
        tapeMode: .off, fontFamily: "Wingdings 2", keyboardGuideMode: .off,
        fontStayedAvailable: true),
      ChallengePresentationSnapshot(liveSpeedStyle: .off, paceCaretStyle: .off,
        tapeMode: .off, fontFamily: "Wingdings", keyboardGuideMode: .next,
        fontStayedAvailable: true),
      ChallengePresentationSnapshot(liveSpeedStyle: .off, paceCaretStyle: .off,
        tapeMode: .off, fontFamily: "Wingdings", keyboardGuideMode: .off,
        fontStayedAvailable: false),
    ] {
      XCTAssertFalse(ChallengeEvaluator.evaluate(result(presentation: invalid),
        challenge: challenge).passed)
    }
    let restored = try JSONDecoder().decode(ChallengePresentationSnapshot.self,
      from: JSONEncoder().encode(valid))
    XCTAssertEqual(restored.fontFamily, "Wingdings")
    let old = try JSONDecoder().decode(ChallengePresentationSnapshot.self,
      from: Data(#"{"liveSpeedStyle":"off","paceCaretStyle":"off","tapeMode":"off"}"#.utf8))
    XCTAssertNil(old.fontFamily)
    XCTAssertNil(old.keyboardGuideMode)
    XCTAssertNil(old.fontStayedAvailable)
  }

  func testBeepBoopUsesIndependentCompleteNoSpaceScriptAndExactScoring() throws {
    let challenge = try officialChallenge("beepBoop")
    let source = try XCTUnwrap(challenge.preset.customText)
    let configuration = challenge.preset.configuration
    XCTAssertEqual(source.split(separator: " ").count, 77)
    XCTAssertEqual(configuration.mode, .custom)
    XCTAssertEqual(configuration.customTextCompletion, .words)
    XCTAssertEqual(configuration.customTextOrdering, .inOrder)
    XCTAssertEqual(configuration.wordLimit, 77)
    XCTAssertEqual(configuration.modifiers, [.noSpaces])
    XCTAssertEqual(challenge.requirements.wpm, .minimum(45))
    XCTAssertEqual(challenge.requirements.accuracy, .exact(100))
    XCTAssertEqual(challenge.requirements.exactFunboxes, [.noSpaces])
    XCTAssertFalse(challenge.dailyEligible)

    var session = TestSessionFactory.make(
      configuration: configuration.with(challengeID: challenge.id), customText: source)
    let prompt = session.prompt
    XCTAssertFalse(prompt.contains(" "))
    XCTAssertEqual(challenge.requirements.exactPrompt, prompt)
    let start = Date(timeIntervalSince1970: 100)
    session.insertBatch(String(prompt.prefix(10)), at: start)
    session.insertBatch(String(prompt.dropFirst(10)), at: start.addingTimeInterval(1))
    let completed = try XCTUnwrap(session.result())
    XCTAssertEqual(completed.outcome, .completed)
    let evaluation = ChallengeEvaluator.evaluate(completed, challenge: challenge)
    XCTAssertTrue(evaluation.passed, "\(evaluation.failedRequirements)")

    let wrongScript = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(10),
      typedCharacterCount: 100, correctCharacterCount: 100,
      errorCount: 0, wpm: 100, rawWpm: 100, accuracy: 100,
      prompt: String(repeating: "x", count: 100))
    XCTAssertFalse(ChallengeEvaluator.evaluate(wrongScript, challenge: challenge).passed)
    let slow = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(100),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count,
      errorCount: 0, wpm: 44, rawWpm: 44, accuracy: 100, prompt: prompt)
    XCTAssertFalse(ChallengeEvaluator.evaluate(slow, challenge: challenge).passed)
    let inaccurate = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(10),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count - 1,
      errorCount: 1, wpm: 100, rawWpm: 100, accuracy: 99, prompt: prompt)
    XCTAssertFalse(ChallengeEvaluator.evaluate(inaccurate, challenge: challenge).passed)
    let roundedToHundred = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(10),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count - 1,
      errorCount: 1, wpm: 100, rawWpm: 100, accuracy: 100,
      preciseAccuracy: 99.8, prompt: prompt)
    XCTAssertFalse(ChallengeEvaluator.evaluate(roundedToHundred, challenge: challenge).passed)
    let wrongMode = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 60).with(modifiers: [.noSpaces]),
      outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(10),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count,
      errorCount: 0, wpm: 100, rawWpm: 100, accuracy: 100, prompt: prompt)
    XCTAssertFalse(ChallengeEvaluator.evaluate(wrongMode, challenge: challenge).passed)
    let missingNoSpace = CompletedTestResult(
      id: UUID(), configuration: TestConfiguration(
        mode: .custom, duration: nil, wordLimit: 77, difficulty: .normal,
        rules: .init(), customTextCompletion: .words),
      outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(10),
      typedCharacterCount: prompt.count, correctCharacterCount: prompt.count,
      errorCount: 0, wpm: 100, rawWpm: 100, accuracy: 100, prompt: prompt)
    XCTAssertFalse(ChallengeEvaluator.evaluate(missingNoSpace, challenge: challenge).passed)
  }

  func testMouseWarriorRequiresOneHourNoFunboxAndRecordedVirtualInput() throws {
    let challenge = try officialChallenge("mouseWarrior")
    XCTAssertEqual(challenge.preset.configuration.mode, .time)
    XCTAssertEqual(challenge.preset.configuration.duration, 3_600)
    XCTAssertEqual(challenge.requirements.minimumDuration, 3_600)
    XCTAssertEqual(challenge.requirements.exactFunboxes, [])
    XCTAssertTrue(challenge.requirements.requiresVirtualKeyboardOnly)
    XCTAssertFalse(challenge.dailyEligible)

    let start = Date(timeIntervalSince1970: 100)
    var session = TypingSession(configuration: challenge.preset.configuration, prompt: "a b ")
    session.insertBatch("a", at: start, origin: .virtualKeyboard)
    XCTAssertTrue(session.hasAcceptedVirtualKeyboardInput)
    XCTAssertTrue(session.hasUsedOnlyVirtualKeyboard)
    session.insertBatch("x", at: start.addingTimeInterval(1))
    XCTAssertFalse(session.hasUsedOnlyVirtualKeyboard)
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertFalse(session.hasUsedOnlyVirtualKeyboard)
    var physicalKeySession = TypingSession(
      configuration: challenge.preset.configuration, prompt: "a b ")
    physicalKeySession.recordPhysicalKeyboardActivityDuringAttempt()
    physicalKeySession.insertBatch("a", at: start, origin: .virtualKeyboard)
    XCTAssertTrue(physicalKeySession.hasUsedOnlyVirtualKeyboard)
    physicalKeySession.recordPhysicalKeyboardActivityDuringAttempt()
    XCTAssertFalse(physicalKeySession.hasUsedOnlyVirtualKeyboard)
    physicalKeySession.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertFalse(physicalKeySession.hasUsedOnlyVirtualKeyboard)

    let presentation = ChallengePresentationSnapshot(
      liveSpeedStyle: .off, paceCaretStyle: .off, tapeMode: .off,
      virtualKeyboardOnly: session.hasUsedOnlyVirtualKeyboard)
    let encoded = try JSONEncoder().encode(presentation)
    XCTAssertFalse(try JSONDecoder().decode(
      ChallengePresentationSnapshot.self, from: encoded).virtualKeyboardOnly ?? true)
    let old = try JSONDecoder().decode(
      ChallengePresentationSnapshot.self,
      from: Data(#"{"liveSpeedStyle":"off","paceCaretStyle":"off","tapeMode":"off"}"#.utf8))
    XCTAssertNil(old.virtualKeyboardOnly)

    func result(
      duration: TimeInterval = 3_600, configuration: TestConfiguration? = nil,
      presentation: ChallengePresentationSnapshot? = nil
    ) -> CompletedTestResult {
      .init(
        id: UUID(), configuration: configuration ?? challenge.preset.configuration,
        outcome: .completed, startedAt: start,
        finishedAt: start.addingTimeInterval(duration),
        typedCharacterCount: 1, correctCharacterCount: 1,
        errorCount: 0, wpm: 1, rawWpm: 1, accuracy: 100,
        prompt: "a", replayEvents: [.init(offset: 1, kind: .insert, text: "a")],
        challengePresentation: presentation)
    }
    let virtualPresentation = ChallengePresentationSnapshot(
      liveSpeedStyle: .off, paceCaretStyle: .off, tapeMode: .off,
      virtualKeyboardOnly: true)
    XCTAssertTrue(ChallengeEvaluator.evaluate(
      result(presentation: virtualPresentation), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(presentation: presentation),
      challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(duration: 3_599,
      presentation: virtualPresentation), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(
      configuration: challenge.preset.configuration.with(modifiers: [.memory]),
      presentation: virtualPresentation), challenge: challenge).passed)
    XCTAssertFalse(ChallengeEvaluator.evaluate(result(
      configuration: .timed(seconds: 60), presentation: virtualPresentation),
      challenge: challenge).passed)
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
