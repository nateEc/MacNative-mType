import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Typebar

final class TypingEngineTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 10_000)

  func testLegacySyncPullResponseDefaultsMissingPaginationFlagToFinalPage() throws {
    let legacy = try JSONDecoder().decode(
      RemoteSyncPullResponse.self,
      from: Data(#"{"changes":[],"nextCursor":17}"#.utf8))
    XCTAssertEqual(legacy.nextCursor, 17)
    XCTAssertFalse(legacy.hasMore)

    let paged = try JSONDecoder().decode(
      RemoteSyncPullResponse.self,
      from: Data(#"{"changes":[],"nextCursor":23,"hasMore":true}"#.utf8))
    XCTAssertTrue(paged.hasMore)
  }

  func testRemoteAccountUserDefaultsLegacyServersToPasswordAndDecodesOAuthMethods() throws {
    let legacy = try JSONDecoder().decode(
      RemoteAccountUser.self,
      from: Data(
        #"{"id":"00000000-0000-0000-0000-000000000001","email":"legacy@example.com","displayName":"Legacy","totalExperience":8}"#
          .utf8))
    XCTAssertEqual(legacy.authenticationMethods, [.password])
    XCTAssertEqual(legacy.profileDetails, .init())
    XCTAssertTrue(legacy.availableBadges.isEmpty)
    XCTAssertNil(legacy.selectedBadgeID)

    let modern = try JSONDecoder().decode(
      RemoteAccountUser.self,
      from: Data(
        #"{"id":"00000000-0000-0000-0000-000000000002","email":"oauth@example.com","emailVerified":true,"displayName":"OAuth","totalExperience":12,"authenticationMethods":["google","password","discord"],"availableBadges":[{"id":"swift-line","title":"迅捷一行","systemImage":"bolt"}],"selectedBadgeID":"swift-line","profileDetails":{"bio":"Native first","keyboard":"ANSI","github":"typebar","socialHandle":"typist","websiteURL":"https://example.com","showActivity":false}}"#
          .utf8))
    XCTAssertTrue(modern.emailVerified)
    XCTAssertEqual(modern.authenticationMethods, [.google, .password, .discord])
    XCTAssertEqual(
      modern.profileDetails,
      .init(
        bio: "Native first", keyboard: "ANSI", github: "typebar", socialHandle: "typist",
        websiteURL: "https://example.com", showActivity: false))
    XCTAssertEqual(modern.availableBadges.map(\.id), ["swift-line"])
    XCTAssertEqual(modern.selectedBadgeID, "swift-line")

    let leaderboardEntry = try JSONDecoder().decode(
      RemoteLeaderboardEntry.self,
      from: Data(
        #"{"id":"00000000-0000-0000-0000-000000000003","rank":1,"userID":"00000000-0000-0000-0000-000000000002","displayName":"OAuth","mode":"time","language":"english","wpm":80,"accuracy":98,"consistency":99,"finishedAt":0,"selectedBadge":{"id":"swift-line","title":"迅捷一行","systemImage":"bolt"},"discordAvatar":{"subject":"123456789012345678","avatarHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}"#
          .utf8))
    XCTAssertEqual(leaderboardEntry.selectedBadge?.id, "swift-line")
    XCTAssertEqual(
      leaderboardEntry.discordAvatar?.cdnURL?.host,
      "cdn.discordapp.com")

    let legacyExperienceEntry = try JSONDecoder().decode(
      RemoteExperienceLeaderboardEntry.self,
      from: Data(
        #"{"id":"00000000-0000-0000-0000-000000000004","rank":1,"userID":"00000000-0000-0000-0000-000000000002","displayName":"OAuth","totalExperience":12}"#
          .utf8))
    XCTAssertNil(legacyExperienceEntry.selectedBadge)
  }

  func testRemoteDiscordAvatarBuildsOnlyValidatedCDNURLs() {
    let valid = RemoteDiscordAvatar(
      subject: "123456789012345678", avatarHash: "a_" + String(repeating: "b", count: 32))
    XCTAssertEqual(
      valid.cdnURL?.absoluteString,
      "https://cdn.discordapp.com/avatars/123456789012345678/a_\(String(repeating: "b", count: 32)).png?size=128")
    XCTAssertNil(RemoteDiscordAvatar(subject: "../invalid", avatarHash: String(repeating: "b", count: 32)).cdnURL)
    XCTAssertNil(RemoteDiscordAvatar(subject: "１２３", avatarHash: String(repeating: "b", count: 32)).cdnURL)
    XCTAssertNil(RemoteDiscordAvatar(subject: "123", avatarHash: "not-a-hash").cdnURL)
  }

  func testTimedTestCompletesAtDeadline() {
    var session = TypingSession(configuration: .timed(seconds: 15), prompt: "amber harbor")
    session.insert("a", at: start)
    session.insert("m", at: start.addingTimeInterval(11))
    session.tick(at: start.addingTimeInterval(15))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.remainingSeconds(at: start.addingTimeInterval(15)), 0)
  }

  func testCustomDurationAndWordCountRespectTheirExactConfiguredLimits() {
    var timed = TypingSession(configuration: .timed(seconds: 73), prompt: "amber harbor")
    timed.insert("a", at: start)
    timed.tick(at: start.addingTimeInterval(72.9))
    XCTAssertEqual(timed.outcome, .active)
    timed.insert("m", at: start.addingTimeInterval(72.9))
    timed.tick(at: start.addingTimeInterval(73))
    XCTAssertEqual(timed.outcome, .completed)

    var words = TestSessionFactory.make(configuration: .words(137))
    XCTAssertEqual(words.prompt.split(separator: " ").count, 137)
    words.insert(words.prompt, at: start)
    XCTAssertEqual(words.outcome, .completed)
  }

  func testInactivityPolicyCountsIdleIntervalsAndInvalidatesTrailingIdleTimedTests() throws {
    let events = [start.addingTimeInterval(0.2), start.addingTimeInterval(2.2)]
    XCTAssertEqual(
      TestInactivityPolicy.intervalCounts(
        activityDates: events, startedAt: start, endedAt: start.addingTimeInterval(4.6),
        includesFractionalTail: true),
      [1, 0, 1, 0, 0])
    XCTAssertEqual(
      TestInactivityPolicy.inactiveDuration(
        activityDates: events, startedAt: start, endedAt: start.addingTimeInterval(4.6),
        includesFractionalTail: true),
      3)

    var idle = TypingSession(configuration: .timed(seconds: 10), prompt: "amber harbor")
    idle.insert("a", at: start)
    idle.tick(at: start.addingTimeInterval(10))
    let invalidResult = try XCTUnwrap(idle.result(at: start.addingTimeInterval(10)))
    XCTAssertEqual(idle.outcome, .invalidAFK)
    XCTAssertEqual(invalidResult.afkDuration, 9)
    XCTAssertEqual(invalidResult.engagedDuration, 1)
    XCTAssertEqual(invalidResult.afkPercentage, 90, accuracy: 0.000_001)
    XCTAssertEqual(idle.remainingSeconds(at: start.addingTimeInterval(10)), 0)
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: invalidResult.outcome, enabled: true))
    XCTAssertEqual(
      invalidResult.outcome.statusText(savesResult: false), "本次因闲置无效 · 未保存为完成成绩")

    var active = TypingSession(configuration: .timed(seconds: 10), prompt: "amber harbor")
    active.insert("a", at: start)
    active.insert("m", at: start.addingTimeInterval(8))
    active.tick(at: start.addingTimeInterval(10))
    XCTAssertEqual(active.outcome, .completed)

    var keyboardOnly = TypingSession(configuration: .timed(seconds: 10), prompt: "amber harbor")
    keyboardOnly.insert("a", at: start)
    keyboardOnly.deleteBackward(at: start.addingTimeInterval(5))
    keyboardOnly.deleteBackward(at: start.addingTimeInterval(6))
    keyboardOnly.recordKeyboardActivity(at: start.addingTimeInterval(7))
    keyboardOnly.tick(at: start.addingTimeInterval(10))
    let keyboardOnlyResult = try XCTUnwrap(keyboardOnly.result())
    XCTAssertEqual(keyboardOnlyResult.afkDuration, 6)
  }

  func testAfkPercentageUsesTheCompletedWallClockDuration() {
    let result = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), afkDuration: 7, typedCharacterCount: 50,
      correctCharacterCount: 48, errorCount: 2, wpm: 19, rawWpm: 20, accuracy: 96)
    XCTAssertEqual(result.afkPercentage, 23.333_333_333_3, accuracy: 0.000_001)

    let instant = CompletedTestResult(
      id: UUID(), configuration: .words(10), outcome: .completed, startedAt: start,
      finishedAt: start, afkDuration: 1, typedCharacterCount: 0, correctCharacterCount: 0,
      errorCount: 0, wpm: 0, rawWpm: 0, accuracy: 100)
    XCTAssertEqual(instant.afkPercentage, 0)
  }

  func testResultConsistencyRebuildsCadenceOnlyFromLocalReplay() {
    let steadyEvents: [TypingReplayEvent] = [
      .init(offset: 0.2, kind: .insert, text: "a"),
      .init(offset: 1.2, kind: .insert, text: "b"),
      .init(offset: 2.2, kind: .insert, text: "c"),
    ]
    let steady = ResultConsistencyPolicy.metrics(events: steadyEvents, duration: 3)
    XCTAssertEqual(steady.typing, 100)
    XCTAssertEqual(steady.key, 100)

    let uneven = ResultConsistencyPolicy.metrics(
      events: [
        .init(offset: 0.2, kind: .insert, text: "a"),
        .init(offset: 1.2, kind: .insert, text: "b"),
        .init(offset: 1.4, kind: .insert, text: "c"),
        .init(offset: 3.8, kind: .insert, text: "d"),
      ],
      duration: 4
    )
    XCTAssertLessThan(uneven.typing, steady.typing)
    XCTAssertLessThan(uneven.key, steady.key)

    let unavailable = ResultConsistencyPolicy.metrics(events: [], duration: 3)
    XCTAssertEqual(unavailable, .init(typing: 0, key: 0))
  }

  func testLegacyLeaderboardResponseDefaultsMissingConsistencyToZero() throws {
    let id = UUID()
    let finishedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    let payload = """
      {"id":"\(id.uuidString)","rank":1,"userID":"\(UUID().uuidString)","displayName":"Local","mode":"time","language":"english","wpm":80,"accuracy":99,"finishedAt":\(finishedAt.timeIntervalSinceReferenceDate)}
      """

    let entry = try JSONDecoder().decode(RemoteLeaderboardEntry.self, from: Data(payload.utf8))

    XCTAssertEqual(entry.consistency, 0)
  }

  func testLeaderboardRankResponsesDecodeAnAbsentStanding() throws {
    let wpm = try JSONDecoder().decode(
      RemoteLeaderboardRankResponse.self, from: Data(#"{"entry":null}"#.utf8))
    let experience = try JSONDecoder().decode(
      RemoteExperienceLeaderboardRankResponse.self, from: Data(#"{"entry":null}"#.utf8))

    XCTAssertNil(wpm.entry)
    XCTAssertNil(experience.entry)
    XCTAssertNil(experience.period)
    XCTAssertEqual(RemoteExperienceLeaderboardPeriod.lastWeek.displayName, "上周")
    XCTAssertTrue(RemoteExperienceLeaderboardPeriod.week.isConfirmed(by: nil))
    XCTAssertTrue(RemoteExperienceLeaderboardPeriod.lastWeek.isConfirmed(by: "lastWeek"))
    XCTAssertFalse(RemoteExperienceLeaderboardPeriod.lastWeek.isConfirmed(by: nil))
    XCTAssertFalse(RemoteExperienceLeaderboardPeriod.lastWeek.isConfirmed(by: "week"))
  }

  func testLegacyPublicProfileResponseDefaultsMissingHighestConsistencyToZero() throws {
    let id = UUID()
    let joinedAt = Date(timeIntervalSinceReferenceDate: 1_000)
    let payload = """
      {"id":"\(id.uuidString)","displayName":"Local","joinedAt":\(joinedAt.timeIntervalSinceReferenceDate),"completedResultCount":3,"bestWPM":80,"totalExperience":42}
      """

    let profile = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(payload.utf8))

    XCTAssertEqual(profile.highestConsistency, 0)
    XCTAssertTrue(profile.personalBests.isEmpty)
    XCTAssertNil(profile.activity)
    XCTAssertNil(profile.streak)
    XCTAssertEqual(profile.startedTestCount, 0)
    XCTAssertEqual(profile.totalTypingSeconds, 0)

    let modernPayload = """
      {"id":"\(id.uuidString)","displayName":"Local","joinedAt":\(joinedAt.timeIntervalSinceReferenceDate),"completedResultCount":3,"startedTestCount":5,"totalTypingSeconds":135.5,"bestWPM":80,"totalExperience":42,"streak":{"currentDays":2,"longestDays":4}}
      """
    let modern = try JSONDecoder().decode(RemotePublicProfile.self, from: Data(modernPayload.utf8))
    XCTAssertEqual(modern.streak, .init(currentDays: 2, longestDays: 4))
    XCTAssertEqual(modern.startedTestCount, 5)
    XCTAssertEqual(modern.totalTypingSeconds, 135.5)
  }

  func testWordsTestCompletesAtWordLimit() {
    var session = TypingSession(configuration: .words(2), prompt: "amber harbor quiet")
    session.insert("amber harbor", at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testLiveProgressUsesCountdownForTimeAndCommittedWordsForWordTests() {
    var timed = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    XCTAssertEqual(timed.progressLabel, "剩余")
    XCTAssertEqual(timed.progressText(at: start), "30s")
    XCTAssertEqual(timed.progressFraction(at: start), 0)
    timed.insert("a", at: start)
    XCTAssertEqual(timed.progressText(at: start.addingTimeInterval(4.2)), "26s")
    XCTAssertEqual(
      try XCTUnwrap(timed.progressFraction(at: start.addingTimeInterval(4.2))), 0.14, accuracy: 0.001)

    var words = TypingSession(configuration: .words(3), prompt: "amber harbor quiet")
    XCTAssertEqual(words.progressLabel, "进度")
    XCTAssertEqual(words.progressText(at: start), "0/3")
    XCTAssertEqual(words.progressFraction(at: start), 0)
    words.insert("amxer ", at: start)
    XCTAssertEqual(words.progressText(at: start), "1/3")
    XCTAssertEqual(try XCTUnwrap(words.progressFraction(at: start)), 1.0 / 3.0, accuracy: 0.001)
    words = TypingSession(configuration: .words(3), prompt: "amber harbor quiet")
    words.insert("amber harbor quiet", at: start)
    XCTAssertEqual(words.outcome, .completed)
    XCTAssertEqual(words.progressText(at: start), "3/3")
    XCTAssertEqual(words.progressFraction(at: start), 1)
  }

  func testFlashProgressStylesMatchReferenceTimerVisibility() {
    XCTAssertEqual(LiveProgressStyle.flashText.metricStyle, .text)
    XCTAssertEqual(LiveProgressStyle.flashMini.metricStyle, .mini)

    XCTAssertTrue(
      LiveProgressStyle.flashText.showsProgressValue(isTimed: true, remainingSeconds: 30))
    XCTAssertFalse(
      LiveProgressStyle.flashText.showsProgressValue(isTimed: true, remainingSeconds: 29))
    XCTAssertTrue(
      LiveProgressStyle.flashMini.showsProgressValue(isTimed: true, remainingSeconds: 15))
    XCTAssertFalse(
      LiveProgressStyle.flashMini.showsProgressValue(isTimed: true, remainingSeconds: 1))
    XCTAssertTrue(
      LiveProgressStyle.flashText.showsProgressValue(isTimed: true, remainingSeconds: 0))

    XCTAssertTrue(
      LiveProgressStyle.flashText.showsProgressValue(isTimed: false, remainingSeconds: 29))
    XCTAssertTrue(LiveProgressStyle.flashMini.showsProgressValue(isTimed: false, remainingSeconds: nil))
    XCTAssertTrue(LiveProgressStyle.text.showsProgressValue(isTimed: true, remainingSeconds: 29))
  }

  func testCaretOffStyleDoesNotDrawEitherPromptOrPaceMarker() {
    XCTAssertFalse(TypingCaretStyle.off.drawsMarker)
    XCTAssertTrue(TypingCaretStyle.bar.drawsMarker)
    XCTAssertTrue(TypingCaretStyle.underline.drawsMarker)
    XCTAssertTrue(TypingCaretStyle.block.drawsMarker)
  }

  func testPromptTextColorPolicyMapsThemeOptionsWithoutTouchingErrorStates() {
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .completed, flipsCompletionAndFuture: false, usesAccentForCompleted: false), .primary)
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .future, flipsCompletionAndFuture: false, usesAccentForCompleted: false), .secondary)
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .completed, flipsCompletionAndFuture: true, usesAccentForCompleted: false), .secondary)
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .future, flipsCompletionAndFuture: true, usesAccentForCompleted: false), .primary)
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .completed, flipsCompletionAndFuture: false, usesAccentForCompleted: true), .accent)
    XCTAssertEqual(
      PromptTextColorPolicy.tone(
        for: .future, flipsCompletionAndFuture: true, usesAccentForCompleted: true), .accent)
  }

  func testCustomBackgroundPolicyAcceptsOnlySupportedRemoteImagesAndNormalizesFilters() {
    XCTAssertEqual(
      CustomBackgroundURLPolicy.normalizedRemoteURL(" https://images.example.test/sky.webp?theme=night "),
      "https://images.example.test/sky.webp?theme=night")
    XCTAssertEqual(CustomBackgroundURLPolicy.normalizedRemoteURL(""), "")
    XCTAssertNil(CustomBackgroundURLPolicy.normalizedRemoteURL("ftp://images.example.test/sky.jpg"))
    XCTAssertNil(CustomBackgroundURLPolicy.normalizedRemoteURL("https://images.example.test/sky.svg"))
    XCTAssertNil(CustomBackgroundURLPolicy.normalizedRemoteURL("https://images.example.test/sky.jpg'"))

    let filter = CustomBackgroundFilter(blur: -1, brightness: 9, saturation: -2, opacity: 4)
    XCTAssertEqual(filter, .init(blur: 0, brightness: 2, saturation: 0, opacity: 1))
  }

  func testNoSpaceWordTestsKeepTheirCommittedWordProgress() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var session = TypingSession(
      configuration: configuration, prompt: "amberharbor", noSpaceWordEndIndices: [5, 11])

    XCTAssertEqual(session.progressLabel, "进度")
    XCTAssertEqual(session.progressText(at: start), "0/2")
    XCTAssertEqual(session.progressFraction(at: start), 0)

    session.insert("amber", at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.progressText(at: start), "1/2")
    XCTAssertEqual(session.progressFraction(at: start), 0.5)

    session.insert("harbor", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(session.progressText(at: start), "2/2")
    XCTAssertEqual(session.progressFraction(at: start), 1)
  }

  func testQuickEndOnlyFinishesAFullLengthIncorrectLastWordWithoutErrorRules() {
    var ordinary = TypingSession(configuration: .words(2), prompt: "amber harbor")
    ordinary.insert("amber haxxxx", at: start)
    XCTAssertEqual(ordinary.outcome, .active)
    ordinary.insert(" ", at: start)
    XCTAssertEqual(ordinary.outcome, .completed)

    var rules = InputRules(quickEnd: true)
    var quickEnd = TypingSession(configuration: .words(2, rules: rules), prompt: "amber haxxxx")
    quickEnd.insert("amber habxxx", at: start)
    XCTAssertEqual(quickEnd.outcome, .completed)

    rules.stopOnError = true
    var blocked = TypingSession(configuration: .words(2, rules: rules), prompt: "amber haxxxx")
    blocked.insert("amber habxxx", at: start)
    XCTAssertEqual(blocked.outcome, .active)
  }

  func testQuoteAndCustomTestsCompleteAtEndOfPrompt() {
    for mode in [TestMode.quote, .custom] {
      var session = TypingSession(
        configuration: .init(
          mode: mode, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
        prompt: "violet")
      session.insert("violet", at: start)
      XCTAssertEqual(session.outcome, .completed)
    }
  }

  func testZenAcceptsFreeformTextAndFinishesOnlyWhenExplicitlyRequested() {
    var session = TypingSession(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "")
    session.insert("free form\nwith\ttab", forceError: true, at: start)
    XCTAssertEqual(session.typed, "free form\nwith\ttab")
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.promptGlyphs.dropLast().map(\.character), Array(session.typed))
    XCTAssertTrue(session.promptGlyphs.dropLast().allSatisfy { $0.state == .correct })

    session.finishZen(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testZenMinimumBurstChecksSpaceAndNewlineCommittedUserWords() {
    let rules = InputRules(minimumWordBurstWpm: 100, minimumWordBurstMode: .fixed)
    var spaceCommitted = TypingSession(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: rules), prompt: "")
    spaceCommitted.insert("f", at: start)
    spaceCommitted.insert("ree ", at: start.addingTimeInterval(4))
    XCTAssertEqual(spaceCommitted.outcome, .failed)

    var newlineCommitted = TypingSession(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: rules), prompt: "")
    newlineCommitted.insert("f", at: start)
    newlineCommitted.insert("ree\n", at: start.addingTimeInterval(4))
    XCTAssertEqual(newlineCommitted.outcome, .failed)
  }

  func testAbandonOnlyAppliesAfterTypingStartsAndDoesNotProduceCompletedOutcome() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber")
    session.abandon(at: start)
    XCTAssertEqual(session.outcome, .active)
    XCTAssertNil(session.result(at: start))

    session.insert("a", at: start)
    session.abandon(at: start.addingTimeInterval(4))
    XCTAssertEqual(session.outcome, .abandoned)
    XCTAssertEqual(session.result(at: start.addingTimeInterval(4))?.outcome, .abandoned)
  }

  func testBailoutProducesAnUnsavedResultAfterTypingStarts() throws {
    var session = TypingSession(configuration: .timed(seconds: 900), prompt: "amber harbor")
    session.insert("amber", at: start)
    session.bailOut(at: start.addingTimeInterval(4))

    let result = try XCTUnwrap(session.result(at: start.addingTimeInterval(4)))
    XCTAssertEqual(session.outcome, .bailedOut)
    XCTAssertEqual(result.outcome, .bailedOut)
    XCTAssertEqual(result.typedCharacterCount, 5)
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: result.outcome, enabled: true))
  }

  func testMasterFailsOnFirstMistake() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .master), prompt: "amber")
    session.insert("x", at: start)
    XCTAssertEqual(session.outcome, .failed)
  }

  func testMultiCharacterInsertionDefersDifficultyUntilTheFinalCharacter() {
    var master = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .master), prompt: "amber")
    master.insertBatch("xmber", at: start)
    XCTAssertEqual(master.typed, "xmber")
    XCTAssertEqual(master.errors, 1)
    XCTAssertEqual(master.outcome, .active)

    var expert = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .expert), prompt: "amber bay")
    expert.insertBatch("am x", at: start)
    XCTAssertEqual(expert.typed, "am x")
    XCTAssertEqual(expert.outcome, .active)
  }

  func testExpertFailsWhenIncorrectWordIsCommitted() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .expert), prompt: "amber harbor")
    session.insert("amxer ", at: start)
    XCTAssertEqual(session.outcome, .failed)

    var incomplete = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .expert), prompt: "amber harbor")
    incomplete.insert("am ", at: start)
    XCTAssertEqual(incomplete.outcome, .failed)
  }

  func testNoSpaceExpertFailsAtTheOriginalWordBoundary() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .expert, rules: .init(),
      modifiers: [.noSpaces])
    var incorrect = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")
    incorrect.insert("amxer", at: start)
    XCTAssertEqual(incorrect.outcome, .failed)

    var correct = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")
    correct.insert("amber", at: start)
    XCTAssertEqual(correct.outcome, .active)
  }

  func testStopOnErrorRejectsIncorrectCharacter() {
    var rules = InputRules()
    rules.stopOnError = true
    var session = TypingSession(configuration: .timed(seconds: 30, rules: rules), prompt: "amber")
    session.insert("x", at: start)
    XCTAssertEqual(session.typed, "")
  }

  func testStopOnErrorWordBlocksOnlyTheIncorrectWordCommit() {
    let rules = InputRules(stopOnErrorMode: .word)
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "amber bay")
    session.insert("amxer ", at: start)
    XCTAssertEqual(session.typed, "amxer")

    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert("ber ", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "amber ")
  }

  func testNormalSpaceCommitsAnIncompleteWordAndAdvancesToTheNextTargetWord() {
    var session = TypingSession(
      configuration: .words(3, rules: .init(freedomMode: true)), prompt: "amber bay cedar")

    session.insert("am ", at: start)

    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.progressText(at: start), "1/3")
    XCTAssertEqual(
      Array(session.promptGlyphs.prefix(6).map(\.state)),
      [.correct, .correct, .incorrect, .incorrect, .incorrect, .incorrect])
    XCTAssertEqual(session.promptGlyphs[6].state, .current)
    XCTAssertEqual(session.completedPromptCharacterIndices, Set(0..<5))

    session.insert("bay ", at: start.addingTimeInterval(1))

    XCTAssertEqual(session.nextExpectedCharacter, "c")
    XCTAssertEqual(session.completedWordCount, 2)
    XCTAssertEqual(
      session.wordReviews,
      [
        .init(index: 0, target: "amber", typed: "am"),
        .init(index: 1, target: "bay", typed: "bay"),
      ])

    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.nextExpectedCharacter, " ")
    session.deleteBackward(at: start.addingTimeInterval(2))
    session.deleteBackward(at: start.addingTimeInterval(2))
    session.deleteBackward(at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(session.nextExpectedCharacter, "b")
  }

  func testNewlineCommitsAnIncompleteCustomTextWordAndAdvancesToTheNextLine() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber\nbay")

    session.insert("am\n", at: start)

    XCTAssertEqual(session.typed, "am\n")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews, [.init(index: 0, target: "amber", typed: "am")])

    session.insert("bay", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testLeadingNewlineInNormalModeCommitsAnEmptyCustomTextWord() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber\nbay")

    session.insert("\n", at: start)

    XCTAssertEqual(session.typed, "\n")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews, [.init(index: 0, target: "amber", typed: "")])
  }

  func testCustomWordLimitFinishesOnTheFinalNewlineDelimitedWord() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: 2, difficulty: .normal, rules: .init(),
        customTextCompletion: .words),
      prompt: "amber\nbay")

    session.insert("amber\nbay", at: start)

    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 2)
  }

  func testVisuallyEquivalentPunctuationNormalizesToThePromptCharacter() {
    let target = "“don’t”—go, now"
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: target)

    session.insert("\"don't\"-go‚ now", at: start)

    XCTAssertEqual(session.typed, target)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testEllipsisExpandsToPeriodsOnlyWhenThePromptDoesNotUseAnEllipsis() {
    var periodPrompt = TypingSession(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "wait...")
    periodPrompt.insertBatch("wait…", at: start)
    XCTAssertEqual(periodPrompt.typed, "wait...")
    XCTAssertEqual(periodPrompt.errors, 0)
    XCTAssertEqual(periodPrompt.outcome, .completed)

    var ellipsisPrompt = TypingSession(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "wait…")
    ellipsisPrompt.insertBatch("wait…", at: start)
    XCTAssertEqual(ellipsisPrompt.typed, "wait…")
    XCTAssertEqual(ellipsisPrompt.errors, 0)
    XCTAssertEqual(ellipsisPrompt.outcome, .completed)
  }

  func testNormalSpaceCompletesAnIncompleteFiniteFinalWord() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")

    session.insert("am ", at: start)

    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.typed, "am ")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.wordReviews, [.init(index: 0, target: "amber", typed: "am")])
  }

  func testFiniteCustomTextWaitsForAnIncorrectFinalWordToBeCommitted() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")

    session.insert("axxxx", at: start)

    XCTAssertEqual(session.outcome, .active)
    XCTAssertEqual(session.errors, 4)

    session.insert(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.outcome, .completed)
  }

  func testExtraLettersRemainInTheCurrentWordUntilSpaceSubmitsIt() {
    var session = TypingSession(
      configuration: .words(2), prompt: "amber bay")

    session.insert("amberx", at: start)

    XCTAssertEqual(session.typed, "amberx")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.nextExpectedCharacter, " ")
    XCTAssertEqual(session.promptGlyphs[5].state, .current)
    XCTAssertEqual(session.promptGlyphs.last, .init(character: "x", state: .extra))

    session.insert(" ", at: start.addingTimeInterval(1))

    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
    XCTAssertEqual(session.completedWordCount, 1)
    XCTAssertEqual(session.wordReviews, [.init(index: 0, target: "amber", typed: "amberx")])
  }

  func testSpaceDelimitedWordInputCapsExtrasButStillAcceptsTheCommitSeparator() {
    var session = TypingSession(
      configuration: .words(2), prompt: "a b")

    session.insert("a" + String(repeating: "x", count: 21), at: start)
    session.insert("y", at: start)

    XCTAssertEqual(session.typed, "a" + String(repeating: "x", count: 21))
    XCTAssertEqual(session.errors, 21)
    XCTAssertEqual(session.nextExpectedCharacter, " ")

    session.insert(" ", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.errors, 21)
    XCTAssertEqual(session.nextExpectedCharacter, "b")
  }

  func testHideExtraLettersOnlyHidesTheGlyphWithoutRejectingOrUnscoringInput() {
    let rules = InputRules(hideExtraLetters: true)
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "a")

    session.insert("ax", at: start)

    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.promptGlyphs.last, .init(character: "x", state: .hidden))
  }

  func testNoSpaceRejectsDirectWhitespaceWithoutRecordingAnError() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: "amber harbor")

    session.insert("am \u{3000}", at: start)

    XCTAssertEqual(session.typed, "am")
    XCTAssertEqual(session.errors, 0)
  }

  func testNoSpaceStopOnErrorWordBlocksIncorrectWordBoundaryUntilCorrected() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(stopOnErrorMode: .word), modifiers: [.noSpaces])
    var session = TestSessionFactory.make(configuration: configuration, customText: "amber harbor")

    session.insert("amxer", at: start)
    XCTAssertEqual(session.typed, "amxe")

    session.deleteBackward(at: start.addingTimeInterval(1))
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert("ber", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "amber")
  }

  func testDeleteOnErrorLetterCostsOneAcceptedCharacter() {
    let rules = InputRules(deleteOnErrorMode: .letter)
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "amber")
    session.insert("am", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "a")
    XCTAssertEqual(session.errors, 0)
    session.insert("mber", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "amber")
  }

  func testDeleteOnErrorWordClearsTheActiveWord() {
    let rules = InputRules(deleteOnErrorMode: .word)
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: rules), prompt: "amber")
    session.insert("am", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "")
    session.insert("amber", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.typed, "amber")
  }

  func testHardDeleteOnErrorReturnsToPreviousWordAtWordStart() {
    var letterHard = TypingSession(
      configuration: .timed(
        seconds: 30, rules: .init(deleteOnErrorMode: .letterHard)), prompt: "amber bay")
    letterHard.insert("amber ", at: start)
    letterHard.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(letterHard.typed, "amber")

    var wordHard = TypingSession(
      configuration: .timed(
        seconds: 30, rules: .init(deleteOnErrorMode: .wordHard)), prompt: "amber bay")
    wordHard.insert("amber ", at: start)
    wordHard.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(wordHard.typed, "")
  }

  func testErrorHandlingModesDecodeLegacyBooleanAndRemainMutuallyExclusive() throws {
    let legacy = """
      {"strictSpace":false,"stopOnError":true,"deleteOnError":false}
      """
    let decoded = try JSONDecoder().decode(InputRules.self, from: Data(legacy.utf8))
    XCTAssertEqual(decoded.stopOnErrorMode, .letter)
    XCTAssertTrue(decoded.stopOnError)

    let conflicting = InputRules(stopOnErrorMode: .word, deleteOnErrorMode: .wordHard)
    XCTAssertEqual(conflicting.stopOnErrorMode, .word)
    XCTAssertEqual(conflicting.deleteOnErrorMode, .off)
  }

  func testConfidenceModePreventsReturningToAnIncorrectPreviousWord() {
    let rules = InputRules(confidenceMode: .on)
    var session = TypingSession(
      configuration: .words(3, rules: rules), prompt: "amber bay cedar")
    session.insert("amber x ", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "amber x ")

    session.insert("b", at: start.addingTimeInterval(2))
    session.deleteBackward(at: start.addingTimeInterval(3))
    XCTAssertEqual(session.typed, "amber x ")

    var correctPreviousWord = TypingSession(
      configuration: .words(2, rules: rules), prompt: "amber bay")
    correctPreviousWord.insert("amber ", at: start)
    correctPreviousWord.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(correctPreviousWord.typed, "amber ")
  }

  func testMaximumConfidenceModeDisablesBackspaceAndNormalizesConflicts() {
    let conflicting = InputRules(
      stopOnError: true, deleteOnError: true, freedomMode: true, confidenceMode: .maximum)
    let configuration = TestConfiguration.words(1, rules: conflicting)
    XCTAssertEqual(configuration.rules.confidenceMode, .maximum)
    XCTAssertFalse(configuration.rules.stopOnError)
    XCTAssertFalse(configuration.rules.deleteOnError)
    XCTAssertFalse(configuration.rules.freedomMode)

    var session = TypingSession(configuration: configuration, prompt: "amber")
    session.insert("am", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "am")
  }

  func testQuickRestartKeyMatchesOnlyItsConfiguredNativeKey() {
    XCTAssertTrue(QuickRestartKey.escape.matches(charactersIgnoringModifiers: "\u{1B}"))
    XCTAssertTrue(QuickRestartKey.tab.matches(charactersIgnoringModifiers: "\t"))
    XCTAssertTrue(QuickRestartKey.enter.matches(charactersIgnoringModifiers: "\r"))
    XCTAssertTrue(QuickRestartKey.enter.matches(charactersIgnoringModifiers: "\n"))
    XCTAssertFalse(QuickRestartKey.off.matches(charactersIgnoringModifiers: "\u{1B}"))
    XCTAssertFalse(QuickRestartKey.tab.matches(charactersIgnoringModifiers: "\r"))
  }

  func testQuickRestartSafetyRequiresShiftAtReferenceLongTestThresholds() {
    XCTAssertFalse(QuickRestartSafetyPolicy.requiresShift(for: .words(999)))
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: .words(1_000)))
    XCTAssertFalse(QuickRestartSafetyPolicy.requiresShift(for: .timed(seconds: 895)))
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: .timed(seconds: 900)))

    let customTime = TestConfiguration(
      mode: .custom, duration: 900, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time)
    let customSections = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .sections, customTextSectionLimit: 1_000)
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: customTime))
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: customSections))
    let savedLongText = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .finish)
    XCTAssertFalse(QuickRestartSafetyPolicy.requiresShift(for: savedLongText))
    XCTAssertTrue(QuickRestartSafetyPolicy.requiresShift(for: savedLongText, savedLongText: true))
  }

  func testCommandBailoutPolicyMatchesReferenceAvailability() {
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: .timed(seconds: 3_600)))
    XCTAssertFalse(CommandBailoutPolicy.isAvailable(for: .timed(seconds: 900)))
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: .words(5_000)))
    XCTAssertFalse(CommandBailoutPolicy.isAvailable(for: .words(1_000)))
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: .init(
      mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())))
    XCTAssertTrue(CommandBailoutPolicy.isAvailable(for: .init(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      savedLongText: true))
  }

  func testThemeCommandCatalogPrioritizesFavoritesAndRoutesSelections() {
    let customID = UUID(uuidString: "8A692C7B-0F0F-42C6-916D-A5A82F0B99FE")!
    let custom = CustomThemeDefinition(
      id: customID, name: "Dawn", background: .init(red: 0.1, green: 0.2, blue: 0.3),
      panel: .init(red: 0.2, green: 0.3, blue: 0.4), accent: .init(red: 0.7, green: 0.4, blue: 0.2),
      prefersDark: true)
    let favoriteID = ThemeFavoritePolicy.customID(for: customID)

    let items = ThemeCommandCatalog.items(
      builtInThemes: [.paper, .midnight], customThemes: [custom], favoriteThemeIDs: [favoriteID])

    XCTAssertEqual(items.first?.id, ThemeCommandCatalog.identifier(for: .custom(customID)))
    XCTAssertEqual(items.first?.subtitle, "自定义主题 · 已收藏")
    XCTAssertEqual(
      ThemeCommandCatalog.target(for: ThemeCommandCatalog.identifier(for: .builtIn(.midnight))),
      .builtIn(.midnight))
    XCTAssertEqual(
      ThemeCommandCatalog.target(for: ThemeCommandCatalog.identifier(for: .custom(customID))),
      .custom(customID))
    XCTAssertNil(ThemeCommandCatalog.target(for: "theme.custom.not-a-uuid"))
  }

  func testPresetCommandCatalogDescribesAndRoutesLocalPresets() {
    let id = UUID(uuidString: "E5D0D867-373F-4B15-B2ED-4F05919AE94B")!
    let preset = SavedTestPreset(configuration: .timed(seconds: 60), quoteID: nil, customText: nil)

    let items = PresetCommandCatalog.items(
      presets: [.init(id: id, name: "冲刺一分钟", definition: preset)])

    XCTAssertEqual(items.first?.title, "应用预设：冲刺一分钟")
    XCTAssertEqual(items.first?.subtitle, "时间 · 60 秒")
    XCTAssertEqual(items.first?.id, "preset.e5d0d867-373f-4b15-b2ed-4f05919ae94b")
    XCTAssertEqual(PresetCommandCatalog.presetID(for: items[0].id), id)
    XCTAssertNil(PresetCommandCatalog.presetID(for: "preset.invalid"))
  }

  func testChallengeCommandCatalogDescribesAndRoutesLibraryChallenges() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "calm-thirty"))

    let items = ChallengeCommandCatalog.items(challenges: [challenge])

    XCTAssertEqual(items.first?.title, "加载挑战：沉稳三十")
    XCTAssertEqual(items.first?.id, "challenge.calm-thirty")
    XCTAssertEqual(ChallengeCommandCatalog.challengeID(for: items[0].id), "calm-thirty")
    XCTAssertNil(ChallengeCommandCatalog.challengeID(for: "challenge."))
  }

  func testQuoteFavoriteCommandOnlyAppearsForCurrentQuoteAndReflectsState() {
    XCTAssertNil(QuoteFavoriteCommand.item(currentQuoteID: nil, isFavorite: false))
    XCTAssertEqual(
      QuoteFavoriteCommand.item(currentQuoteID: "craft", isFavorite: false)?.title,
      "收藏当前引语")
    XCTAssertEqual(
      QuoteFavoriteCommand.item(currentQuoteID: "craft", isFavorite: true)?.title,
      "取消收藏当前引语")
  }

  func testClearCurrentWordOnErrorModifierKeepsCompletedWordsAndReplayInSync() {
    var session = TypingSession(
      configuration: .words(2).with(modifiers: [.clearCurrentWordOnError]),
      prompt: "amber bay")
    session.insert("amber b", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "amber ")
    XCTAssertEqual(session.errors, 0)

    session.insert("bay", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(
      TypingReplay.typedText(events: session.result()?.replayEvents ?? [], through: 2), "amber bay")
  }

  func testClearCurrentWordOnErrorModifierDoesNotClearChineseInput() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese)
        .with(modifiers: [.clearCurrentWordOnError]),
      prompt: "你好")
    session.insert("你", at: start)
    session.insert("x", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "你x")
  }

  func testTimeWarningsUseTheSelectedCountdownOffsetAndNeverRepeatWithinOneSecond() {
    XCTAssertTrue(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 10, previousSecond: 11, offset: .tenSeconds))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 10, previousSecond: 10, offset: .tenSeconds))
    XCTAssertTrue(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 1, previousSecond: 2, offset: .oneSecond))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 4, previousSecond: 5, offset: .fiveSeconds))
    XCTAssertFalse(
      TimeWarningPolicy.shouldPlay(remainingSeconds: 5, previousSecond: 6, offset: .off))
  }

  func testMinimumWordBurstFailsForEverySlowCommittedWordAndCanBeDisabled() {
    var rules = InputRules(minimumWordBurstWpm: 60)
    var slow = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    slow.insert("a", at: start)
    slow.insert("mber", at: start.addingTimeInterval(8))
    slow.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(slow.outcome, .failed)
    XCTAssertEqual(slow.result()?.outcome, .failed)

    var incorrect = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    incorrect.insert("axber", at: start)
    incorrect.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(incorrect.outcome, .failed)

    rules.minimumWordBurstWpm = 0
    var disabled = TypingSession(configuration: .words(2, rules: rules), prompt: "amber harbor")
    disabled.insert("a", at: start)
    disabled.insert("mber", at: start.addingTimeInterval(8))
    disabled.insert(" ", at: start.addingTimeInterval(9))
    XCTAssertEqual(disabled.outcome, .active)
  }

  func testMultiCharacterInsertionDefersMinimumBurstUntilTheFinalCharacter() {
    let rules = InputRules(minimumWordBurstWpm: 60)
    var session = TypingSession(
      configuration: .words(2, rules: rules), prompt: "amber bay")
    session.insert("a", at: start)
    session.insertBatch(" b", at: start.addingTimeInterval(9))

    XCTAssertEqual(session.typed, "a b")
    XCTAssertEqual(session.outcome, .active)
  }

  func testFlexibleMinimumWordBurstRelaxesForLongerTargetWords() {
    XCTAssertEqual(
      MinimumWordBurstPolicy.threshold(baseWpm: 100, mode: .fixed, wordLength: 9), 100)
    XCTAssertEqual(
      MinimumWordBurstPolicy.threshold(baseWpm: 100, mode: .flex, wordLength: 3), 100)
    XCTAssertEqual(
      MinimumWordBurstPolicy.threshold(baseWpm: 100, mode: .flex, wordLength: 9), 70)

    var fixed = TypingSession(
      configuration: .words(
        2, rules: .init(minimumWordBurstWpm: 100, minimumWordBurstMode: .fixed)),
      prompt: "wonderful harbor")
    fixed.insert("w", at: start)
    fixed.insert("onderful ", at: start.addingTimeInterval(1.5))
    XCTAssertEqual(fixed.outcome, .failed)

    var flexible = TypingSession(
      configuration: .words(
        2, rules: .init(minimumWordBurstWpm: 100, minimumWordBurstMode: .flex)),
      prompt: "wonderful harbor")
    flexible.insert("w", at: start)
    flexible.insert("onderful ", at: start.addingTimeInterval(1.5))
    XCTAssertEqual(flexible.outcome, .active)
  }

  func testNoSpaceMinimumWordBurstCommitsAtEveryOriginalWordBoundary() {
    let rules = InputRules(minimumWordBurstWpm: 60, minimumWordBurstMode: .fixed)
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: rules,
      modifiers: [.noSpaces])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")

    XCTAssertEqual(session.prompt, "amberharbor")
    session.insert("a", at: start)
    session.insert("mber", at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.outcome, .active, "the first original word should commit without a space")

    session.insert("h", at: start.addingTimeInterval(1))
    session.insert("arbor", at: start.addingTimeInterval(9))
    XCTAssertEqual(session.outcome, .failed, "the second original word should independently check min burst")
  }

  func testNoSpaceFlexibleMinimumWordBurstUsesTheOriginalWordLength() {
    let fixedConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(minimumWordBurstWpm: 100, minimumWordBurstMode: .fixed),
      modifiers: [.noSpaces])
    var fixed = TestSessionFactory.make(
      configuration: fixedConfiguration, customText: "wonderful harbor")
    fixed.insert("w", at: start)
    fixed.insert("onderful", at: start.addingTimeInterval(1.5))
    XCTAssertEqual(fixed.outcome, .failed)

    let flexibleConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal,
      rules: .init(minimumWordBurstWpm: 100, minimumWordBurstMode: .flex),
      modifiers: [.noSpaces])
    var flexible = TestSessionFactory.make(
      configuration: flexibleConfiguration, customText: "wonderful harbor")
    flexible.insert("w", at: start)
    flexible.insert("onderful", at: start.addingTimeInterval(1.5))
    XCTAssertEqual(flexible.outcome, .active)
  }

  func testNoSpaceRepeatingCustomTextKeepsWordBoundariesWithoutReintroducingSpaces() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time, modifiers: [.noSpaces])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")

    XCTAssertEqual(session.prompt, "amberharboramberharbor")
    session.insert(session.prompt, at: start)
    session.insert("a", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.prompt, "amberharboramberharboramberharbor")
    XCTAssertFalse(session.prompt.contains(" "))
  }

  func testNoSpaceBoundaryPolicyTracksFlattenedWordsAfterBackwardsTransform() {
    let modifiers: [TestModifier] = [.noSpaces, .backwards]
    let prompt = TestModifierPolicy.transformed("amber bay", modifiers: modifiers)
    XCTAssertEqual(prompt, "yabrebma")
    let lengths =
      NoSpaceWordBoundaryPolicy.wordLengths(
        source: "amber bay", modifiers: modifiers, transformedPrompt: prompt)
    XCTAssertEqual(lengths, [3, 5])
    XCTAssertEqual(
      NoSpaceWordBoundaryPolicy.targetWords(for: lengths, in: prompt), ["yab", "rebma"])
  }

  func testNoSpaceResultHistoryAndPracticeKeepOriginalWordBoundaries() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")

    session.insert("a", at: start)
    session.insert("xber", at: start.addingTimeInterval(0.5))
    session.insert("h", at: start.addingTimeInterval(1))
    session.insert("arbor", at: start.addingTimeInterval(1.4))

    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(
      session.wordReviews,
      [
        .init(index: 0, target: "amber", typed: "axber"),
        .init(index: 1, target: "harbor", typed: "harbor"),
      ])
    XCTAssertEqual(session.wordBurstHistory, [144, 210])
    XCTAssertEqual(session.missedWordErrorCounts, [.init(word: "amber", count: 1)])
    XCTAssertEqual(session.missedWordErrorCountsByWord, [1, 0])
    XCTAssertEqual(session.missedWords, ["amber"])
  }

  func testNoSpaceRepeatingCustomTextExtendsItsResultWordSegments() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time, modifiers: [.noSpaces])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor")

    session.insert(session.prompt, at: start)
    session.insert("a", at: start.addingTimeInterval(1))

    XCTAssertEqual(session.wordReviews.map(\.target), ["amber", "harbor", "amber", "harbor", "amber"])
    XCTAssertEqual(session.wordReviews.last?.typed, "a")
  }

  func testNoSpaceBackwardsResultHistoryUsesRenderedWordSlices() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces, .backwards])
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber bay")

    XCTAssertEqual(session.prompt, "yabrebma")
    session.insert("y", at: start)
    session.insert("ab", at: start.addingTimeInterval(0.5))
    session.insert("r", at: start.addingTimeInterval(1))
    session.insert("ebma", at: start.addingTimeInterval(1.5))

    XCTAssertEqual(session.wordReviews.map(\.target), ["yab", "rebma"])
    XCTAssertEqual(session.wordReviews.map(\.typed), ["yab", "rebma"])
  }

  func testMinimumAccuracyFailsFiniteTestsOnlyWhenCompletionWouldOtherwiseSucceed() {
    let rules = InputRules(minimumAccuracy: 90)
    var failed = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    failed.insert("axxer bay ", at: start)
    XCTAssertEqual(failed.accuracy, 80)
    XCTAssertEqual(failed.outcome, .failed)
    XCTAssertEqual(failed.result()?.outcome, .failed)

    var passing = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    passing.insert("amber bay", at: start)
    XCTAssertEqual(passing.outcome, .completed)

    var disabled = TypingSession(configuration: .words(2, rules: .init()), prompt: "amber bay")
    disabled.insert("axxer bay ", at: start)
    XCTAssertEqual(disabled.outcome, .completed)
  }

  func testMinimumWpmFailsFiniteTestsOnlyWhenFinalPaceIsTooLow() {
    let rules = InputRules(minimumWpm: 10)
    var slow = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    slow.insert("a", at: start)
    slow.insert("mber bay", at: start.addingTimeInterval(60))
    XCTAssertEqual(slow.outcome, .failed)

    var fast = TypingSession(configuration: .words(2, rules: rules), prompt: "amber bay")
    fast.insert("amber bay", at: start)
    XCTAssertEqual(fast.outcome, .completed)
  }

  func testFreedomModeOnlyAllowsDeletingCommittedCorrectWordsWhenEnabled() {
    let prompt = "amber harbor"
    var protectedSession = TypingSession(configuration: .words(2), prompt: prompt)
    protectedSession.insert("amber ", at: start)
    protectedSession.deleteBackward()
    XCTAssertEqual(protectedSession.typed, "amber ")

    var incorrectWordSession = TypingSession(configuration: .words(2), prompt: prompt)
    incorrectWordSession.insert("amberx ", at: start)
    incorrectWordSession.deleteBackward()
    XCTAssertEqual(incorrectWordSession.typed, "amberx")

    var freeSession = TypingSession(
      configuration: .words(2, rules: .init(freedomMode: true)), prompt: prompt)
    freeSession.insert("amber ", at: start)
    freeSession.deleteBackward()
    XCTAssertEqual(freeSession.typed, "amber")
  }

  func testWordBackwardDeletionClearsTheCurrentWordAndRespectsWordProtection() {
    let prompt = "amber harbor"
    var currentWord = TypingSession(configuration: .words(2), prompt: prompt)
    currentWord.insert("amber har", at: start)
    currentWord.deleteWordBackward()
    XCTAssertEqual(currentWord.typed, "amber ")

    var protected = TypingSession(configuration: .words(2), prompt: prompt)
    protected.insert("amber ", at: start)
    protected.deleteWordBackward()
    XCTAssertEqual(protected.typed, "amber ")

    var incorrect = TypingSession(configuration: .words(2), prompt: prompt)
    incorrect.insert("amberx ", at: start)
    incorrect.deleteWordBackward()
    XCTAssertTrue(incorrect.typed.isEmpty)

    var free = TypingSession(
      configuration: .words(2, rules: .init(freedomMode: true)), prompt: prompt)
    free.insert("amber ", at: start)
    free.deleteWordBackward()
    XCTAssertTrue(free.typed.isEmpty)
  }

  func testBlindModeKeepsInputForMetricsWithoutChangingValidation() {
    var session = TypingSession(
      configuration: .timed(seconds: 30, rules: .init(blindMode: true)), prompt: "amber")
    session.insert("ax", at: start)
    XCTAssertEqual(session.typed, "ax")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.accuracy, 50)
  }

  func testReferenceSpaceNormalizationAndLeadingSeparatorRules() {
    var normal = TypingSession(
      configuration: .timed(seconds: 30), prompt: "amber harbor")
    normal.insert("\u{3000}", at: start)
    XCTAssertEqual(normal.typed, "")
    XCTAssertEqual(normal.errors, 0)
    normal.insert("amber\u{3000}\u{3000}harbor", at: start)
    XCTAssertEqual(normal.typed, "amber harbor")
    XCTAssertEqual(normal.errors, 0)

    let strictRules = InputRules(strictSpace: true)
    var strict = TypingSession(
      configuration: .timed(seconds: 30, rules: strictRules), prompt: "amber harbor")
    strict.insert("\u{3000}", at: start)
    XCTAssertEqual(strict.typed, " ")
    XCTAssertEqual(strict.errors, 1)

    var expert = TypingSession(
      configuration: .timed(seconds: 30, difficulty: .expert), prompt: "amber harbor")
    expert.insert(" ", at: start)
    XCTAssertEqual(expert.typed, " ")
    XCTAssertEqual(expert.outcome, .active)
  }

  func testStatsUseCorrectCharactersAndFixedClock() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber")
    session.insert("amxzr", at: start)
    XCTAssertEqual(session.errors, 2)
    XCTAssertEqual(session.accuracy, 60)
    XCTAssertEqual(session.wpm(at: start.addingTimeInterval(12)), 3)
    XCTAssertEqual(session.rawWpm(at: start.addingTimeInterval(12)), 5)
  }

  func testBurstUsesAcceptedCharactersFromTheCurrentOrLatestCommittedWord() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    session.insert("a", at: start)
    session.insert("m", at: start.addingTimeInterval(0.1))
    XCTAssertEqual(session.burstWpm, 360)

    session.insert("ber ", at: start.addingTimeInterval(0.5))
    XCTAssertEqual(session.burstWpm, 144)

    session.insert("h", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.burstWpm, 144)
    session.insert("a", at: start.addingTimeInterval(1.1))
    XCTAssertEqual(session.burstWpm, 360)
  }

  func testRecentWordBurstHistoryKeepsTheLatestEightCommittedWords() {
    var session = TypingSession(
      configuration: .timed(seconds: 60),
      prompt: Array(repeating: "a", count: 10).joined(separator: " "))
    for index in 0..<10 {
      let wordStart = start.addingTimeInterval(Double(index + 1))
      session.insert("a", at: wordStart)
      session.insert(" ", at: wordStart.addingTimeInterval(0.1))
    }
    XCTAssertEqual(session.recentWordBursts.count, 8)
    XCTAssertTrue(session.recentWordBursts.allSatisfy { $0 > 0 })
  }

  func testWordBurstHistoryTracksAttemptedWordsAndLeavesSingleEventWordsNeutral() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber bay")
    session.insert("a", at: start)
    session.insert("mber ", at: start.addingTimeInterval(0.5))
    session.insert("b", at: start.addingTimeInterval(1))
    session.insert("ay", at: start.addingTimeInterval(1.4))

    XCTAssertEqual(session.wordReviews.count, 2)
    XCTAssertEqual(session.wordBurstHistory, [144, 120])

    var singleEvent = TypingSession(configuration: .timed(seconds: 30), prompt: "amber bay")
    singleEvent.insert("amber ", at: start)
    XCTAssertEqual(singleEvent.wordBurstHistory, [nil])
  }

  func testMissedWordsIncludesOnlyAttemptedIncorrectSpaceDelimitedTargetsWithoutDuplicates() {
    var session = TypingSession(
      configuration: .timed(seconds: 30), prompt: "amber harbor amber quiet")
    session.insert("amber habxxx amber ", at: start)
    XCTAssertEqual(session.missedWords, ["harbor"])

    var partial = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor quiet")
    partial.insert("amx", at: start)
    XCTAssertEqual(partial.missedWords, ["amber"])

    var correctPartial = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    correctPartial.insert("am", at: start)
    XCTAssertTrue(correctPartial.missedWords.isEmpty)

    var chinese = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese), prompt: "晨光窗边")
    chinese.insert("晨x", at: start)
    XCTAssertEqual(chinese.missedWords, ["晨光"])

    var chineseWithPunctuation = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese), prompt: "晨光，窗边纸张")
    chineseWithPunctuation.insert("晨光，窗x", at: start)
    XCTAssertEqual(chineseWithPunctuation.missedWords, ["窗边"])
    XCTAssertEqual(
      WordPracticeText.make(words: chineseWithPunctuation.missedWords, language: .simplifiedChinese),
      "窗边")
    XCTAssertEqual(MissedWordCopyText.make(words: ["晨光", "窗边"]), "晨光 窗边")

    var spanish = TypingSession(
      configuration: .timed(seconds: 30, language: .spanish), prompt: "árbol puerto calma")
    spanish.insert("árbol puertx ", at: start)
    XCTAssertEqual(spanish.missedWords, ["puerto"])
  }

  func testMissedWordsRetainCorrectedInputErrorsForWordAndChinesePractice() {
    var words = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    words.insert("amx", at: start)
    words.deleteBackward(at: start.addingTimeInterval(0.1))
    words.insert("ber harbor", at: start.addingTimeInterval(0.2))

    XCTAssertEqual(words.typed, "amber harbor")
    XCTAssertEqual(words.missedWords, ["amber"])
    XCTAssertTrue(words.wordReviews.first?.hasInputError ?? false)

    var chinese = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese), prompt: "晨光窗边")
    chinese.insert("晨x", at: start)
    chinese.deleteBackward(at: start.addingTimeInterval(0.1))
    chinese.insert("光窗边", at: start.addingTimeInterval(0.2))

    XCTAssertEqual(chinese.typed, "晨光窗边")
    XCTAssertEqual(chinese.missedWords, ["晨光"])

    var deleted = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    deleted.insert("x", at: start)
    deleted.deleteBackward(at: start.addingTimeInterval(0.1))

    XCTAssertTrue(deleted.typed.isEmpty)
    XCTAssertEqual(deleted.missedWords, ["amber"])
    XCTAssertEqual(deleted.wordReviews.first, .init(index: 0, target: "amber", typed: ""))

    var deletedChinese = TypingSession(
      configuration: .timed(seconds: 30, language: .simplifiedChinese), prompt: "晨光窗边")
    deletedChinese.insert("x", at: start)
    deletedChinese.deleteBackward(at: start.addingTimeInterval(0.1))

    XCTAssertTrue(deletedChinese.typed.isEmpty)
    XCTAssertEqual(deletedChinese.missedWords, ["晨光"])

    var repeated = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor")
    repeated.insert("ax", at: start)
    repeated.deleteBackward(at: start.addingTimeInterval(0.1))
    repeated.insert("x", at: start.addingTimeInterval(0.2))

    XCTAssertEqual(repeated.missedWordErrorCounts, [.init(word: "amber", count: 2)])
    let weighted = MissedWordPracticePlan.make(errorCounts: repeated.missedWordErrorCounts)
    XCTAssertEqual(weighted?.selectedWords, ["amber"])
    XCTAssertEqual(weighted?.exerciseWords, ["amber", "amber"])

    let ranked = MissedWordPracticePlan.make(errorCounts: [
      .init(word: "harbor", count: 1),
      .init(word: "amber", count: 3),
      .init(word: "cabin", count: 2),
    ])
    XCTAssertEqual(ranked?.selectedWords, ["amber", "cabin", "harbor"])
    XCTAssertEqual(ranked?.exerciseWords, ["amber", "amber", "amber", "cabin", "cabin", "harbor"])

    let capped = MissedWordPracticePlan.make(errorCounts: (0...20).map {
      .init(word: "word\($0)", count: 1)
    })
    XCTAssertEqual(capped?.selectedWords.count, MissedWordPracticePlan.maximumSelectedWords)
  }

  func testWordReviewsPairOnlyAttemptedWordsWithTheirTargetAndTypedValue() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "amber harbor quiet")
    session.insert("amber habxxx ", at: start)

    XCTAssertEqual(
      session.wordReviews,
      [
        .init(index: 0, target: "amber", typed: "amber"),
        .init(index: 1, target: "harbor", typed: "habxxx"),
      ])
    XCTAssertTrue(session.wordReviews[0].isCorrect)
    XCTAssertFalse(session.wordReviews[1].isCorrect)
  }

  func testKeyboardGuideHighlightsOnlySupportedNextKeys() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "a 1，")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "home-0")
    session.insert("a", at: start)
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "space")
    session.insert(" ", at: start)
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter), "number-0")
    session.insert("1", at: start)
    XCTAssertNil(KeyboardGuideModel.highlightedKey(for: session.nextExpectedCharacter))
  }

  func testKeyboardGuideModesChooseStaticReactiveAndNextHighlights() {
    XCTAssertNil(KeyboardGuideMode.off.highlightedCharacter(
      nextCharacter: "n", recentCharacter: "r"))
    XCTAssertNil(KeyboardGuideMode.staticGuide.highlightedCharacter(
      nextCharacter: "n", recentCharacter: "r"))
    XCTAssertEqual(KeyboardGuideMode.react.highlightedCharacter(
      nextCharacter: "n", recentCharacter: "r"), "r")
    XCTAssertEqual(KeyboardGuideMode.next.highlightedCharacter(
      nextCharacter: "n", recentCharacter: "r"), "n")
  }

  func testKeyboardGuideScaleMatchesReferenceRangeAndStep() {
    XCTAssertEqual(KeyboardGuideScalePolicy.normalized(1), 1)
    XCTAssertEqual(KeyboardGuideScalePolicy.normalized(1.234), 1.2)
    XCTAssertEqual(KeyboardGuideScalePolicy.normalized(0.4), 0.5)
    XCTAssertEqual(KeyboardGuideScalePolicy.normalized(3.6), 3.5)
  }

  func testKeyboardGuideLegendsSupportStaticAndDynamicShiftLayers() {
    let key = KeyboardGuideKey("number-0", label: "1")
    XCTAssertEqual(key.legend(style: .lowercase, modifierFlags: [], capsLockEnabled: false), "1")
    XCTAssertEqual(key.legend(style: .uppercase, modifierFlags: [], capsLockEnabled: false), "1")
    XCTAssertEqual(key.legend(style: .blank, modifierFlags: [], capsLockEnabled: false), "")
    XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [], capsLockEnabled: false), "1")
    XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [.shift], capsLockEnabled: false), "!")
    XCTAssertEqual(key.legend(style: .dynamic, modifierFlags: [], capsLockEnabled: true), "1")
    let letter = KeyboardGuideKey("top-0", label: "Q")
    XCTAssertEqual(letter.legend(style: .dynamic, modifierFlags: [], capsLockEnabled: false), "q")
    XCTAssertEqual(letter.legend(style: .dynamic, modifierFlags: [.shift], capsLockEnabled: false), "Q")
  }

  func testKeyboardGuideKeySetsMatchReferenceNumberRowPolicies() {
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: .ansiQwerty, keysMode: .minimal, mode: .staticGuide, nextCharacter: nil).count,
      3)
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: .ansiQwerty, keysMode: .minimal, mode: .next, nextCharacter: "7").count,
      4)
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: .frenchAzerty, keysMode: .minimal, mode: .staticGuide, nextCharacter: nil).count,
      4)
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: .ansiDvorak, keysMode: .minimalNumberRow, mode: .staticGuide, nextCharacter: nil).count,
      4)
    let fullRows = KeyboardGuideModel.displayRows(
      for: .ansiQwerty, keysMode: .full, mode: .staticGuide, nextCharacter: nil)
    XCTAssertEqual(fullRows.count, 4)
    XCTAssertEqual(fullRows[0].first?.id, "escape")
    XCTAssertEqual(
      fullRows[0].first?.legend(style: .uppercase, modifierFlags: [], capsLockEnabled: false),
      "Esc")
    XCTAssertEqual(fullRows[3].first?.id, "left-shift")
    XCTAssertEqual(KeyboardGuideModel.bottomRow(for: .full).map(\.id), [
      "left-control", "left-option", "left-command", "space", "right-command", "right-option",
      "right-control",
    ])
  }

  func testCustomKeyboardGuideLayoutsNormalizeUnicodeRowsAndHighlightKeys() throws {
    let layout = try XCTUnwrap(CustomKeyboardGuideLayoutPolicy.make(
      name: "  Cyrillic  ", numberRow: "123", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС"))
    XCTAssertEqual(layout.name, "Cyrillic")
    XCTAssertEqual(layout.guideRows[1].map(\.label), ["Й", "Ц", "У"])
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: "ы", rows: layout.guideRows),
      layout.guideRows[2][1].id)
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: layout.guideRows, keysMode: .minimal, mode: .staticGuide, nextCharacter: nil).count,
      3)
    XCTAssertEqual(
      KeyboardGuideModel.displayRows(
        for: layout.guideRows, keysMode: .minimal, mode: .next, nextCharacter: "1").count,
      4)
    XCTAssertNil(CustomKeyboardGuideLayoutPolicy.make(
      name: "", numberRow: "123", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС"))
    XCTAssertNil(CustomKeyboardGuideLayoutPolicy.make(
      name: "Broken", numberRow: "", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС"))
    XCTAssertEqual(CustomKeyboardGuideLayoutPolicy.normalizedLayouts([layout, layout]).count, 1)

    let mapping = KeyboardInputLayout.custom.inputMapping(for: layout)
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 12, modifierFlags: [], mapping: mapping), "й")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 12, modifierFlags: [.shift], mapping: mapping), "Й")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 0, modifierFlags: [.shift], mapping: mapping), "Ф")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ы", mapping: mapping), 1)
    XCTAssertNil(KeyboardLayoutEmulator.character(forKeyCode: 12, modifierFlags: [.option], mapping: mapping))
    XCTAssertEqual(KeyboardInputLayout.custom.inputMapping(for: nil), .system)

    let visualOnlyLayout = try XCTUnwrap(CustomKeyboardGuideLayoutPolicy.make(
      name: "Visual only", numberRow: "12345678901234", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС"))
    XCTAssertFalse(visualOnlyLayout.supportsPhysicalInputMapping)
    XCTAssertEqual(KeyboardInputLayout.custom.inputMapping(for: visualOnlyLayout), .system)

    let symbolLayout = try XCTUnwrap(CustomKeyboardGuideLayoutPolicy.make(
      name: "Symbols", numberRow: "12", topRow: "q", homeRow: "a", bottomRow: "z",
      shiftedNumberRow: "!@", shiftedTopRow: "Q", shiftedHomeRow: "A", shiftedBottomRow: "Z"))
    XCTAssertEqual(symbolLayout.guideRows[0][0].shiftedLabel, "!")
    XCTAssertEqual(
      symbolLayout.guideRows[0][0].legend(
        style: .dynamic, modifierFlags: [.shift], capsLockEnabled: false), "!")
    let symbolMapping = KeyboardInputLayout.custom.inputMapping(for: symbolLayout)
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 50, modifierFlags: [.shift], mapping: symbolMapping),
      "!")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "@", mapping: symbolMapping), 18)
    XCTAssertNil(CustomKeyboardGuideLayoutPolicy.make(
      name: "Mismatch", numberRow: "12", topRow: "q", homeRow: "a", bottomRow: "z",
      shiftedNumberRow: "!"))

    let legacy = try JSONDecoder().decode(
      CustomKeyboardGuideLayout.self,
      from: Data("{\"id\":\"A37ACD3C-2E19-4D36-9D41-9BF6189E2A5D\",\"name\":\"Legacy\",\"numberRow\":\"1\",\"topRow\":\"q\",\"homeRow\":\"a\",\"bottomRow\":\"z\"}".utf8))
    XCTAssertNil(legacy.shiftedNumberRow)
  }

  func testSystemKeyboardGuideBuildsCompleteShiftAwarePhysicalRows() throws {
    let rows = try XCTUnwrap(SystemKeyboardGuide.rows { keyCode, shift in
      switch keyCode {
      case 10: nil
      case 12: shift ? "Q" : "q"
      case 18: shift ? "!" : "1"
      default: shift ? "*" : "a"
      }
    })
    XCTAssertEqual(rows.map(\.count), [13, 13, 11, 10])
    XCTAssertEqual(rows[0][1].id, "system-18")
    XCTAssertEqual(rows[0][1].label, "1")
    XCTAssertEqual(rows[0][1].shiftedLabel, "!")
    XCTAssertTrue(rows[0][1].characters.contains("!"))
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "!", rows: rows), "system-18")
    XCTAssertEqual(rows[1][0].label, "q")
    XCTAssertEqual(rows[1][0].shiftedLabel, "Q")
    XCTAssertNil(SystemKeyboardGuide.rows(translate: { keyCode, _ in keyCode == 12 ? nil : "a" }))
    let optionRows = try XCTUnwrap(SystemKeyboardGuide.rows(translateLayer: { keyCode, layer in
      guard keyCode != 10 else { return nil }
      switch layer {
      case .base: return "a"
      case .shift: return "A"
      case .option: return "å"
      case .shiftOption: return "Å"
      }
    }))
    let optionKey = optionRows[0][0]
    XCTAssertTrue(optionKey.characters.contains("å"))
    XCTAssertEqual(
      optionKey.legend(style: .dynamic, modifierFlags: [.option], capsLockEnabled: false), "å")
    XCTAssertEqual(
      optionKey.legend(style: .dynamic, modifierFlags: [.option, .shift], capsLockEnabled: false), "Å")
    XCTAssertEqual(KeyboardGuideLayoutSource.allCases, [.builtIn, .systemInput, .custom])
    if let currentRows = SystemKeyboardGuide.currentRows() {
      XCTAssertTrue([[13, 13, 11, 10], [13, 13, 11, 11]].contains(currentRows.map(\.count)))
      XCTAssertTrue(currentRows.flatMap { $0 }.allSatisfy { !$0.label.isEmpty })
    }
    let isoRows = try XCTUnwrap(SystemKeyboardGuide.rows(
      includesISOSectionKey: true, translate: { _, _ in "a" }))
    XCTAssertEqual(isoRows[3].first?.id, "system-10")
  }

  @MainActor
  func testSystemKeyboardGuideRefreshesOnlyForTheSelectedInputSourceNotification() {
    let monitor = SystemKeyboardGuideMonitor(observesInputSourceChanges: false)
    XCTAssertEqual(monitor.revision, 0)
    monitor.receive(notificationName: "TypebarUnrelatedNotification")
    XCTAssertEqual(monitor.revision, 0)
    monitor.receive(notificationName: SystemKeyboardGuideMonitor.selectedInputSourceChanged.rawValue)
    XCTAssertEqual(monitor.revision, 1)
  }

  func testKeyboardGuideStylesCoverReferenceChoicesWithNativeGeometries() {
    XCTAssertEqual(KeyboardGuideStyle.allCases.map(\.rawValue), [
      "staggered", "alice", "matrix", "split", "split_matrix", "steno", "steno_matrix",
    ])
    XCTAssertEqual(KeyboardGuideStyle.staggered.rowLeadingInset(for: 3), 12)
    XCTAssertEqual(KeyboardGuideStyle.matrix.rowLeadingInset(for: 3), 0)
    XCTAssertTrue(KeyboardGuideStyle.split.usesSplit)
    XCTAssertTrue(KeyboardGuideStyle.alice.usesSplit)
    XCTAssertTrue(KeyboardGuideStyle.steno.isSteno)
    XCTAssertTrue(KeyboardGuideStyle.stenoMatrix.isSteno)

    let stenoRows = KeyboardGuideModel.displayRows(
      for: .ansiQwerty, keysMode: .minimal, mode: .next, nextCharacter: "s", style: .steno)
    XCTAssertEqual(stenoRows.count, 3)
    XCTAssertEqual(stenoRows[0].first?.id, "steno-left-top-0")
    XCTAssertEqual(stenoRows[2].first?.id, "steno-space")
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: "s", layout: .ansiQwerty, style: .steno),
      "steno-left-top-0")
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: " ", layout: .ansiQwerty, style: .steno),
      "steno-space")
    XCTAssertTrue(KeyboardGuideModel.bottomRow(for: .full, style: .steno).isEmpty)
  }

  func testKeyboardGuideUsesTheSelectedLayoutAndSupportsAsciiPunctuation() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .ansiQwerty), "top-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .ansiDvorak), "bottom-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "/", layout: .ansiDvorak), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .ansiDvorak), "number-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "?", layout: .ansiDvorak), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "e", layout: .ansiColemak), "home-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ";", layout: .ansiColemak), "top-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "e", layout: .ansiWorkman), "home-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ";", layout: .ansiWorkman), "top-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "r", layout: .ansiWorkman), "top-2")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "a", layout: .frenchAzerty), "top-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "q", layout: .frenchAzerty), "home-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "é", layout: .frenchAzerty), "number-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "à", layout: .frenchAzerty), "number-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ".", layout: .frenchAzerty), "bottom-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .ansiQwerty), "number-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "_", layout: .frenchAzerty), "number-7")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "，", layout: .ansiDvorak), nil)
  }

  func testGermanQwertzLayoutMapsIsoCharactersAndPhysicalKeyPositions() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "z", layout: .germanQwertz), "top-5")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "y", layout: .germanQwertz), "bottom-1")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ü", layout: .germanQwertz), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "#", layout: .germanQwertz), "home-11")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "'", layout: .germanQwertz), "home-11")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ">", layout: .germanQwertz), "bottom-0")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ";", layout: .germanQwertz), "bottom-8")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ":", layout: .germanQwertz), "bottom-9")
    let numberTwo = KeyboardGuideModel.rows(for: .germanQwertz)[0][1]
    XCTAssertEqual(numberTwo.legend(style: .dynamic, modifierFlags: [.shift], capsLockEnabled: false), "\"")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 16, modifierFlags: [], layout: .germanQwertz), "z")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 6, modifierFlags: [], layout: .germanQwertz), "y")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [], layout: .germanQwertz), "ü")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 10, modifierFlags: [.shift], layout: .germanQwertz), ">")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [.shift], layout: .germanQwertz), "'")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 43, modifierFlags: [.shift], layout: .germanQwertz), ";")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 47, modifierFlags: [.shift], layout: .germanQwertz), ":")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ß", layout: .germanQwertz), 27)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: ">", layout: .germanQwertz), 10)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "#", layout: .germanQwertz), 42)
  }

  func testSwissQwertzLayoutsMapTheirDistinctAccentKeys() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "è", layout: .swissGerman), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "é", layout: .swissGerman), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "è", layout: .swissFrench), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "é", layout: .swissFrench), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ü", layout: .swissFrench), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ö", layout: .swissFrench), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "<", layout: .swissGerman), "bottom-0")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 16, modifierFlags: [], layout: .swissGerman), "z")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 18, modifierFlags: [.shift], layout: .swissGerman), "+")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [.shift], layout: .swissGerman), "è")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 41, modifierFlags: [.shift], layout: .swissGerman), "é")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [], layout: .swissFrench), "è")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [.shift], layout: .swissFrench), "ü")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 41, modifierFlags: [], layout: .swissFrench), "é")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 41, modifierFlags: [.shift], layout: .swissFrench), "ö")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ç", layout: .swissGerman), 21)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "£", layout: .swissFrench), 42)
  }

  func testRegionalQwertyLayoutsMapVisibleSymbolsAndIsoKeys() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "£", layout: .ukQwerty), "number-3")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "#", layout: .ukQwerty), "top-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "~", layout: .ukQwerty), "top-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ñ", layout: .spanishQwerty), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "¿", layout: .spanishQwerty), "number-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ç", layout: .italianQwerty), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "§", layout: .italianQwerty), "home-11")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ">", layout: .italianQwerty), "bottom-0")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 20, modifierFlags: [.shift], layout: .ukQwerty), "£")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [.shift], layout: .ukQwerty), "~")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 41, modifierFlags: [], layout: .spanishQwerty), "ñ")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 24, modifierFlags: [.shift], layout: .spanishQwerty), "¿")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [], layout: .italianQwerty), "è")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [.shift], layout: .italianQwerty), "§")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "@", layout: .ukQwerty), 39)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "Ç", layout: .spanishQwerty), 42)
  }

  func testNordicQwertyMapsScandinavianLettersAndIsoKeys() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "å", layout: .nordicQwerty), "top-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ø", layout: .nordicQwerty), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "Æ", layout: .nordicQwerty), "home-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "^", layout: .nordicQwerty), "top-11")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ">", layout: .nordicQwerty), "bottom-0")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [], layout: .nordicQwerty), "å")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 33, modifierFlags: [.shift], layout: .nordicQwerty), "Å")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 41, modifierFlags: [], layout: .nordicQwerty), "ø")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 39, modifierFlags: [.shift], layout: .nordicQwerty), "Æ")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "Ø", layout: .nordicQwerty), 41)
    XCTAssertEqual(KeyboardInputLayout.nordicQwerty.emulatedLayout, .nordicQwerty)
  }

  @MainActor
  func testNordicQwertyPersistsAsGuideInputAndLayoutFluidChoice() {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.keyboardLayout = .nordicQwerty
    settings.keyboardInputLayout = .nordicQwerty
    settings.layoutFluidLayouts = [.nordicQwerty, .ansiQwerty]

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.keyboardLayout, .nordicQwerty)
    XCTAssertEqual(restored.keyboardInputLayout, .nordicQwerty)
    XCTAssertEqual(restored.layoutFluidLayouts, [.nordicQwerty, .ansiQwerty])
  }

  func testPortugueseQwertyLayoutsMapIsoAndAnsiPunctuationPositions() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "«", layout: .portugueseQwertyISO), "number-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "»", layout: .portugueseQwertyISO), "number-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ç", layout: .portugueseQwertyISO), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "~", layout: .portugueseQwertyISO), "home-11")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "<", layout: .portugueseQwertyANSI), "number-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "~", layout: .portugueseQwertyANSI), "top-12")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 24, modifierFlags: [.shift], layout: .portugueseQwertyISO), "»")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [], layout: .portugueseQwertyISO), "~")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 24, modifierFlags: [], layout: .portugueseQwertyANSI), "<")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [.shift], layout: .portugueseQwertyANSI), "^")
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ç", layout: .portugueseQwertyISO), 41)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ª", layout: .portugueseQwertyANSI), 39)
  }

  func testLatinAmericanQwertyLeavesItsDeadKeyToMacOSAndMapsTypedSymbols() {
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "ñ", layout: .latinAmericanQwerty), "home-9")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "¡", layout: .latinAmericanQwerty), "number-12")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: "[", layout: .latinAmericanQwerty), "home-10")
    XCTAssertEqual(KeyboardGuideModel.highlightedKey(for: ">", layout: .latinAmericanQwerty), "bottom-0")

    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 50, modifierFlags: [.shift], layout: .latinAmericanQwerty), "°")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 24, modifierFlags: [.shift], layout: .latinAmericanQwerty), "¡")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(forKeyCode: 39, modifierFlags: [.shift], layout: .latinAmericanQwerty), "[")
    XCTAssertNil(
      KeyboardLayoutEmulator.character(forKeyCode: 42, modifierFlags: [], layout: .latinAmericanQwerty))
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "ñ", layout: .latinAmericanQwerty), 41)
  }

  func testNonDefaultKeyboardLayoutsEmulatePhysicalAnsiKeyPositions() {
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [], layout: .ansiDvorak), ",")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [.shift], layout: .ansiDvorak), "<")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 1, modifierFlags: [], layout: .ansiColemak), "r")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 13, modifierFlags: [], layout: .ansiWorkman), "d")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 12, modifierFlags: [], layout: .frenchAzerty), "a")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 18, modifierFlags: [.shift], layout: .frenchAzerty), "1")
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [], layout: .ansiQwerty), "a")
    XCTAssertNil(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [], layout: KeyboardInputLayout.system.emulatedLayout))
    XCTAssertNil(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [.option], layout: .ansiDvorak))
  }

  func testKeyboardInputLayoutSeparatesSystemInputFromGuideAndPreservesLegacyChoices() {
    XCTAssertNil(KeyboardInputLayout.system.emulatedLayout)
    XCTAssertNil(KeyboardInputLayout.custom.emulatedLayout)
    XCTAssertEqual(KeyboardInputLayout.ansiQwerty.emulatedLayout, .ansiQwerty)
    XCTAssertEqual(KeyboardInputLayout.ansiDvorak.emulatedLayout, .ansiDvorak)
    XCTAssertEqual(KeyboardInputLayout.legacyDefault(for: .ansiQwerty), .system)
    XCTAssertEqual(KeyboardInputLayout.legacyDefault(for: .germanQwertz), .germanQwertz)
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 0, modifierFlags: [], layout: KeyboardInputLayout.ansiQwerty.emulatedLayout),
      "a")
  }

  @MainActor
  func testCustomKeyboardInputMappingPersistsAndFallsBackWhenItsLayoutIsDeleted() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    let layout = try XCTUnwrap(settings.addCustomKeyboardLayout(
      name: "Cyrillic", numberRow: "123", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС",
      shiftedNumberRow: "!\"#"))
    settings.keyboardInputLayout = .custom

    XCTAssertEqual(settings.selectedCustomKeyboardLayout, layout)
    XCTAssertEqual(
      KeyboardLayoutEmulator.character(
        forKeyCode: 12, modifierFlags: [],
        mapping: settings.keyboardInputLayout.inputMapping(for: settings.selectedCustomKeyboardLayout)),
      "й")

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.keyboardInputLayout, .custom)
    XCTAssertEqual(restored.selectedCustomKeyboardLayout, layout)
    XCTAssertEqual(restored.selectedCustomKeyboardLayout?.shiftedNumberRow, "!\"#")

    restored.deleteCustomKeyboardLayout(layout.id)
    XCTAssertEqual(restored.keyboardInputLayout, .system)
    XCTAssertNil(restored.selectedCustomKeyboardLayout)

    XCTAssertEqual(AppSettingsSnapshot(keyboardInputLayout: .custom).keyboardInputLayout, .system)
  }

  @MainActor
  func testNativeInputKeepsMarkedCompositionOutOfTheTypingEngineUntilCommit() {
    let input = TypingInputView(frame: .zero)
    var markedText = [String]()
    var insertedText = [String]()
    input.onCompositionChanged = { markedText.append($0) }
    input.onInsert = { text, _ in insertedText.append(text) }

    input.setMarkedText("拼", selectedRange: NSRange(location: 0, length: 1), replacementRange: .init())
    XCTAssertEqual(markedText, ["拼"])
    XCTAssertTrue(insertedText.isEmpty)
    XCTAssertTrue(input.hasMarkedText())

    input.insertText("拼", replacementRange: .init())
    XCTAssertEqual(markedText, ["拼", ""])
    XCTAssertEqual(insertedText, ["拼"])
    XCTAssertFalse(input.hasMarkedText())
  }

  func testOppositeShiftPolicyAllowsCentreKeysAndRequiresTheOtherHandElsewhere() {
    XCTAssertFalse(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 0, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 4, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 16, leftShiftPressed: true, rightShiftPressed: false))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 11, leftShiftPressed: false, rightShiftPressed: true))
    XCTAssertTrue(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: 0, leftShiftPressed: false, rightShiftPressed: false))
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "a", layout: .ansiDvorak), 0)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiDvorak), 15)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "A", layout: .frenchAzerty), 12)
    XCTAssertEqual(KeyboardLayoutEmulator.keyCode(for: "@", layout: .ansiQwerty), 19)
    XCTAssertFalse(
      OppositeShiftPolicy.usesOppositeShift(
        keyCode: try! XCTUnwrap(KeyboardLayoutEmulator.keyCode(for: "p", layout: .ansiDvorak)),
        leftShiftPressed: true,
        rightShiftPressed: false))
  }

  func testForcedPhysicalInputErrorRetainsTypedTextButChangesMetricsReviewsAndReplay() {
    var session = TypingSession(configuration: .words(2), prompt: "a b ")
    let start = Date(timeIntervalSince1970: 1_000)
    session.insert("a", forceError: true, at: start)
    session.insert(" ", at: start.addingTimeInterval(0.2))
    session.insert("b", at: start.addingTimeInterval(0.4))

    XCTAssertEqual(session.typed, "a b")
    XCTAssertEqual(session.errors, 1)
    XCTAssertEqual(session.accuracy, 67)
    XCTAssertEqual(session.promptGlyphs[0].state, .incorrect)
    XCTAssertEqual(session.wordReviews.first?.typed, "a")
    XCTAssertFalse(session.wordReviews.first?.isCorrect ?? true)
    XCTAssertTrue(session.missedWords.contains("a"))
    XCTAssertTrue(session.result(at: start.addingTimeInterval(1))?.replayEvents.first?.forceError ?? false)
  }

  func testCodePracticeAutoIndentsUnindentsReplaysAndFinishesWordMode() {
    let configuration = TestConfiguration.words(
      1, rules: .init(codeUnindentOnBackspace: true), language: .codeSwift)
    let start = Date(timeIntervalSince1970: 2_000)
    var session = TypingSession(configuration: configuration, prompt: "if ready {\n\tgo()\n}")

    session.insert("if ready {\n", at: start)
    XCTAssertEqual(session.typed, "if ready {\n\t")

    session.deleteBackward(at: start.addingTimeInterval(1))
    XCTAssertEqual(session.typed, "if ready {")

    session.insert("\ngo()\n}", at: start.addingTimeInterval(2))
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.typed, "if ready {\n\tgo()\n}")
    let replayEvents = session.result(at: start.addingTimeInterval(2))?.replayEvents ?? []
    XCTAssertTrue(replayEvents.contains(where: \ .automatic))
    XCTAssertEqual(TypingReplay.typedText(events: replayEvents, through: 2), session.typed)
  }

  func testEveryOfficialCodeLanguageHasAnOriginalPromptAndCompletesCodeMode() {
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    let expectedDisplayNames: Set<String> = [
      "ABAP", "ABAP 1k", "Arduino", "Assembly", "Bash", "Brainf*ck", "C", "C#", "C++",
      "COBOL", "CSS", "CUDA", "Clojure", "Common Lisp", "Dart", "Elixir", "Erlang", "F#",
      "Fortran", "GDScript", "GDScript 2", "Gleam", "Go", "Haskell", "HTML", "Java",
      "JavaScript", "JavaScript 1k", "JavaScript React", "Julia", "Jule", "Kotlin", "LaTeX", "Lua", "Luau",
      "MATLAB", "Nim", "Nix", "OCaml", "Odin", "Ook!", "OpenCL", "PHP", "Pascal", "Perl",
      "PowerShell", "Python", "Python 1k", "Python 2k", "Python 5k", "R", "R 2k", "Rockstar",
      "Ruby", "Rust", "SQL", "Scala", "Swift", "SystemVerilog", "TypeScript", "Typst", "V",
      "VHDL", "Vim", "Vimscript", "Visual Basic", "YoptaScript", "Zig", "6502 Assembly",
    ]
    XCTAssertEqual(languages.count, 69)
    XCTAssertEqual(Set(languages), Set(CodeLanguageCatalog.displayNames.keys))
    XCTAssertEqual(Set(languages.map(\.displayName)), Set(expectedDisplayNames.map { "Code · \($0)" }))

    let start = Date(timeIntervalSince1970: 3_000)
    for language in languages {
      let prompt = OfflineContent.generatedPrompt(
        wordCount: 9, language: language, contentOptions: .init())
      XCTAssertFalse(prompt.isEmpty, language.displayName)
      XCTAssertFalse(language.supportsQuotes, language.displayName)
      XCTAssertFalse(language.usesSpaceDelimitedWords, language.displayName)

      var session = TypingSession(configuration: .words(9, language: language), prompt: prompt)
      for character in prompt {
        if character == "\t", session.typed.last == "\t" { continue }
        session.insert(String(character), at: start)
      }
      XCTAssertTrue(session.isFinished, language.displayName)
      XCTAssertEqual(session.typed, prompt, language.displayName)
      XCTAssertEqual(session.result(at: start)?.prompt, prompt, language.displayName)
    }
  }

  func testPracticeTapePolicyAnchorsByWordOrCharacterWithoutChangingInput() {
    let typed = "alpha beta"
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .off), 0)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .word), 6)
    XCTAssertEqual(PracticeTapePolicy.anchorCharacterIndex(typed: typed, mode: .letter), 10)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .word, margin: 0.5, glyphWidth: 10, containerWidth: 100), 10)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .letter, margin: 0.5, glyphWidth: 10, containerWidth: 100), 50)
    XCTAssertEqual(
      PracticeTapePolicy.horizontalOffset(
        typed: typed, mode: .off, margin: 0.5, glyphWidth: 10, containerWidth: 100), 0)
  }

  func testPracticeLineDisplayPolicyMatchesSupportedUntimedModes() {
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .words, hasTimeLimit: false))
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .quote, hasTimeLimit: false))
    XCTAssertTrue(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .custom, hasTimeLimit: false))

    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: false, tapeMode: .off, testMode: .words, hasTimeLimit: false))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .letter, testMode: .words, hasTimeLimit: false))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .time, hasTimeLimit: true))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .custom, hasTimeLimit: true))
    XCTAssertFalse(PracticeLineDisplayPolicy.shouldShowAllLines(
      settingEnabled: true, tapeMode: .off, testMode: .zen, hasTimeLimit: false))
  }

  func testKeyboardMirrorTransformsOnlyAsciiPhysicalRowsAndPreservesComposedText() {
    XCTAssertEqual(KeyboardMirror.transform("qaz19"), "plm02")
    XCTAssertEqual(KeyboardMirror.transform("QAZ"), "PLM")
    XCTAssertEqual(KeyboardMirror.transform("á中"), "á中")
    XCTAssertEqual(
      KeyboardGuideModel.highlightedKey(for: KeyboardMirror.transform("a").first), "home-8")
  }

  func testCommandPaletteSearchNormalizesCaseAndMatchesKeywords() {
    let items = [
      CommandPaletteItem(
        id: "history", title: "打开练习历史", subtitle: "查看成绩", systemImage: "clock",
        keywords: ["history", "统计"]),
      CommandPaletteItem(
        id: "restart", title: "重新开始测试", subtitle: "当前配置", systemImage: "arrow",
        keywords: ["restart", "重开"]),
    ]

    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "  HISTORY "), [items[0]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "统计"), [items[0]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: "重开"), [items[1]])
    XCTAssertEqual(CommandPaletteSearch.results(items: items, query: ""), items)
  }

  func testCommandPaletteBrowsePolicySeparatesGroupsAndSupportsGlobalSearch() {
    let restart = CommandPaletteItem(
      id: "restart", title: "重新开始测试", subtitle: "当前配置", systemImage: "arrow",
      keywords: ["restart", "重开"], group: .practice)
    let theme = CommandPaletteItem(
      id: "theme.builtin.paper", title: "切换主题：纸页", subtitle: "内置主题", systemImage: "paintpalette",
      keywords: ["theme", "主题"], group: .appearance)
    let preset = CommandPaletteItem(
      id: "preset.example", title: "应用预设：冲刺", subtitle: "时间 · 60 秒", systemImage: "slider.horizontal.3",
      keywords: ["preset", "预设"], group: .library)
    let items = [restart, theme, preset]

    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .singleList, selectedGroup: nil, query: ""),
      .searchHint)
    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .singleList, selectedGroup: nil, query: "主题"),
      .items([theme]))
    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .grouped, selectedGroup: nil, query: ""),
      .groups([.practice, .library, .appearance]))
    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .grouped, selectedGroup: nil, query: "theme"),
      .groups([.appearance]))
    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .grouped, selectedGroup: .practice, query: ""),
      .items([restart]))
    XCTAssertEqual(
      CommandPaletteBrowsePolicy.destination(
        items: items, listMode: .grouped, selectedGroup: .practice, query: "> theme"),
      .items([theme]))
    XCTAssertTrue(CommandPaletteBrowsePolicy.isGlobalSearch("> theme"))
    XCTAssertEqual(CommandPaletteBrowsePolicy.globalSearchQuery("> theme"), " theme")
  }

  func testTypingCompanionTracksPhysicalHandsAndClampsSpeedFeedback() {
    var hands = TypingCompanionHands()
    XCTAssertFalse(hands.leftIsActive)
    XCTAssertFalse(hands.rightIsActive)

    hands.handle(keyCode: 0, isKeyDown: true)  // A: left hand
    XCTAssertTrue(hands.leftIsActive)
    XCTAssertFalse(hands.rightIsActive)
    hands.handle(keyCode: 4, isKeyDown: true)  // H: right hand
    XCTAssertTrue(hands.leftIsActive)
    XCTAssertTrue(hands.rightIsActive)
    hands.handle(keyCode: 0, isKeyDown: false)
    XCTAssertFalse(hands.leftIsActive)
    XCTAssertTrue(hands.rightIsActive)
    hands.handle(keyCode: 4, isKeyDown: false)

    hands.handle(keyCode: 16, isKeyDown: true)  // Y: shared centre key
    XCTAssertTrue(hands.leftIsActive)
    XCTAssertFalse(hands.rightIsActive)
    hands.handle(keyCode: 16, isKeyDown: false)
    hands.handle(keyCode: 16, isKeyDown: true)
    XCTAssertFalse(hands.leftIsActive)
    XCTAssertTrue(hands.rightIsActive)
    hands.reset()
    XCTAssertFalse(hands.leftIsActive)
    XCTAssertFalse(hands.rightIsActive)

    hands.handle(keyCode: 56, isKeyDown: true)  // Left Shift
    XCTAssertTrue(hands.leftIsActive)
    hands.handle(keyCode: 56, isKeyDown: false)
    XCTAssertFalse(hands.leftIsActive)

    hands.handle(keyCode: 10, isKeyDown: true)  // ISO section: left hand
    XCTAssertTrue(hands.leftIsActive)
    hands.handle(keyCode: 10, isKeyDown: false)
    XCTAssertFalse(hands.leftIsActive)

    XCTAssertEqual(TypingCompanionMotion.fastBlend(for: 0), 0)
    XCTAssertEqual(TypingCompanionMotion.fastBlend(for: 130), 0)
    XCTAssertEqual(TypingCompanionMotion.fastBlend(for: 155), 0.5, accuracy: 0.001)
    XCTAssertEqual(TypingCompanionMotion.fastBlend(for: 180), 1)
    XCTAssertEqual(TypingCompanionMotion.fastBlend(for: 250), 1)
  }

  func testTypingPowerModesKeepReferenceLevelSemanticsWithNativeParticles() {
    XCTAssertFalse(TypingPowerMode.off.isEnabled)
    XCTAssertFalse(TypingPowerMode.mellow.usesSpectrum)
    XCTAssertFalse(TypingPowerMode.high.usesShake)
    XCTAssertTrue(TypingPowerMode.high.usesSpectrum)
    XCTAssertTrue(TypingPowerMode.ultra.usesShake)
    XCTAssertTrue(TypingPowerMode.over9000.usesSpectrum)
    XCTAssertTrue(TypingPowerMode.over9000.usesShake)
    XCTAssertEqual(TypingPowerPolicy.particleCount(randomUnit: -1), 6)
    XCTAssertEqual(TypingPowerPolicy.particleCount(randomUnit: 0.5), 8)
    XCTAssertEqual(TypingPowerPolicy.particleCount(randomUnit: 2), 9)
    XCTAssertEqual(TypingPowerPolicy.tone(for: .mellow, isCorrect: true, isBlind: false), .accent)
    XCTAssertEqual(TypingPowerPolicy.tone(for: .mellow, isCorrect: false, isBlind: false), .error)
    XCTAssertEqual(TypingPowerPolicy.tone(for: .mellow, isCorrect: false, isBlind: true), .accent)
    XCTAssertEqual(TypingPowerPolicy.tone(for: .high, isCorrect: false, isBlind: false), .spectrum)
    XCTAssertEqual(TypingPowerPolicy.origin(typedCharacters: 0, promptLength: 10), .init(x: 0.22, y: 0.48))
    XCTAssertEqual(TypingPowerPolicy.origin(typedCharacters: 10, promptLength: 10), .init(x: 0.78, y: 0.48))
    XCTAssertEqual(TypingPowerPolicy.shakeOffset(xRandomUnit: 1, yRandomUnit: 0), .init(width: 5, height: -5))
  }

  func testHistoryChartPolicyMatchesLocalHistoryTracesAndTypingTimeTrend() throws {
    XCTAssertEqual(HistoryChartVisibility(), .init())
    XCTAssertEqual(
      HistoryChartPolicy.movingAverage(values: [120, 100, 80], windowSize: 10), [100, 90, 80])
    XCTAssertEqual(
      HistoryChartPolicy.personalBestEnvelope(values: [95, 110, 90]), [110, 110, 90])

    let older = ResultMetric(
      finishedAt: .init(timeIntervalSince1970: 1), wpm: 100, accuracy: 97, typingSeconds: 60)
    let newer = ResultMetric(
      finishedAt: .init(timeIntervalSince1970: 2), wpm: 120, accuracy: 99, typingSeconds: 60)
    XCTAssertEqual(
      try XCTUnwrap(HistoryChartPolicy.speedChangePerTypingHour(metrics: [newer, older])), 600,
      accuracy: 0.001)
    XCTAssertEqual(TypingSpeedUnit.cps.converted(wpm: 12.5), 1.041_666_666_7, accuracy: 0.000_001)
  }

  func testIndependentCaretLayoutTracksGlyphsWrapsAndMotionSettings() throws {
    let text = AttributedString("amber harbor willow")
    let font = PracticeFont.monospaced.nsFont(size: 28)
    let first = try XCTUnwrap(
      PromptCaretLayout.rect(
        in: text, characterOffset: 0, containerSize: .init(width: 360, height: 200),
        font: font, lineSpacing: 12))
    let secondWord = try XCTUnwrap(
      PromptCaretLayout.rect(
        in: text, characterOffset: 6, containerSize: .init(width: 360, height: 200),
        font: font, lineSpacing: 12))
    let wrapped = try XCTUnwrap(
      PromptCaretLayout.rect(
        in: text, characterOffset: 13, containerSize: .init(width: 90, height: 200),
        font: font, lineSpacing: 12))
    let wrappedBoundary = try XCTUnwrap(
      PromptCaretLayout.rect(
        in: text, characterOffset: 12, containerSize: .init(width: 90, height: 200),
        font: font, lineSpacing: 12))

    XCTAssertGreaterThan(secondWord.minX, first.minX)
    XCTAssertGreaterThan(wrapped.minY, first.minY)
    XCTAssertEqual(wrappedBoundary.minY, wrapped.minY)
    XCTAssertNil(
      PromptCaretLayout.rect(
        in: text, characterOffset: 100, containerSize: .init(width: 360, height: 200),
        font: font, lineSpacing: 12))
    XCTAssertEqual(SmoothCaretMotion.off.duration, nil)
    XCTAssertEqual(try XCTUnwrap(SmoothCaretMotion.slow.duration), 0.15, accuracy: 0.0001)
    XCTAssertEqual(try XCTUnwrap(SmoothCaretMotion.medium.duration), 0.10, accuracy: 0.0001)
    XCTAssertEqual(try XCTUnwrap(SmoothCaretMotion.fast.duration), 0.085, accuracy: 0.0001)
    XCTAssertFalse(TypingCaretStyle.bar.usesFullGlyphWidth)
    XCTAssertTrue(TypingCaretStyle.outline.usesFullGlyphWidth)
    XCTAssertTrue(TypingCaretStyle.underline.usesFullGlyphWidth)
    XCTAssertTrue(TypingCaretStyle.block.usesFullGlyphWidth)
    XCTAssertTrue(TypingCaretStyle.allCases.contains(.outline))
    XCTAssertTrue(TypingCaretStyle.allCases.contains(.carrot))
    XCTAssertTrue(TypingCaretStyle.allCases.contains(.banana))
    XCTAssertTrue(TypingCaretStyle.allCases.contains(.monkey))
  }

  @MainActor
  func testInstalledPracticeFontResolvesLocalNamesAndSafelyFallsBack() {
    let installedName = NativePracticeFont.fallbackPostScriptName

    XCTAssertEqual(NativePracticeFont.normalizedName(" \n\(installedName)\t "), installedName)
    XCTAssertEqual(NativePracticeFont.postScriptName(for: installedName), installedName)
    XCTAssertTrue(NativePracticeFont.isAvailable(installedName))
    XCTAssertNil(NativePracticeFont.postScriptName(for: "Typebar-Missing-Font"))
    XCTAssertEqual(
      NativePracticeFont.normalizedName(String(repeating: "a", count: 55)).count,
      NativePracticeFont.maximumNameLength)
    XCTAssertEqual(
      PracticeFont.serif.nsFont(size: 24, installedFontName: installedName).fontName,
      installedName)
  }

  func testLocalPracticeFontFilePolicyAcceptsNativeFormatsOnly() {
    XCTAssertTrue(LocalPracticeFontFilePolicy.supports(filename: "practice.ttf"))
    XCTAssertTrue(LocalPracticeFontFilePolicy.supports(filename: "PRACTICE.OTF"))
    XCTAssertFalse(LocalPracticeFontFilePolicy.supports(filename: "practice.woff"))
    XCTAssertFalse(LocalPracticeFontFilePolicy.supports(filename: "practice.woff2"))
    XCTAssertFalse(LocalPracticeFontFilePolicy.supports(filename: "practice.ttc"))
    XCTAssertFalse(LocalPracticeFontFilePolicy.supports(filename: "practice"))
  }

  @MainActor
  func testRestoreDefaultsResetsPersistedSettings() {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.difficulty = .master
    settings.installedPracticeFontName = NativePracticeFont.fallbackPostScriptName
    settings.theme = .midnight
    settings.customBackgroundURL = "https://images.example.test/harbour.jpeg"
    settings.showTypingCompanion = true
    settings.commandPaletteListMode = .grouped
    settings.restoreDefaults()

    XCTAssertEqual(settings.snapshot, AppSettingsSnapshot())
    XCTAssertEqual(AppSettings(defaults: defaults).snapshot, AppSettingsSnapshot())
  }

  @MainActor
  func testFreshAndRestoredSettingsUseReferenceCompatiblePresentationDefaults() {
    let suiteName = "TypebarTests.reference-defaults-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    XCTAssertFalse(settings.showKeyboardGuide)
    XCTAssertEqual(settings.keyboardGuideMode, .off)
    XCTAssertEqual(settings.quickRestartKey, .off)
    XCTAssertFalse(settings.smoothPracticeLineScroll)
    XCTAssertEqual(settings.caretStyle, .bar)
    XCTAssertEqual(settings.liveSpeedStyle, .off)
    XCTAssertEqual(settings.liveAccuracyStyle, .off)
    XCTAssertEqual(settings.liveBurstStyle, .off)
    XCTAssertEqual(settings.liveProgressStyle, .mini)
    XCTAssertEqual(settings.soundVolume, 0.5)
    XCTAssertEqual(settings.paceGuideCustomWpm, 100)
    XCTAssertTrue(settings.repeatedPace)

    settings.keyboardGuideMode = .next
    settings.quickRestartKey = .escape
    settings.liveSpeedStyle = .text
    settings.restoreDefaults()

    XCTAssertEqual(settings.snapshot, AppSettingsSnapshot())
  }

  func testSettingsSearchMatchesEveryWhitespaceSeparatedTokenAcrossLocalizedTerms() {
    XCTAssertTrue(
      SettingsSearch.matches(query: "KEYBOARD layout", terms: ["键盘布局", "Keyboard Layout", "下一键"]))
    XCTAssertTrue(SettingsSearch.matches(query: "快速结束", terms: ["最后一词快速结束", "Quick End"]))
    XCTAssertTrue(
      SettingsSearch.matches(
        query: "连续 统计日", terms: ["连续练习日分界", "统计日", "活动", "Streak"]))
    XCTAssertFalse(SettingsSearch.matches(query: "账户 主题", terms: ["自建账户", "登录", "邮箱"]))
    XCTAssertTrue(SettingsSearch.matches(query: "   ", terms: ["任意设置"]))
  }

  func testTestConfigurationShareRoundTripsAndRejectsInvalidLinks() throws {
    let custom = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .expert,
        rules: .init(quickEnd: true, minimumWordBurstWpm: 90), language: .english), quoteID: nil,
      customText: "A locally shared practice passage.")
    let link = try TestConfigurationShare.link(for: custom)
    XCTAssertEqual(try TestConfigurationShare.preset(from: link), custom)

    XCTAssertThrowsError(try TestConfigurationShare.preset(from: "https://example.com/test"))
    XCTAssertThrowsError(
      try TestConfigurationShare.link(
        for: .init(configuration: .timed(seconds: 2), quoteID: nil, customText: nil)))
    XCTAssertThrowsError(
      try TestConfigurationShare.preset(from: "typebar://test?preset=not-base64"))
  }

  func testCustomTextPolicyBoundsEditorSharingAndArchiveImport() throws {
    let valid = String(repeating: "a", count: CustomTextPolicy.maximumLength)
    let oversized = valid + "b"
    XCTAssertEqual(CustomTextPolicy.clamped(oversized), valid)
    XCTAssertTrue(CustomTextPolicy.isValid(valid))
    XCTAssertFalse(CustomTextPolicy.isValid(oversized))

    let oversizedPreset = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      quoteID: nil,
      customText: oversized
    )
    XCTAssertThrowsError(try TestConfigurationShare.link(for: oversizedPreset))

    let archive = TypebarArchive(
      exportedAt: start, settings: .init(), results: [], presets: [],
      savedTexts: [
        .init(title: "Valid", text: "A valid local passage."),
        .init(title: "Oversized", text: oversized),
        .init(title: "", text: "Missing title"),
      ])
    XCTAssertEqual(
      TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: []),
      [.init(title: "Valid", text: "A valid local passage.")])
  }

  func testResultSavingPolicyPersistsOnlyCompletedResultsWhenEnabled() {
    XCTAssertTrue(ResultSavingPolicy.shouldPersist(outcome: .completed, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .completed, enabled: false))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .failed, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .abandoned, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .bailedOut, enabled: true))
    XCTAssertFalse(ResultSavingPolicy.shouldPersist(outcome: .invalidAFK, enabled: true))
  }

  func testCompletedStatusTextReflectsWhetherResultWasSaved() {
    XCTAssertEqual(TestOutcome.completed.statusText(savesResult: true), "本次完成 · 已保存到本机")
    XCTAssertEqual(TestOutcome.completed.statusText(savesResult: false), "本次完成 · 未保存为完成成绩")
    XCTAssertEqual(TestOutcome.bailedOut.statusText(savesResult: true), "本次已中止 · 未保存为完成成绩")
    XCTAssertEqual(TestOutcome.invalidAFK.statusText(savesResult: true), "本次因闲置无效 · 未保存为完成成绩")
  }

  func testCompletedSessionCreatesPortableResult() throws {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("amber", at: start)
    let result = try XCTUnwrap(session.result(tags: [" morning ", "MORNING", "focus"]))
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(result.typedCharacterCount, 5)
    XCTAssertEqual(result.correctCharacterCount, 5)
    XCTAssertEqual(result.configuration.mode, .custom)
    XCTAssertEqual(result.rawWpm, 60)
    XCTAssertEqual(result.tags, ["morning", "focus"])
    XCTAssertEqual(result.prompt, "amber")
    XCTAssertEqual(result.replayEvents.map(\.kind), [.insert, .insert, .insert, .insert, .insert])
  }

  func testResultShareTextUsesOnlyLocalCompletedResultData() {
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let result = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), typedCharacterCount: 12, correctCharacterCount: 11,
      errorCount: 1, wpm: 72, rawWpm: 74, accuracy: 91, prompt: "amber harbor", replayEvents: [])
    XCTAssertEqual(
      ResultShareText.make(for: result), "Typebar\n72 WPM · 91% 准确率 · 1 错误\ntime · english · 30 秒")
  }

  func testResultInputTextRebuildsActualInputOnlyWhenReplayExists() {
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let result = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(3), typedCharacterCount: 5, correctCharacterCount: 4,
      errorCount: 1, wpm: 20, rawWpm: 25, accuracy: 80, prompt: "amber",
      replayEvents: [
        .init(offset: 0, kind: .insert, text: "amx"),
        .init(offset: 1, kind: .delete, text: ""),
        .init(offset: 2, kind: .insert, text: "ber"),
      ])
    XCTAssertEqual(ResultInputText.make(for: result), "amber")
    XCTAssertNil(
      ResultInputText.make(
        for: CompletedTestResult(
          id: UUID(), configuration: configuration, outcome: .completed, startedAt: start,
          finishedAt: start.addingTimeInterval(3), typedCharacterCount: 5, correctCharacterCount: 5,
          errorCount: 0, wpm: 20, rawWpm: 20, accuracy: 100, prompt: "amber")))
  }

  func testResultPromptTextCopiesReachedTargetsInsteadOfActualInputOrFuturePrompt() {
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let result = CompletedTestResult(
      id: UUID(), configuration: configuration, outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(3), typedCharacterCount: 6, correctCharacterCount: 5,
      errorCount: 1, wpm: 20, rawWpm: 24, accuracy: 83, prompt: "amber harbor summer",
      replayEvents: [.init(offset: 0, kind: .insert, text: "amxer ")])
    XCTAssertEqual(
      ResultPromptText.make(
        for: result,
        reviews: [.init(index: 0, target: "amber", typed: "amxer", hasInputError: true)]),
      "amber")

    let chinese = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30, language: .simplifiedChinese),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0, wpm: 20, rawWpm: 24,
      accuracy: 100, prompt: "晨光窗边", replayEvents: [.init(offset: 0, kind: .insert, text: "晨")])
    XCTAssertEqual(ResultPromptText.make(for: chinese, reviews: []), "晨光")

    let punctuatedChinese = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30, language: .simplifiedChinese),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: 1, correctCharacterCount: 1, errorCount: 0, wpm: 20, rawWpm: 24,
      accuracy: 100, prompt: "（晨光）窗边", replayEvents: [.init(offset: 0, kind: .insert, text: "（")])
    XCTAssertEqual(ResultPromptText.make(for: punctuatedChinese, reviews: []), "（晨光）")

    let zen = CompletedTestResult(
      id: UUID(),
      configuration: .init(mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      outcome: .completed, startedAt: start, finishedAt: start.addingTimeInterval(3),
      typedCharacterCount: 5, correctCharacterCount: 4, errorCount: 1, wpm: 20, rawWpm: 24,
      accuracy: 80, prompt: "unused prompt", replayEvents: [.init(offset: 0, kind: .insert, text: "hello")])
    XCTAssertEqual(ResultPromptText.make(for: zen, reviews: []), "hello")
  }

  func testResultImageExportUsesPortableUtcFilename() {
    XCTAssertEqual(
      ResultImageExport.filename(for: Date(timeIntervalSince1970: 0)),
      "typebar-result-19700101-000000.png")
  }

  func testResultCSVExportEscapesLocalMetadataAndUsesUtcFilename() throws {
    let configuration = TestConfiguration.timed(
      seconds: 30, difficulty: .expert, language: .french,
      contentOptions: .init(includePunctuation: true, includeNumbers: true)
    )
    .with(modifiers: [.uppercase, .rot13])
    let result = CompletedTestResult(
      id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000007")),
      configuration: configuration, outcome: .completed,
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 2.5), afkDuration: 0.5,
      typedCharacterCount: 12, correctCharacterCount: 11, errorCount: 1, wpm: 60, rawWpm: 66,
      accuracy: 92, tags: ["focus, \"deep\"", "café"], prompt: "private prompt",
      replayEvents: [.init(offset: 0.5, kind: .insert, text: "bonjour")]
    )

    let csv = ResultCSVExport.csvString(for: [result])
    XCTAssertTrue(csv.hasPrefix(ResultCSVExport.columns.joined(separator: ",") + "\r\n"))
    XCTAssertTrue(csv.contains("00000000-0000-0000-0000-000000000007,completed,60,66,92,"))
    XCTAssertTrue(csv.contains(",true,true,expert,uppercase;rot13,\"focus, \"\"deep\"\";café\","))
    XCTAssertTrue(csv.contains("1970-01-01T00:00:00"))
    XCTAssertFalse(csv.contains("private prompt"))
    XCTAssertTrue(csv.hasSuffix("\r\n"))
    XCTAssertEqual(ResultCSVExport.csvString(for: []), ResultCSVExport.columns.joined(separator: ",") + "\r\n")
    XCTAssertEqual(
      ResultCSVExport.filename(for: Date(timeIntervalSince1970: 0)),
      "typebar-results-19700101-000000.csv")
  }

  func testSlowWordPracticeUsesReferenceTwentyPercentSelectionAndWeightsTheSlowest() throws {
    let reviews = [
      TypedWordReview(index: 0, target: "ember", typed: "ember"),
      TypedWordReview(index: 1, target: "cabin", typed: "cabin"),
      TypedWordReview(index: 2, target: "planet", typed: "planet"),
      TypedWordReview(index: 3, target: "willow", typed: "willow"),
      TypedWordReview(index: 4, target: "stream", typed: "stream"),
      TypedWordReview(index: 5, target: "ignored", typed: "ignored"),
    ]
    let shortPlan = try XCTUnwrap(
      SlowWordPracticePlan.make(reviews: Array(reviews.prefix(4)), bursts: [80, 70, 60, 50]))
    XCTAssertEqual(shortPlan.selectedWords, ["planet"])

    let plan = try XCTUnwrap(
      SlowWordPracticePlan.make(reviews: reviews, bursts: [90, 40, 25, 55, 70, nil]))
    XCTAssertEqual(plan.selectedWords, ["planet"])
    XCTAssertEqual(plan.exerciseWords, ["planet"])

    let repeatedTarget = try XCTUnwrap(
      SlowWordPracticePlan.make(
        reviews: [
          TypedWordReview(index: 0, target: "cabin", typed: "cabin"),
          TypedWordReview(index: 1, target: "cabin", typed: "cabin"),
          TypedWordReview(index: 2, target: "planet", typed: "planet"),
          TypedWordReview(index: 3, target: "willow", typed: "willow"),
          TypedWordReview(index: 4, target: "stream", typed: "stream"),
          TypedWordReview(index: 5, target: "ember", typed: "ember"),
        ],
        bursts: [10, 20, 30, 40, 50, 60]))
    XCTAssertEqual(repeatedTarget.selectedWords, ["cabin"])
  }

  func testContextualMissedWordPracticeKeepsOnlyAttemptedTargetContext() throws {
    let plan = try XCTUnwrap(
      ContextualMissedWordPracticePlan.make(
        reviews: [
          TypedWordReview(index: 0, target: "ember", typed: "ember"),
          TypedWordReview(index: 1, target: "cabin", typed: "cab"),
          TypedWordReview(index: 2, target: "planet", typed: "planet"),
          TypedWordReview(index: 3, target: "willow", typed: "willox"),
        ],
        errorCounts: [0, 2, 0, 1]))
    XCTAssertEqual(plan.missedWordCount, 3)
    XCTAssertEqual(plan.phrases, ["ember cabin", "ember cabin", "planet willow"])
    XCTAssertNil(
      ContextualMissedWordPracticePlan.make(
        reviews: [TypedWordReview(index: 0, target: "ember", typed: "ember")], errorCounts: [0]))

    let sharedTarget = try XCTUnwrap(
      ContextualMissedWordPracticePlan.make(
        reviews: [
          TypedWordReview(index: 0, target: "cabin", typed: "cab"),
          TypedWordReview(index: 1, target: "harbor", typed: "harbor"),
          TypedWordReview(index: 2, target: "cabin", typed: "cabin"),
        ],
        errorCounts: [2, 0, 0]))
    XCTAssertEqual(sharedTarget.phrases, ["cabin", "cabin", "harbor cabin", "harbor cabin"])

    let capped = try XCTUnwrap(
      ContextualMissedWordPracticePlan.make(
        reviews: (0...10).map {
          TypedWordReview(index: $0, target: "word\($0)", typed: "wrong")
        },
        errorCounts: Array(repeating: 1, count: 11)))
    XCTAssertEqual(capped.missedWordCount, ContextualMissedWordPracticePlan.maximumSelectedWords)
  }

  func testMissedAndSlowPracticeBoundsMissedTargetsAndWeightsSlowWords() throws {
    let missed = try XCTUnwrap(MissedWordPracticePlan.make(errorCounts: [
      .init(word: "amber", count: 2), .init(word: "cabin", count: 1),
    ]))
    let slow = SlowWordPracticePlan(
      selectedWords: ["planet", "willow"], exerciseWords: ["ignored"])
    let plan = try XCTUnwrap(MissedAndSlowWordPracticePlan.make(missed: missed, slow: slow))
    XCTAssertEqual(plan.selectedTargetCount, 4)
    XCTAssertEqual(plan.exerciseWords, ["amber", "amber", "cabin", "planet", "planet", "willow"])

    let noSlow = MissedAndSlowWordPracticePlan.make(missed: missed, slow: nil)
    XCTAssertNil(noSlow)
  }

  func testContextualMissedAndSlowPracticePreservesPhrasesAndWeightsSlowWords() throws {
    let contextual = ContextualMissedWordPracticePlan(
      phrases: ["amber cabin", "amber cabin"], missedWordCount: 2, selectedTargetCount: 1)
    let slow = SlowWordPracticePlan(selectedWords: ["planet", "willow"], exerciseWords: [])
    let plan = try XCTUnwrap(
      ContextualMissedAndSlowWordPracticePlan.make(contextual: contextual, slow: slow))
    XCTAssertEqual(plan.selectedTargetCount, 3)
    XCTAssertEqual(
      plan.exerciseSegments,
      ["amber cabin", "amber cabin", "planet", "planet", "willow"])
  }

  func testTodayPracticeSummaryMergesSavedAndCurrentProcessWithoutDoubleCounting() {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSince1970: 1_728_000_000)
    let yesterday = today.addingTimeInterval(-86_400)
    let currentID = UUID()
    let summary = TodayPracticeAggregation.summary(
      persisted: [
        ResultMetric(id: currentID, finishedAt: today, wpm: 50, accuracy: 98, typingSeconds: 12),
        ResultMetric(finishedAt: today, wpm: 60, accuracy: 99, typingSeconds: 75),
        ResultMetric(finishedAt: yesterday, wpm: 70, accuracy: 100, typingSeconds: 90),
      ],
      currentProcess: [
        CurrentProcessPractice(id: currentID, finishedAt: today, typingSeconds: 18),
        CurrentProcessPractice(id: UUID(), finishedAt: today, typingSeconds: 7),
      ],
      now: today,
      calendar: calendar)
    XCTAssertEqual(summary.typingSeconds, 100)
    XCTAssertEqual(summary.completedTests, 3)
    XCTAssertEqual(summary.formattedDuration, "1 分 40 秒")
  }

  @MainActor
  func testResultSnapshotImageRendersThemedHighResolutionPng() throws {
    let result = CompletedTestResult(
      id: UUID(), configuration: .words(2), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(12), typedCharacterCount: 12, correctCharacterCount: 11,
      errorCount: 1, wpm: 66, rawWpm: 72, accuracy: 92, prompt: "amber harbor")
    let image = try XCTUnwrap(
      ResultSnapshotImage.make(
        result: result,
        typingSpeedUnit: .wpm,
        background: AppTheme.paper.background,
        panel: AppTheme.paper.panel,
        accent: AppTheme.paper.accent,
        colorScheme: .light))
    let tiff = try XCTUnwrap(image.tiffRepresentation)
    let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))

    XCTAssertEqual(bitmap.pixelsWide, 1_520)
    XCTAssertGreaterThan(bitmap.pixelsHigh, 500)
  }

  func testReplayRebuildsAcceptedInsertsAndDeletesAtRecordedTimes() {
    var session = TypingSession(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("ax", at: start)
    session.deleteBackward(at: start.addingTimeInterval(1))
    session.insert("mber", at: start.addingTimeInterval(2))
    let result = session.result(at: start.addingTimeInterval(2))

    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 0), "ax")
    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 1), "a")
    XCTAssertEqual(TypingReplay.typedText(events: result?.replayEvents ?? [], through: 2), "amber")
  }

  func testExtraCharactersNeverCauseAnOutOfBoundsRead() {
    var session = TypingSession(configuration: .timed(seconds: 30), prompt: "a")
    session.insert("abc", at: start)
    XCTAssertEqual(session.typed, "abc")
  }

  func testPromptPresentationMarksCorrectIncorrectCurrentExtraAndBlindCharacters() {
    let active = TypingPromptPresentation.glyphs(
      target: "amber", typed: "ax", isFinished: false, blindMode: false)
    XCTAssertEqual(
      active,
      [
        .init(character: "a", state: .correct),
        .init(character: "m", state: .incorrect, typedCharacter: "x"),
        .init(character: "b", state: .current),
        .init(character: "e", state: .pending),
        .init(character: "r", state: .pending),
      ])

    let extra = TypingPromptPresentation.glyphs(
      target: "a", typed: "ax", isFinished: false, blindMode: false)
    XCTAssertEqual(
      extra,
      [
        .init(character: "a", state: .correct),
        .init(character: "x", state: .extra),
      ])

    let blind = TypingPromptPresentation.glyphs(
      target: "a", typed: "ax", isFinished: false, blindMode: true)
    XCTAssertEqual(
      blind,
      [
        .init(character: "a", state: .hidden),
        .init(character: "x", state: .hidden),
      ])
  }

  func testPromptHighlightPolicyScopesWordsAndSafelyFallsBackToCharacter() {
    let target = "amber bay cove"
    let firstWord = Set(0..<5)
    let secondWord = Set(6..<9)
    let thirdWord = Set(10..<14)

    XCTAssertTrue(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .off,
      allowsWordRanges: true
    ).isEmpty)
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .letter,
      allowsWordRanges: true
    ), [2])
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .word,
      allowsWordRanges: true
    ), firstWord)
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .nextWord,
      allowsWordRanges: true
    ), firstWord.union(secondWord))
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .nextTwoWords,
      allowsWordRanges: true
    ), firstWord.union(secondWord).union(thirdWord))
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 5,
      mode: .word,
      allowsWordRanges: true
    ), firstWord)
    XCTAssertEqual(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 2,
      mode: .nextThreeWords,
      allowsWordRanges: false
    ), [2])
    XCTAssertTrue(PromptHighlightPolicy.highlightedIndices(
      in: target,
      currentTargetIndex: 99,
      mode: .nextWord,
      allowsWordRanges: true
    ).isEmpty)
  }

  func testTypedCharacterEffectsOnlySelectCompletedPromptWords() {
    XCTAssertEqual(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay quiet", typed: "amxer ", isFinished: false),
      Set(0..<5))
    XCTAssertEqual(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay", typed: "amber bay", isFinished: true),
      Set(0..<5).union(6..<9))
    XCTAssertTrue(
      TypedCharacterEffectPolicy.completedCharacterIndices(
        target: "amber bay", typed: "amber", isFinished: false).isEmpty)
  }

  func testAttentionWarningsRespectFocusLanguageCompletionAndPreferences() {
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .english, isFinished: false,
        showFocusWarning: true, showCapsLockWarning: true),
      [.inputUnfocused, .capsLockEnabled]
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, focusWarningDelayElapsed: false,
        capsLockEnabled: true, language: .english, isFinished: false,
        showFocusWarning: true, showCapsLockWarning: true),
      [.capsLockEnabled]
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: true, capsLockEnabled: true, language: .simplifiedChinese,
        isFinished: false, showFocusWarning: true, showCapsLockWarning: true),
      []
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .mixedEnglishChinese,
        isFinished: true, showFocusWarning: true, showCapsLockWarning: true),
      []
    )
    XCTAssertEqual(
      TypingAttentionPolicy.warnings(
        isInputFocused: false, capsLockEnabled: true, language: .english, isFinished: false,
        showFocusWarning: false, showCapsLockWarning: false),
      []
    )
  }

  func testSessionFactoryLeavesZenPromptFreeformAndBuildsOtherModePrompts() {
    let timed = TestSessionFactory.make(configuration: .timed(seconds: 120))
    let words = TestSessionFactory.make(configuration: .words(25))
    let quote = TestSessionFactory.make(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      quote: OfflineContent.quotes[1])
    let zen = TestSessionFactory.make(
      configuration: .init(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()))
    let custom = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      customText: "own text")

    XCTAssertGreaterThanOrEqual(timed.prompt.split(separator: " ").count, 480)
    XCTAssertEqual(words.prompt.split(separator: " ").count, 25)
    XCTAssertEqual(quote.prompt, OfflineContent.quotes[1].text)
    XCTAssertTrue(zen.prompt.isEmpty)
    XCTAssertEqual(custom.prompt, "own text")
  }

  func testSimplifiedChineseWordsUseOriginalUnspacedTermsAndFinishAtLimit() {
    let configuration = TestConfiguration.words(10, language: .simplifiedChinese)
    var session = TestSessionFactory.make(configuration: configuration)
    XCTAssertFalse(session.prompt.contains(" "))
    XCTAssertEqual(session.prompt.count, 20)

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testMixedEnglishChineseUsesOnlyTypebarOwnedCorporaAndSpaceDelimitedWordCompletion() {
    let configuration = TestConfiguration.words(
      8, language: .mixedEnglishChinese, englishVariant: .british)
    var session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)

    XCTAssertEqual(tokens.count, 8)
    XCTAssertTrue(
      tokens.enumerated().allSatisfy { index, token in
        index.isMultiple(of: 2)
          ? StarterLexicon.britishWords.contains(token)
          : StarterLexicon.simplifiedChineseWords.contains(token)
      })
    XCTAssertFalse(TypingLanguage.mixedEnglishChinese.supportsQuotes)
    XCTAssertTrue(OfflineContent.quotes(for: .mixedEnglishChinese).isEmpty)
    XCTAssertTrue(session.wordReviews.isEmpty)

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
  }

  func testMixedLanguagesCyclesOnlyTypebarOwnedCorporaAndCompletesByWords() {
    let configuration = TestConfiguration.words(
      8, language: .mixedLanguages, englishVariant: .british)
    var session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)
    let corpora = [
      StarterLexicon.britishWords, StarterLexicon.spanishWords, StarterLexicon.germanWords,
      StarterLexicon.frenchWords, StarterLexicon.italianWords, StarterLexicon.portugueseWords,
      StarterLexicon.simplifiedChineseWords,
    ]

    XCTAssertEqual(tokens.count, 8)
    XCTAssertTrue(
      tokens.enumerated().allSatisfy { corpora[$0.offset % corpora.count].contains($0.element) })
    XCTAssertTrue(TypingLanguage.mixedLanguages.usesSpaceDelimitedWords)
    XCTAssertFalse(TypingLanguage.mixedLanguages.supportsQuotes)
    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)

    let selected = [TypingLanguage.italian, .french]
    let customConfiguration = TestConfiguration.words(
      6, language: .mixedLanguages, mixedLanguageComponents: selected)
    let customTokens = TestSessionFactory.make(configuration: customConfiguration).prompt.split(
      separator: " "
    ).map(String.init)
    XCTAssertTrue(
      customTokens.enumerated().allSatisfy { index, token in
        [StarterLexicon.italianWords, StarterLexicon.frenchWords][index % 2].contains(token)
      })
    XCTAssertEqual(customConfiguration.mixedLanguageComponents, selected)
    XCTAssertEqual(
      TypingLanguage.normalizedMixedComponents([.english]), TypingLanguage.defaultMixedComponents)
  }

  func testContentOptionsGenerateAndPersistNumbersAndPunctuation() {
    let options = ContentOptions(includePunctuation: true, includeNumbers: true)
    let configuration = TestConfiguration.words(10, language: .english, contentOptions: options)
    var session = TestSessionFactory.make(configuration: configuration)
    XCTAssertTrue(session.prompt.contains(where: { $0.isNumber }))
    XCTAssertTrue(session.prompt.contains(where: { ",.!?".contains($0) }))

    session.insert(session.prompt, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.configuration.contentOptions, options)
  }

  func testOfflineCharacterStreamsOverrideBuiltInWordsWithoutExternalContent() {
    let binary = TestSessionFactory.make(
      configuration: TestConfiguration.words(3).with(modifiers: [.binaryStream]))
    XCTAssertEqual(
      binary.prompt.split(separator: " ").map(String.init), ["00000000", "00000001", "00000010"])
    let accounting = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.accountingStream]))
    XCTAssertTrue(
      accounting.prompt.split(separator: " ").allSatisfy {
        $0.contains(".") && $0.last.map(\.isNumber) == true
      })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.accountingStream, in: [.binaryStream]), [.accountingStream])
    let hexadecimal = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.hexadecimalStream]))
    XCTAssertTrue(hexadecimal.prompt.split(separator: " ").allSatisfy { $0.hasPrefix("0x") })
    let symbols = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.symbolStream]))
    XCTAssertTrue(symbols.prompt.allSatisfy { "!@#$%^&*+=?/[]{}<>~ ".contains($0) })
    XCTAssertEqual(TestModifierPolicy.toggling(.symbolStream, in: [.binaryStream]), [.symbolStream])
    let ascii = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.asciiStream]))
    XCTAssertTrue(ascii.prompt.allSatisfy { $0 == " " || (33...126).contains($0.asciiValue ?? 0) })
    let specials = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.specialCharacterStream]))
    XCTAssertTrue(specials.prompt.allSatisfy { "`~!@#$%^&*()-_=+{}[]|\\/?:;,.<> ".contains($0) })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.specialCharacterStream, in: [.asciiStream]),
      [.specialCharacterStream])
    let gibberish = TestSessionFactory.make(
      configuration: TestConfiguration.words(7).with(modifiers: [.gibberishStream]))
    XCTAssertTrue(gibberish.prompt.split(separator: " ").allSatisfy {
      (1...7).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isLowercase }
    })
    XCTAssertEqual(TestModifierPolicy.toggling(.gibberishStream, in: [.symbolStream]), [.gibberishStream])
    let poetry = TestSessionFactory.make(
      configuration: TestConfiguration.words(5).with(modifiers: [.poetryStream]))
    XCTAssertEqual(poetry.prompt.split(separator: " ").count, 5)
    XCTAssertTrue(poetry.prompt.allSatisfy { $0.isLetter || $0 == " " })
    XCTAssertEqual(TestModifierPolicy.toggling(.poetryStream, in: [.gibberishStream]), [.poetryStream])
    let reference = TestSessionFactory.make(
      configuration: TestConfiguration.words(6).with(modifiers: [.referenceStream]))
    XCTAssertEqual(reference.prompt.split(separator: " ").count, 6)
    XCTAssertTrue(reference.prompt.allSatisfy { $0.isLetter || $0 == " " })
    XCTAssertEqual(TestModifierPolicy.toggling(.referenceStream, in: [.poetryStream]), [.referenceStream])
    let arrows = TestSessionFactory.make(
      configuration: TestConfiguration.words(4).with(modifiers: [.arrowStream]))
    XCTAssertEqual(arrows.prompt.split(separator: " ").map(String.init), ["↑", "→", "↓", "←"])
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 126), "↑")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 124), "→")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 125), "↓")
    XCTAssertEqual(ArrowKeyInputPolicy.character(forKeyCode: 123), "←")
    XCTAssertNil(ArrowKeyInputPolicy.character(forKeyCode: 0))
    XCTAssertEqual(TestModifierPolicy.toggling(.arrowStream, in: [.symbolStream]), [.arrowStream])
    let ipv4 = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.ipv4Stream]))
    XCTAssertTrue(
      ipv4.prompt.split(separator: " ").allSatisfy { $0.split(separator: ".").count == 4 })
    let ipv6 = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.ipv6Stream]))
    XCTAssertTrue(
      ipv6.prompt.split(separator: " ").allSatisfy { $0.split(separator: ":").count == 4 })
    XCTAssertEqual(TestModifierPolicy.toggling(.ipv6Stream, in: [.ipv4Stream]), [.ipv6Stream])
    let pseudolang = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.pseudolangStream]))
    XCTAssertTrue(pseudolang.prompt.split(separator: " ").allSatisfy { $0.allSatisfy(\.isLetter) })
    let morse = TestSessionFactory.make(
      configuration: TestConfiguration.words(2).with(modifiers: [.morseStream]))
    XCTAssertTrue(morse.prompt.allSatisfy { ".-/ ".contains($0) })
    XCTAssertEqual(
      TestModifierPolicy.toggling(.morseStream, in: [.pseudolangStream]), [.morseStream])
  }

  func testLivePracticeContentParsesSanitizesAndExpandsPublicSources() throws {
    let poetryData = Data("""
    [{"title":"Night Walk","author":"A. Writer","lines":["Dawn, arrives.","Hands learn slowly."]}]
    """.utf8)
    let poetry = try XCTUnwrap(LivePracticeContentService.poetry(from: poetryData))
    XCTAssertEqual(poetry.text, "Dawn arrives Hands learn slowly")
    XCTAssertEqual(poetry.attribution, "诗歌内容：Night Walk · A. Writer")
    XCTAssertEqual(poetry.prompt(for: .words(7)).split(separator: " ").count, 7)
    let poetryConfiguration = TestConfiguration.words(4).with(modifiers: [.poetryStream])
    XCTAssertEqual(LivePracticeContentSource.selected(for: poetryConfiguration), .poetry)
    XCTAssertNil(LivePracticeContentSource.selected(for: .init(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init())))
    XCTAssertNil(LivePracticeContentSource.selected(for: .words(4, language: .simplifiedChinese)))
    XCTAssertEqual(
      TestSessionFactory.make(
        configuration: poetryConfiguration, streamPrompt: poetry.prompt(for: poetryConfiguration)
      ).prompt,
      "Dawn arrives Hands learn")
    XCTAssertTrue(LivePracticeContentReplacementPolicy.shouldApply(
      hasStarted: false, currentConfiguration: poetryConfiguration,
      requestedConfiguration: poetryConfiguration))
    XCTAssertFalse(LivePracticeContentReplacementPolicy.shouldApply(
      hasStarted: true, currentConfiguration: poetryConfiguration,
      requestedConfiguration: poetryConfiguration))
    XCTAssertFalse(LivePracticeContentReplacementPolicy.shouldApply(
      hasStarted: false, currentConfiguration: .words(5),
      requestedConfiguration: poetryConfiguration))

    let encyclopediaData = Data("""
    {"title":"Harbor","extract":"A harbor holds boats safely near shore."}
    """.utf8)
    let encyclopedia = try XCTUnwrap(LivePracticeContentService.encyclopedia(from: encyclopediaData))
    XCTAssertEqual(encyclopedia.text, "A harbor holds boats safely near shore")
    XCTAssertEqual(encyclopedia.prompt(for: .words(3)), "A harbor holds")
    XCTAssertNil(LivePracticeContentService.encyclopedia(from: Data("{}".utf8)))
  }

  @MainActor
  func testNativeInputBridgeSendsArrowKeysToTheTypingEngineOnlyInArrowMode() throws {
    var accepted = [String]()
    let view = TypingInputView()
    view.onInsert = { text, _ in accepted.append(text) }
    let up = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
        keyCode: 126))

    view.mapsArrowKeysToInput = true
    view.keyDown(with: up)
    XCTAssertEqual(accepted, ["↑"])

    accepted.removeAll()
    view.mapsArrowKeysToInput = false
    view.keyDown(with: up)
    XCTAssertTrue(accepted.isEmpty)
  }

  @MainActor
  func testNativeInputBridgeOnlySendsReturnWhenThePromptAcceptsNewlines() throws {
    var accepted = [String]()
    var restarts = 0
    let view = TypingInputView()
    view.onInsert = { text, _ in accepted.append(text) }
    view.onRestart = { restarts += 1 }
    let enter = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))

    view.quickRestartKey = .enter
    view.acceptsNewlineInput = true
    view.keyDown(with: enter)
    XCTAssertEqual(accepted, ["\n"])

    accepted.removeAll()
    view.acceptsNewlineInput = false
    view.keyDown(with: enter)
    XCTAssertTrue(accepted.isEmpty)
    XCTAssertEqual(restarts, 1)

    let shiftEnterRestart = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))
    view.acceptsNewlineInput = true
    view.keyDown(with: shiftEnterRestart)
    XCTAssertEqual(restarts, 2)
    XCTAssertTrue(accepted.isEmpty)

    let shiftEnter = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))
    var zenFinishes = 0
    view.acceptsNewlineInput = true
    view.finishesOnShiftEnter = true
    view.onFinishZen = { zenFinishes += 1 }
    view.keyDown(with: shiftEnter)
    XCTAssertEqual(zenFinishes, 1)
    XCTAssertTrue(accepted.isEmpty)
  }

  @MainActor
  func testNativeInputBridgeReservesShiftTabForRestartWhenThePromptNeedsTabs() throws {
    var accepted = [String]()
    var restarts = 0
    let view = TypingInputView()
    view.quickRestartKey = .tab
    view.acceptsTabInput = true
    view.onInsert = { text, _ in accepted.append(text) }
    view.onRestart = { restarts += 1 }
    let tab = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false,
        keyCode: 48))
    let shiftTab = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false,
        keyCode: 48))

    view.keyDown(with: tab)
    XCTAssertEqual(accepted, ["\t"])
    XCTAssertEqual(restarts, 0)

    view.keyDown(with: shiftTab)
    XCTAssertEqual(restarts, 1)
    XCTAssertEqual(accepted, ["\t"])
  }

  @MainActor
  func testNativeInputBridgeRequiresShiftToRestartLongTests() throws {
    var restarts = 0
    let view = TypingInputView()
    view.quickRestartKey = .escape
    view.requiresShiftQuickRestart = true
    view.onRestart = { restarts += 1 }
    let escape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
        keyCode: 53))
    let shiftEscape = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
        keyCode: 53))

    view.keyDown(with: escape)
    XCTAssertEqual(restarts, 0)
    view.keyDown(with: shiftEscape)
    XCTAssertEqual(restarts, 1)
  }

  @MainActor
  func testNativeInputBridgeUsesDoubleShiftEnterToBailOutOfLongTests() throws {
    var restarts = 0
    var armedBailouts = 0
    var bailouts = 0
    var now = start
    let view = TypingInputView()
    view.quickRestartKey = .enter
    view.disablesQuickRestart = true
    view.enablesLongTestBailout = true
    view.bailoutClock = { now }
    view.onRestart = { restarts += 1 }
    view.onBailoutArmed = { armedBailouts += 1 }
    view.onBailout = { bailouts += 1 }
    let enter = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))
    let shiftEnter = try XCTUnwrap(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36))

    view.keyDown(with: enter)
    view.keyDown(with: shiftEnter)
    now = start.addingTimeInterval(0.1)
    view.keyDown(with: shiftEnter)
    XCTAssertEqual(restarts, 0)
    XCTAssertEqual(armedBailouts, 1)
    XCTAssertEqual(bailouts, 1)

    now = start.addingTimeInterval(0.4)
    view.keyDown(with: shiftEnter)
    XCTAssertEqual(armedBailouts, 2)
    XCTAssertEqual(bailouts, 1)
  }

  func testZipfFrequencyModifierUsesRankWeightedTypebarLexicon() {
    XCTAssertEqual(ZipfWordSelection.index(in: 24, random: { 0 }), 0)
    XCTAssertEqual(ZipfWordSelection.index(in: 24, random: { 0.999_999 }), 23)
    XCTAssertLessThan(ZipfWordSelection.index(in: 24, random: { 0.25 }), 12)

    let configuration = TestConfiguration.words(30).with(modifiers: [.zipf])
    let session = TestSessionFactory.make(configuration: configuration)
    let tokens = session.prompt.split(separator: " ").map(String.init)
    XCTAssertEqual(tokens.count, 30)
    XCTAssertTrue(tokens.allSatisfy(StarterLexicon.words.contains))
    XCTAssertEqual(
      TestModifierPolicy.toggling(.zipf, in: [.uppercase]), [.uppercase, .zipf])
  }

  func testTextBoundaryModifiersTransformPromptsFinishWordsAndRemainMutuallyExclusive() {
    let noSpaceConfiguration = TestConfiguration.words(2).with(modifiers: [.noSpaces])
    var noSpaceSession = TestSessionFactory.make(configuration: noSpaceConfiguration)
    XCTAssertFalse(noSpaceSession.prompt.contains(" "))
    noSpaceSession.insert(noSpaceSession.prompt, at: start)
    XCTAssertEqual(noSpaceSession.outcome, .completed)
    XCTAssertEqual(noSpaceSession.wordReviews.count, 2)
    XCTAssertEqual(noSpaceSession.wordReviews.map(\.target).joined(), noSpaceSession.prompt)
    XCTAssertTrue(noSpaceSession.wordReviews.allSatisfy(\.isCorrect))

    let underscoreConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.underscoreSeparators])
    let underscoreSession = TestSessionFactory.make(
      configuration: underscoreConfiguration, customText: "amber harbor")
    XCTAssertEqual(underscoreSession.prompt, "amber_harbor")

    XCTAssertEqual(TestModifierPolicy.normalized([.noSpaces, .underscoreSeparators]), [.noSpaces])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.underscoreSeparators, in: [.noSpaces]), [.underscoreSeparators])

    let uppercaseConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces, .uppercase])
    let uppercaseSession = TestSessionFactory.make(
      configuration: uppercaseConfiguration, customText: "amber harbor")
    XCTAssertEqual(uppercaseSession.prompt, "AMBERHARBOR")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.noSpaces, .underscoreSeparators, .uppercase]),
      [.noSpaces, .uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.uppercase, in: [.noSpaces]), [.noSpaces, .uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.underscoreSeparators, in: [.noSpaces, .uppercase]),
      [.underscoreSeparators, .uppercase])

    let titleCase = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.titleCase]),
      customText: "amber HARBOR 9lives"
    )
    XCTAssertEqual(titleCase.prompt, "Amber Harbor 9lives")
    let alternatingCase = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.alternatingCase]),
      customText: "amber bay!"
    )
    XCTAssertEqual(alternatingCase.prompt, "aMbEr bAy!")
    let cipherAndBackwards = TestSessionFactory.make(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.rot13, .backwards]),
      customText: "amber bay"
    )
    XCTAssertEqual(cipherAndBackwards.prompt, "erozn lno")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.uppercase, .titleCase, .alternatingCase]), [.uppercase])
    XCTAssertEqual(
      TestModifierPolicy.toggling(.titleCase, in: [.uppercase, .noSpaces]), [.noSpaces, .titleCase])

    let doubledConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.uppercase, .doubleCharacters])
    let doubledSession = TestSessionFactory.make(
      configuration: doubledConfiguration, customText: "amber bay")
    XCTAssertEqual(doubledSession.prompt, "AAMMBBEERR BBAAYY")
    XCTAssertEqual(
      TestModifierPolicy.normalized([.noSpaces, .doubleCharacters]), [.noSpaces, .doubleCharacters])

    var focusSession = TypingSession(
      configuration: .init(
        mode: .words, duration: nil, wordLimit: 3, difficulty: .normal, rules: .init(),
        modifiers: [.focusCurrentWord]), prompt: "amber harbor quiet")
    XCTAssertEqual(
      focusSession.promptGlyphs.map(\.state),
      [
        .current, .pending, .pending, .pending, .pending, .pending, .hidden, .hidden, .hidden,
        .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden, .hidden,
      ])
    focusSession.insert("amber ", at: start)
    XCTAssertEqual(focusSession.promptGlyphs[6].state, .current)
    XCTAssertEqual(focusSession.promptGlyphs[13].state, .hidden)

    let nextWordConfiguration = TestConfiguration(
      mode: .words, duration: nil, wordLimit: 4, difficulty: .normal, rules: .init(),
      modifiers: [.focusNextWord])
    var nextWordSession = TypingSession(
      configuration: nextWordConfiguration, prompt: "amber harbor quiet moss")
    XCTAssertEqual(nextWordSession.promptGlyphs[6].state, .pending)
    XCTAssertEqual(nextWordSession.promptGlyphs[13].state, .hidden)
    nextWordSession.insert("amber ", at: start)
    XCTAssertEqual(nextWordSession.promptGlyphs[13].state, .pending)
    XCTAssertEqual(nextWordSession.promptGlyphs[19].state, .hidden)
    XCTAssertEqual(
      TestModifierPolicy.toggling(.focusTwoWords, in: [.focusCurrentWord, .uppercase]),
      [.uppercase, .focusTwoWords])
    XCTAssertEqual(
      TestConfiguration.words(3).with(modifiers: [.focusThreeWords]).visibleFutureWordCount, 3)

    var lazySession = TypingSession(
      configuration: .init(
        mode: .words, duration: nil, wordLimit: 2, difficulty: .normal, rules: .init(),
        modifiers: [.correctBeforeAdvance]), prompt: "amber bay")
    lazySession.insert("amxer ", at: start)
    XCTAssertEqual(lazySession.typed, "amxer")
    lazySession.deleteBackward(at: start)
    lazySession.deleteBackward(at: start)
    lazySession.deleteBackward(at: start)
    lazySession.insert("ber ", at: start)
    XCTAssertEqual(lazySession.typed, "amber ")

    let noSpaceLazyConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      modifiers: [.noSpaces, .correctBeforeAdvance])
    var noSpaceLazySession = TestSessionFactory.make(
      configuration: noSpaceLazyConfiguration, customText: "amber bay")
    noSpaceLazySession.insert("amxer", at: start)
    XCTAssertEqual(noSpaceLazySession.typed, "amxe")
    noSpaceLazySession.deleteBackward(at: start)
    noSpaceLazySession.deleteBackward(at: start)
    noSpaceLazySession.insert("ber", at: start)
    XCTAssertEqual(noSpaceLazySession.typed, "amber")
  }

  func testRandomCaseModifierChangesOnlyAsciiLetterCaseAndConflictsWithOtherCaseModes() {
    var bits = [true, false, false, true]
    let transformed = RandomCasePolicy.transformed("Ab-cD 7") { bits.removeFirst() }
    XCTAssertEqual(transformed, "Ab-cD 7")

    let randomCase = TestModifierPolicy.transformed("amber bay!", modifiers: [.randomCase])
    XCTAssertEqual(randomCase.lowercased(), "amber bay!")
    XCTAssertEqual(
      TestModifierPolicy.toggling(.randomCase, in: [.uppercase, .noSpaces]),
      [.noSpaces, .randomCase])
    XCTAssertEqual(
      TestModifierPolicy.normalized([.randomCase, .alternatingCase]), [.alternatingCase])
  }

  func testMessagingStyleUsesLowercaseShortLinesAndConflictsWithCaseModes() {
    XCTAssertEqual(
      MessagingTextPolicy.transformed("Hello, World! (Next?) \"Ready.\""),
      "hello, world\n next\n ready")
    XCTAssertEqual(
      TestModifierPolicy.transformed("Hi! There?", modifiers: [.messagingStyle]), "hi\n there")
    XCTAssertEqual(
      TestModifierPolicy.toggling(.messagingStyle, in: [.uppercase, .noSpaces]),
      [.noSpaces, .messagingStyle])
  }

  func testVisualModifiersApplyOnlyToThePracticePresentation() {
    XCTAssertEqual(PracticeVisualTransform.make(modifiers: []), .init(horizontalScale: 1, rotationDegrees: 0))
    XCTAssertEqual(
      PracticeVisualTransform.make(modifiers: [.mirrorVisual]),
      .init(horizontalScale: -1, rotationDegrees: 0))
    XCTAssertEqual(
      PracticeVisualTransform.make(modifiers: [.mirrorVisual, .upsideDownVisual]),
      .init(horizontalScale: -1, rotationDegrees: 180))
    XCTAssertEqual(
      TestModifierPolicy.transformed("amber", modifiers: [.mirrorVisual, .upsideDownVisual]), "amber")
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: []).usesCRT, false)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.crtVisual]).usesCRT, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.earthquakeVisual]).usesEarthquake, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.spaceVisual]).usesSpace, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.nauseaVisual]).usesNausea, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.roundVisual]).usesRound, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.chooVisual]).usesChoo, true)
    XCTAssertEqual(PracticeVisualEffect.make(modifiers: [.aslVisual]).usesASL, true)
    XCTAssertTrue(TestModifierPolicy.normalized([.layoutFluid]).contains(.layoutFluid))
    XCTAssertEqual(LayoutFluidPolicy.maximumLayouts, 15)
    XCTAssertEqual(LayoutFluidPolicy.maximumSupportedLayouts, 15)
    XCTAssertEqual(LayoutFluidPolicy.maximumSupportedLayouts, KeyboardLayout.allCases.count)
    XCTAssertEqual(
      LayoutFluidPolicy.normalizedLayouts(KeyboardLayout.allCases + [.ansiQwerty]),
      KeyboardLayout.allCases)
    XCTAssertEqual(
      EarthquakeOffsetPolicy.offset(at: start, isEnabled: true, reducesMotion: true).x, 0)
    XCTAssertEqual(EarthquakeOffsetPolicy.offset(at: start, isEnabled: false, reducesMotion: false).y, 0)
        let firstStar = StarfieldPolicy.point(index: 0, in: .init(width: 100, height: 100))
        XCTAssertEqual(firstStar.x, 29, accuracy: 0.000_001)
        XCTAssertEqual(firstStar.y, 11.458_333_333_333_334, accuracy: 0.000_001)
    XCTAssertEqual(
      NauseaVisualPolicy.transform(at: start, isEnabled: false, reducesMotion: false), .identity)
    XCTAssertEqual(
      NauseaVisualPolicy.transform(at: start, isEnabled: true, reducesMotion: true), .identity)
    let nauseaTransform = NauseaVisualPolicy.transform(at: start, isEnabled: true, reducesMotion: false)
    XCTAssertNotEqual(nauseaTransform, .identity)
    XCTAssertGreaterThan(nauseaTransform.horizontalScale, 0)
    XCTAssertGreaterThan(nauseaTransform.verticalScale, 0)
    XCTAssertEqual(RoundVisualPolicy.rotationDegrees(at: start, isEnabled: false, reducesMotion: false), 0)
    XCTAssertEqual(RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: true), 0)
    XCTAssertGreaterThanOrEqual(
      RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: false), 0)
    XCTAssertLessThan(
      RoundVisualPolicy.rotationDegrees(at: start, isEnabled: true, reducesMotion: false), 360)
    XCTAssertEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: false, reducesMotion: false), 0)
    XCTAssertEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: true, reducesMotion: true), 0)
    XCTAssertNotEqual(
      ChooVisualPolicy.rotationDegrees(
        at: start, glyphIndex: 4, isEnabled: true, reducesMotion: false), 0)
    XCTAssertEqual(
      LayoutFluidPolicy.activeLayout(
        completedWords: 0, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak]),
      .ansiQwerty)
    XCTAssertEqual(
      LayoutFluidPolicy.activeLayout(
        completedWords: 10, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak]),
      .ansiColemak)
    XCTAssertEqual(
      LayoutFluidPolicy.upcomingLayout(
        completedWords: 8, wordLimit: 30, layouts: [.ansiQwerty, .ansiColemak, .ansiDvorak])?.layout,
      .ansiColemak)
    XCTAssertNotNil(ASLHandshapePolicy.fingerMask(for: "A"))
    XCTAssertNil(ASLHandshapePolicy.fingerMask(for: "7"))
    XCTAssertEqual(ASLHandshapePolicy.motionCue(for: "J"), .jCurve)
    XCTAssertEqual(ASLHandshapePolicy.motionCue(for: "z"), .zZigzag)
    XCTAssertTrue(ASLHandshapePolicy.usesMotionCue(for: "J"))
    XCTAssertTrue(ASLHandshapePolicy.usesMotionCue(for: "z"))
    XCTAssertFalse(ASLHandshapePolicy.usesMotionCue(for: "A"))
  }

  func testListeningModifierPersistsWithoutChangingPromptText() {
    let modifiers = TestModifierPolicy.toggling(.listening, in: [.rot13, .doubleCharacters])
    XCTAssertTrue(modifiers.contains(.listening))
    XCTAssertEqual(
      TestModifierPolicy.transformed("amber harbor", modifiers: modifiers),
      "nnzzoorree uunneeoobbee")
  }

  func testMemoryModifierHidesPromptOnlyAfterTheFirstAcceptedInput() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.memory])
    var session = TypingSession(configuration: configuration, prompt: "amber harbor")

    XCTAssertFalse(session.hasStarted)
    XCTAssertEqual(session.promptGlyphs.first?.state, .current)
    session.insert("a", at: start)
    XCTAssertTrue(session.hasStarted)
    XCTAssertEqual(
      session.promptGlyphs.map(\.state), Array(repeating: .hidden, count: session.prompt.count))

    XCTAssertEqual(
      TestModifierPolicy.toggling(.memory, in: [.listening, .focusNextWord]), [.memory])
    XCTAssertFalse(
      TestConfiguration(
        mode: .zen, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        modifiers: [.memory]
      ).modifiers.contains(.memory))
  }

  func testSimonSaysHidesPendingCharactersButKeepsTheNextExpectedInputAvailable() {
    let configuration = TestConfiguration.words(2).with(modifiers: [.simonSays])
    var session = TypingSession(configuration: configuration, prompt: "amber bay")

    XCTAssertTrue(session.promptGlyphs.allSatisfy { $0.state == .hidden })
    XCTAssertEqual(session.nextExpectedCharacter, "a")
    session.insert("a", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .correct)
    XCTAssertTrue(session.promptGlyphs.dropFirst().allSatisfy { $0.state == .hidden })
    XCTAssertEqual(TestModifierPolicy.toggling(.simonSays, in: [.memory]), [.simonSays])
  }

  func testReadAheadModifiersConcealTheConfiguredCurrentAndFutureWordsAfterStarting() {
    var session = TypingSession(
      configuration: TestConfiguration.words(4).with(modifiers: [.readAhead]),
      prompt: "amber harbor quiet moss")
    XCTAssertEqual(session.promptGlyphs.first?.state, .current)
    session.insert("a", at: start)
    XCTAssertEqual(session.promptGlyphs[0].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[6].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[13].state, .pending)
    session.insert("mber ", at: start)
    XCTAssertEqual(session.promptGlyphs[6].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[13].state, .hidden)
    XCTAssertEqual(session.promptGlyphs[19].state, .pending)
    XCTAssertEqual(
      TestModifierPolicy.toggling(.readAheadHard, in: [.memory, .focusNextWord]), [.readAheadHard])
  }

  func testNoQuitModifierLocksOnlyAnActiveStartedSession() {
    var session = TypingSession(
      configuration: TestConfiguration.words(2).with(modifiers: [.noQuit]), prompt: "amber harbor")
    XCTAssertFalse(TypingRestartPolicy.isLocked(session))
    session.insert("a", at: start)
    XCTAssertTrue(TypingRestartPolicy.isLocked(session))
    session.abandon(at: start)
    XCTAssertFalse(TypingRestartPolicy.isLocked(session))
    XCTAssertTrue(TestModifierPolicy.normalized([.noQuit, .uppercase]).contains(.noQuit))
  }

  func testRepeatingCustomTextSupportsWordAndTimeLimits() {
    let wordConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: 3, difficulty: .normal, rules: .init(),
      customTextCompletion: .words
    )
    var wordSession = TestSessionFactory.make(
      configuration: wordConfiguration, customText: "amber harbor")
    wordSession.insert("amber harbor amber", at: start)
    XCTAssertEqual(wordSession.outcome, .completed)
    XCTAssertEqual(wordSession.configuration.customTextCompletion, .words)

    let timeConfiguration = TestConfiguration(
      mode: .custom, duration: 5, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time
    )
    var timeSession = TestSessionFactory.make(configuration: timeConfiguration, customText: "amber")
    timeSession.insert("amber amber ", at: start)
    XCTAssertTrue(timeSession.prompt.hasPrefix("amber amber amber"))
    XCTAssertEqual(timeSession.outcome, .active)
    timeSession.tick(at: start.addingTimeInterval(5))
    XCTAssertEqual(timeSession.outcome, .completed)
  }

  func testPipeDelimitedCustomTextCompletesTheRequestedSections() {
    let configuration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .sections, customTextSectionLimit: 2
    )
    var session = TestSessionFactory.make(
      configuration: configuration, customText: "amber harbor | quiet meadow | copper lantern")
    XCTAssertEqual(session.prompt, "amber harbor quiet meadow")
    XCTAssertEqual(session.sectionProgress?.total, 2)
    session.insert("amber harbor ", at: start)
    XCTAssertEqual(session.sectionProgress?.completed, 1)
    session.insert("quiet meadow", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(CustomTextPolicy.sections(in: "one|| two | "), ["one", "two"])
  }

  func testSectionedPracticeCyclesWeightedCandidatesAndPreservesChineseSpacing() throws {
    let practice = try XCTUnwrap(
      WordPracticeText.sectionedPractice(
        segments: ["amber", "amber", "cabin"], selectedTargetCount: 2, random: { 0 }))
    let sections = CustomTextPolicy.sections(in: practice.text)
    XCTAssertEqual(practice.sectionCount, 10)
    XCTAssertEqual(sections.count, 10)
    XCTAssertEqual(Set(sections), ["amber", "cabin"])
    XCTAssertEqual(sections.prefix(3).sorted(), ["amber", "amber", "cabin"])
    XCTAssertEqual(sections.dropFirst(3).prefix(3).sorted(), ["amber", "amber", "cabin"])
    XCTAssertEqual(sections.dropFirst(6).prefix(3).sorted(), ["amber", "amber", "cabin"])

    let chineseConfiguration = TestConfiguration(
      mode: .custom, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: .simplifiedChinese, customTextCompletion: .sections, customTextSectionLimit: 2)
    let chineseSession = TestSessionFactory.make(
      configuration: chineseConfiguration, customText: "晨光 | 窗边 | 纸张")
    XCTAssertEqual(chineseSession.prompt, "晨光窗边")
  }

  func testCustomTextOrderingUsesOnlyUserSuppliedTokens() {
    let text = "amber harbor quiet"
    let shuffled = CustomTextOrderPolicy.prompt(from: text, ordering: .shuffled, random: { 1 })
    XCTAssertEqual(
      shuffled.split(separator: " ").map(String.init).sorted(),
      text.split(separator: " ").map(String.init).sorted())
    XCTAssertNotEqual(shuffled, text)

    var randomIndex = 0
    let randomized = CustomTextOrderPolicy.prompt(
      from: text, ordering: .random,
      random: {
        defer { randomIndex += 1 }
        return randomIndex % 3
      })
    XCTAssertTrue(
      randomized.split(separator: " ").map(String.init).allSatisfy(
        ["amber", "harbor", "quiet"].contains))
    XCTAssertGreaterThan(randomized.split(separator: " ").count, 3)
    XCTAssertEqual(CustomTextOrderPolicy.prompt(from: text, ordering: .inOrder), text)
  }

  func testBritishEnglishUsesOnlyTypebarOwnedBritishSpellingCorpus() {
    let configuration = TestConfiguration.words(32, language: .english, englishVariant: .british)
    let session = TestSessionFactory.make(configuration: configuration)
    let words = Set(session.prompt.split(separator: " ").map(String.init))
    XCTAssertTrue(words.isSubset(of: Set(StarterLexicon.britishWords)))
    XCTAssertFalse(words.isEmpty)
  }

  func testGermanUsesOnlyTypebarOwnedUnicodeCorpusAndQuotes() {
    let prompt = OfflineContent.generatedPrompt(
      wordCount: 12, language: .german,
      contentOptions: .init(includePunctuation: true, includeNumbers: true))
    XCTAssertTrue(prompt.contains(" "))
    XCTAssertTrue(
      prompt.split(separator: " ").allSatisfy { token in
        let normalized = token.trimmingCharacters(
          in: CharacterSet.punctuationCharacters.union(.decimalDigits))
        return StarterLexicon.germanWords.contains(normalized)
      })
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .short).count, 1)
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .medium).count, 1)
    XCTAssertEqual(OfflineContent.quotes(for: .german, length: .long).count, 1)
    XCTAssertTrue(TypingLanguage.german.usesSpaceDelimitedWords)
    XCTAssertTrue(TypingLanguage.german.supportsQuotes)
  }

  func testFrenchItalianAndPortugueseUseOnlyTypebarOwnedCorporaAndQuotes() {
    for (language, lexicon) in [
      (TypingLanguage.french, StarterLexicon.frenchWords), (.italian, StarterLexicon.italianWords),
      (.portuguese, StarterLexicon.portugueseWords),
    ] {
      let prompt = OfflineContent.generatedPrompt(
        wordCount: 12, language: language,
        contentOptions: .init(includePunctuation: true, includeNumbers: true))
      XCTAssertTrue(
        prompt.split(separator: " ").allSatisfy { token in
          let normalized = token.trimmingCharacters(
            in: CharacterSet.punctuationCharacters.union(.decimalDigits))
          return lexicon.contains(normalized)
        })
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .short).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .medium).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .long).count, 1)
      XCTAssertEqual(OfflineContent.quotes(for: language, length: .extended).count, 1)
      XCTAssertTrue(language.usesSpaceDelimitedWords)
      XCTAssertTrue(language.supportsQuotes)
    }
  }

  func testLazyLatinModifierNormalizesAccentsLigaturesAndGeneratedPrompts() {
    XCTAssertEqual(TypingTextNormalizer.lazyLatin("árvore Straße cœur Łódź"), "arvore Strasse coeur Lodz")
    let session = TestSessionFactory.make(
      configuration: .words(4, language: .german).with(modifiers: [.lazyLatin]))
    XCTAssertFalse(session.prompt.contains("ä"))
    XCTAssertFalse(session.prompt.contains("ü"))
    XCTAssertFalse(session.prompt.contains("ß"))
  }

  func testNativeSpeechUsesStableSystemLocalesForSupportedLanguages() {
    XCTAssertEqual(TypingLanguage.english.speechLocaleIdentifier, "en-US")
    XCTAssertEqual(TypingLanguage.spanish.speechLocaleIdentifier, "es-ES")
    XCTAssertEqual(TypingLanguage.german.speechLocaleIdentifier, "de-DE")
    XCTAssertEqual(TypingLanguage.french.speechLocaleIdentifier, "fr-FR")
    XCTAssertEqual(TypingLanguage.italian.speechLocaleIdentifier, "it-IT")
    XCTAssertEqual(TypingLanguage.portuguese.speechLocaleIdentifier, "pt-PT")
    XCTAssertEqual(TypingLanguage.simplifiedChinese.speechLocaleIdentifier, "zh-CN")
    XCTAssertEqual(TypingLanguage.mixedEnglishChinese.speechLocaleIdentifier, "zh-CN")
    XCTAssertEqual(TypingLanguage.mixedLanguages.speechLocaleIdentifier, "en-US")
  }

  func testWeakSpotPracticeUsesOnlyTypebarWordsAndCompletedLocalReplayErrors() {
    let result = CompletedTestResult(
      id: UUID(), configuration: .words(2, language: .english), outcome: .completed,
      startedAt: start, finishedAt: start.addingTimeInterval(10), typedCharacterCount: 12,
      correctCharacterCount: 11, errorCount: 1, wpm: 14, rawWpm: 14, accuracy: 92,
      prompt: "amber harbor", replayEvents: [.init(offset: 1, kind: .insert, text: "axber harbor")]
    )
    let prompt = try? XCTUnwrap(
      WeakSpotPractice.prompt(
        results: [result], language: .english, englishVariant: .american, wordCount: 6))
    XCTAssertNotNil(prompt)
    XCTAssertEqual(WeakSpotPractice.characterScores(results: [result], language: .english)["m"], 1)
    XCTAssertTrue(
      prompt?.split(separator: " ").allSatisfy { StarterLexicon.words.contains(String($0)) }
        ?? false)
    XCTAssertTrue(prompt?.contains("amber") ?? false)
    XCTAssertNil(
      WeakSpotPractice.prompt(results: [], language: .english, englishVariant: .american))
    XCTAssertNil(
      WeakSpotPractice.prompt(
        results: [result], language: .simplifiedChinese, englishVariant: .american))
  }

  func testModerationQueueStatesAndReportIdentifiersRemainStable() {
    XCTAssertEqual(
      RemoteQuoteModerationStatus.allCases.map(\.rawValue),
      ["pending", "approved", "rejected"]
    )
    let report = RemoteModerationQuoteReport(
      reason: .inaccurateAttribution,
      note: "Needs source review.",
      submittedAt: start
    )
    XCTAssertEqual(report.reason.displayName, "署名或来源不准确")
    XCTAssertFalse(report.id.isEmpty)
    XCTAssertEqual(RemoteQuoteModerationStatus.pending.displayName, "待审核")
    XCTAssertEqual(
      RemoteProfileModerationStatus.allCases.map(\.rawValue),
      ["open", "resolved", "dismissed"]
    )
    XCTAssertEqual(RemoteProfileModerationStatus.open.displayName, "待处理")
  }

  func testQuoteContentFiltersAndFallsBackByLanguage() {
    let chineseQuotes = OfflineContent.quotes(for: .simplifiedChinese)
    XCTAssertFalse(chineseQuotes.isEmpty)
    XCTAssertTrue(chineseQuotes.allSatisfy { $0.language == .simplifiedChinese })

    let configuration = TestConfiguration(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: .simplifiedChinese)
    let session = TestSessionFactory.make(configuration: configuration)
    XCTAssertEqual(session.prompt, chineseQuotes[0].text)

    let spanishQuotes = OfflineContent.quotes(for: .spanish)
    XCTAssertEqual(spanishQuotes.count, 7)
    XCTAssertTrue(spanishQuotes.allSatisfy { $0.language == .spanish })
    let spanishConfiguration = TestConfiguration.words(
      3, language: .spanish, contentOptions: .init(includePunctuation: true, includeNumbers: true))
    var spanishSession = TypingSession(
      configuration: spanishConfiguration, prompt: "árbol puente calma")
    spanishSession.insert("árbol puente calma", at: start)
    XCTAssertEqual(spanishSession.outcome, .completed)
    XCTAssertTrue(
      OfflineContent.generatedPrompt(
        wordCount: 12, language: .spanish,
        contentOptions: .init(includePunctuation: true, includeNumbers: true)
      ).split(separator: " ").count == 12)
  }

  func testQuoteLengthFiltersAndRepeatPolicyUseOnlyTypebarAuthoredQuotes() {
    let shortEnglish = OfflineContent.quotes(for: .english, length: .short)
    let longChinese = OfflineContent.quotes(for: .simplifiedChinese, length: .long)
    let extendedEnglish = OfflineContent.quotes(for: .english, length: .extended)
    XCTAssertFalse(shortEnglish.isEmpty)
    XCTAssertFalse(longChinese.isEmpty)
    XCTAssertEqual(extendedEnglish.count, 1)
    XCTAssertTrue(shortEnglish.allSatisfy { $0.length == .short && $0.language == .english })
    XCTAssertTrue(
      longChinese.allSatisfy { $0.length == .long && $0.language == .simplifiedChinese })
    XCTAssertTrue(extendedEnglish.allSatisfy { $0.length == .extended && $0.language == .english })

    let current = try! XCTUnwrap(shortEnglish.first)
    let next = OfflineContent.nextQuote(
      from: shortEnglish, currentID: current.id, allowsRepeat: false, index: 0)
    XCTAssertNotEqual(next?.id, current.id)
    let repeated = OfflineContent.nextQuote(
      from: shortEnglish, currentID: current.id, allowsRepeat: true, index: 0)
    XCTAssertEqual(repeated?.id, current.id)
  }

  func testQuoteRestartPolicyRepeatsOnlyAnInProgressQuoteWhenEnabled() {
    XCTAssertTrue(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: true, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: false, hasStarted: true, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: false, isFinished: false))
    XCTAssertFalse(
      QuoteRestartPolicy.shouldKeepCurrent(
        repeatWhileTyping: true, hasStarted: true, isFinished: true))
  }

  func testQuoteQueueCyclesEligibleQuotesWithoutImmediateRepeats() {
    let quotes = [
      OfflineQuote(id: "a", title: "A", text: "A", language: .english, length: .short),
      OfflineQuote(id: "b", title: "B", text: "B", language: .english, length: .medium),
      OfflineQuote(id: "c", title: "C", text: "C", language: .english, length: .long),
    ]
    var queue = QuoteQueue()
    var current = "a"
    var firstCycle: [String] = []

    for _ in quotes.indices {
      let next = try! XCTUnwrap(queue.next(from: quotes, avoiding: current))
      XCTAssertNotEqual(next, current)
      firstCycle.append(next)
      current = next
    }

    XCTAssertEqual(Set(firstCycle), Set(quotes.map(\.id)))
    XCTAssertNotEqual(try! XCTUnwrap(queue.next(from: quotes, avoiding: current)), current)
  }

  func testQuoteLengthSelectionPersistsThroughPresetsAndLegacyConfigurations() throws {
    let selection: Set<QuoteLength> = [.short, .long]
    let configuration = TestConfiguration(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      quoteLengths: selection)
    let preset = SavedTestPreset(configuration: configuration, quoteID: "craft", customText: nil)

    XCTAssertEqual(configuration.effectiveQuoteLengths, selection)
    XCTAssertEqual(configuration.quoteLength, .all)
    XCTAssertEqual(
      try TestConfigurationShare.preset(from: TestConfigurationShare.link(for: preset))
        .configuration.effectiveQuoteLengths,
      selection)

    let legacy = """
      {"mode":"quote","duration":null,"wordLimit":null,"difficulty":"normal","rules":{},"quoteLength":"medium","customTextCompletion":"finish","customTextOrdering":"inOrder","mixedLanguageComponents":["english","spanish"],"modifiers":[],"contentOptions":{"includePunctuation":false,"includeNumbers":false}}
      """
    XCTAssertEqual(
      try JSONDecoder().decode(TestConfiguration.self, from: Data(legacy.utf8)).effectiveQuoteLengths,
      [.medium])
  }

  @MainActor
  func testRemoteAnnouncementCenterPersistsLocalDismissalsButKeepsStickyItems() {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let ordinary = RemoteAnnouncement(
      id: UUID(), message: "A normal update", level: .notice, sticky: false,
      publishedAt: Date(timeIntervalSince1970: 20))
    let sticky = RemoteAnnouncement(
      id: UUID(), message: "A sticky update", level: .warning, sticky: true,
      publishedAt: Date(timeIntervalSince1970: 10))
    let center = RemoteAnnouncementCenter(defaults: defaults)
    center.replace(with: [sticky, ordinary])
    XCTAssertEqual(center.visibleAnnouncements.map(\.id), [ordinary.id, sticky.id])

    center.dismiss(ordinary)
    center.dismiss(sticky)
    XCTAssertEqual(center.visibleAnnouncements.map(\.id), [sticky.id])

    let restored = RemoteAnnouncementCenter(defaults: defaults)
    restored.replace(with: [ordinary, sticky])
    XCTAssertEqual(restored.visibleAnnouncements.map(\.id), [sticky.id])
    restored.replace(with: [])
    restored.replace(with: [ordinary])
    XCTAssertEqual(restored.visibleAnnouncements.map(\.id), [ordinary.id])
  }

  func testEverySingleLanguageHasAnOriginalExtendedQuoteThatBuildsACompleteSession() {
    let languages: [TypingLanguage] = [
      .english, .spanish, .german, .french, .italian, .portuguese, .simplifiedChinese,
    ]
    for language in languages {
      let quote = try! XCTUnwrap(OfflineContent.quotes(for: language, length: .extended).first)
      XCTAssertEqual(quote.language, language)
      XCTAssertEqual(quote.length, .extended)
      XCTAssertGreaterThan(quote.text.count, 120)
      let session = TestSessionFactory.make(
        configuration: .init(
          mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
          language: language, quoteLength: .extended),
        quote: quote)
      XCTAssertEqual(session.prompt, quote.text)
    }
  }

  func testQuoteSearchMatchesAllTermsWithoutSendingOrMutatingContent() {
    let quotes = [
      OfflineQuote(id: "first", title: "Morning Field", text: "A quiet orchard opens at dawn.", language: .english, length: .short),
      OfflineQuote(id: "second", title: "Harbor Note", text: "A bright harbor keeps a careful rhythm.", language: .english, length: .short),
    ]
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "quiet dawn").map(\.id), ["first"])
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "BRIGHT rhythm").map(\.id), ["second"])
    XCTAssertTrue(QuoteSearch.filtered(quotes, query: "quiet harbor").isEmpty)
    XCTAssertEqual(QuoteSearch.filtered(quotes, query: "   ").map(\.id), quotes.map(\.id))
  }

  func testQuoteRatingsPersistAndTreatNeutralAsUnrated() {
    let suite = "quote-rating-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = QuoteRatingStore(defaults: defaults)
    XCTAssertEqual(store.rating(for: "craft"), .neutral)
    store.set(.up, for: "craft")
    XCTAssertEqual(QuoteRatingStore(defaults: defaults).rating(for: "craft"), .up)
    store.set(.neutral, for: "craft")
    XCTAssertEqual(QuoteRatingStore(defaults: defaults).rating(for: "craft"), .neutral)
  }

  func testResultQuoteFeedbackCapturesOnlyTheCompletedQuoteSource() {
    let communityID = UUID()
    XCTAssertEqual(
      QuoteResultFeedbackTarget.make(
        mode: .quote, sourceIsCommunity: false, selectedQuoteID: "craft"),
      .builtIn(quoteID: "craft"))
    XCTAssertEqual(
      QuoteResultFeedbackTarget.make(
        mode: .quote, sourceIsCommunity: true, selectedQuoteID: communityID.uuidString),
      .community(quoteID: communityID))
    XCTAssertEqual(
      QuoteResultFeedbackTarget.make(
        mode: .words, sourceIsCommunity: false, selectedQuoteID: "craft"), nil)
    XCTAssertEqual(
      QuoteResultFeedbackTarget.make(
        mode: .quote, sourceIsCommunity: true, selectedQuoteID: "craft"), nil)
  }

  func testLegacyConfigurationDefaultsToEnglish() throws {
    let legacy = """
      {"mode":"time","duration":30,"wordLimit":null,"difficulty":"normal","rules":{"strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false}}
      """
    let configuration = try JSONDecoder().decode(TestConfiguration.self, from: Data(legacy.utf8))
    XCTAssertEqual(configuration.language, .english)
    XCTAssertEqual(configuration.englishVariant, .american)
    XCTAssertEqual(configuration.quoteLength, .all)
    XCTAssertTrue(configuration.modifiers.isEmpty)
    XCTAssertEqual(configuration.contentOptions, ContentOptions())
  }

  @MainActor
  func testPresetRoundTripsWithAllSessionInputs() throws {
    let container = try ModelContainer(
      for: TestPresetRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    var rules = InputRules()
    rules.strictSpace = true
    rules.minimumWordBurstWpm = 75
    let definition = SavedTestPreset(
      configuration: .init(
        mode: .custom, duration: nil, wordLimit: nil, difficulty: .expert, rules: rules),
      quoteID: nil,
      customText: "a tailored practice",
      activeResultTags: ["focus", "morning"]
    )
    container.mainContext.insert(TestPresetRecord(name: "Focused practice", definition: definition))
    try container.mainContext.save()

    let record = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<TestPresetRecord>()).first)
    XCTAssertEqual(record.name, "Focused practice")
    XCTAssertEqual(record.definition, definition)
    XCTAssertEqual(record.definition?.configuration.rules.minimumWordBurstWpm, 75)
    XCTAssertEqual(record.definition?.activeResultTags, ["focus", "morning"])

    var legacyPayload = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any])
    legacyPayload.removeValue(forKey: "activeResultTags")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)
    XCTAssertNil(try JSONDecoder().decode(SavedTestPreset.self, from: legacyData).activeResultTags)
  }

  func testResultStatisticsAggregateCompletedTests() {
    let day = Date(timeIntervalSinceReferenceDate: 1_000)
    let statistics = ResultStatistics(metrics: [
      .init(finishedAt: day, wpm: 60, accuracy: 95, typingSeconds: 30, consistency: 80),
      .init(
        finishedAt: day.addingTimeInterval(60), wpm: 90, accuracy: 85, typingSeconds: 60,
        consistency: 92),
    ])
    XCTAssertEqual(statistics.completedTests, 2)
    XCTAssertEqual(statistics.averageWPM, 75)
    XCTAssertEqual(statistics.bestWPM, 90)
    XCTAssertEqual(statistics.averageAccuracy, 90)
    XCTAssertEqual(statistics.totalTypingSeconds, 90)
    XCTAssertEqual(statistics.highestConsistency, 92)
    XCTAssertEqual(statistics.averageConsistency, 86)
    XCTAssertEqual(statistics.averageConsistencyLast10, 86)

    let newestFirst = (0...10).map { offset in
      ResultMetric(
        finishedAt: day.addingTimeInterval(Double(-offset)), wpm: 60, accuracy: 95,
        typingSeconds: 30, consistency: Double(100 - offset * 10))
    }
    let recentStatistics = ResultStatistics(metrics: newestFirst)
    XCTAssertEqual(recentStatistics.averageConsistency, 50)
    XCTAssertEqual(recentStatistics.averageConsistencyLast10, 55)
  }

  func testRecentTestAverageUsesTheLatestTenMatchingCurrentSettings() {
    let current = TestConfiguration.words(
      25, difficulty: .expert, language: .english,
      contentOptions: .init(includePunctuation: true, includeNumbers: false)
    )
    let matching = (0..<11).map { offset in
      RecentAverageSample(
        configuration: current, prompt: "generated \(offset)",
        finishedAt: start.addingTimeInterval(TimeInterval(offset)), wpm: 50 + offset,
        accuracy: 80 + offset)
    }
    let differentWordLimit = RecentAverageSample(
      configuration: .words(
        50, difficulty: .expert, language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "other", finishedAt: start.addingTimeInterval(99), wpm: 999, accuracy: 1)
    let quote = TestConfiguration(
      mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
      language: .english)
    let differentQuote = RecentAverageSample(
      configuration: quote, prompt: "another quote", finishedAt: start.addingTimeInterval(100),
      wpm: 999, accuracy: 1)

    let average = RecentTestAveragePolicy.average(
      currentConfiguration: current, currentPrompt: "irrelevant for words",
      samples: matching + [differentWordLimit, differentQuote])
    XCTAssertEqual(average, .init(count: 10, wpm: 56, accuracy: 86))

    XCTAssertNil(
      RecentTestAveragePolicy.average(
        currentConfiguration: quote, currentPrompt: "current quote", samples: [differentQuote]))
    XCTAssertNil(
      RecentTestAveragePolicy.average(
        currentConfiguration: current, currentPrompt: "irrelevant for words", samples: matching,
        limit: 0))
  }

  func testCurrentPersonalBestExcludesIneligibleResultsAndUsesMatchingSettings() {
    let current = TestConfiguration.words(
      25, difficulty: .expert, language: .english,
      contentOptions: .init(includePunctuation: true, includeNumbers: false))
    let eligible = RecentAverageSample(
      configuration: current, prompt: "first", finishedAt: start, wpm: 72, accuracy: 98)
    let best = RecentAverageSample(
      configuration: current, prompt: "second", finishedAt: start.addingTimeInterval(1),
      wpm: 84, accuracy: 93)
    let ineligibleStream = RecentAverageSample(
      configuration: current.with(modifiers: [.zipf]), prompt: "zipf",
      finishedAt: start.addingTimeInterval(2), wpm: 999, accuracy: 100)
    let stoppedWithError = RecentAverageSample(
      configuration: TestConfiguration(
        mode: .words, duration: nil, wordLimit: 25, difficulty: .expert,
        rules: .init(stopOnError: true), language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "stopped", finishedAt: start.addingTimeInterval(3), wpm: 500, accuracy: 99)
    let differentWordLimit = RecentAverageSample(
      configuration: .words(
        50, difficulty: .expert, language: .english,
        contentOptions: .init(includePunctuation: true, includeNumbers: false)),
      prompt: "longer", finishedAt: start.addingTimeInterval(4), wpm: 600, accuracy: 100)

    XCTAssertEqual(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: current, currentPrompt: "ignored", samples: [
          eligible, best, ineligibleStream, stoppedWithError, differentWordLimit,
        ]),
      .init(wpm: 84, accuracy: 93))
    XCTAssertFalse(CurrentPersonalBestPolicy.isConfigurationEligible(current.with(modifiers: [.zipf])))
    XCTAssertFalse(
      CurrentPersonalBestPolicy.isConfigurationEligible(
        .words(25, difficulty: .expert, language: .mixedLanguages)))
    XCTAssertNil(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: current.with(modifiers: [.zipf]), currentPrompt: "ignored",
        samples: [eligible, best]))
    XCTAssertNil(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: TestConfiguration(
          mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
          language: .english), currentPrompt: "quote", samples: [eligible, best]))
  }

  func testCurrentStatisticsUseAnyActiveResultTagButLeaveEmptyStateUnrestricted() {
    let configuration = TestConfiguration.words(25, language: .english)
    let samples = [
      RecentAverageSample(
        configuration: configuration, prompt: "one", finishedAt: start, wpm: 60, accuracy: 95,
        tags: ["morning"]),
      RecentAverageSample(
        configuration: configuration, prompt: "two", finishedAt: start.addingTimeInterval(1),
        wpm: 90, accuracy: 99, tags: ["focus"]),
      RecentAverageSample(
        configuration: configuration, prompt: "three", finishedAt: start.addingTimeInterval(2),
        wpm: 120, accuracy: 100, tags: []),
    ]

    XCTAssertEqual(
      RecentTestAveragePolicy.average(
        currentConfiguration: configuration, currentPrompt: "ignored", samples: samples,
        activeTags: ["FOCUS"]),
      .init(count: 1, wpm: 90, accuracy: 99))
    XCTAssertEqual(
      CurrentPersonalBestPolicy.personalBest(
        currentConfiguration: configuration, currentPrompt: "ignored", samples: samples,
        activeTags: ["morning", "focus"]),
      .init(wpm: 90, accuracy: 99))
    XCTAssertEqual(
      RecentTestAveragePolicy.average(
        currentConfiguration: configuration, currentPrompt: "ignored", samples: samples),
      .init(count: 3, wpm: 90, accuracy: 98))
  }

  func testTagPersonalBestFeedbackUsesOnlyComparableCompletedLocalResults() {
    let configuration = TestConfiguration.words(25, language: .english)
    func result(
      wpm: Int, tags: [String], configuration: TestConfiguration = configuration,
      outcome: TestOutcome = .completed
    ) -> CompletedTestResult {
      .init(
        id: UUID(), configuration: configuration, outcome: outcome, startedAt: start,
        finishedAt: start.addingTimeInterval(30), typedCharacterCount: 100,
        correctCharacterCount: 100, errorCount: 0, wpm: wpm, rawWpm: wpm, accuracy: 100,
        tags: tags)
    }

    let current = result(wpm: 90, tags: ["focus", "review", "fresh"])
    let feedback = TagPersonalBestPolicy.feedback(
      for: current,
      previousResults: [
        result(wpm: 100, tags: ["FOCUS"]),
        result(wpm: 85, tags: ["review"]),
        result(wpm: 250, tags: ["review"], configuration: .words(50, language: .english)),
        result(wpm: 300, tags: ["review"], outcome: .abandoned),
      ])

    XCTAssertEqual(
      feedback,
      [
        .init(tag: "focus", previousBestWpm: 100, currentWpm: 90),
        .init(tag: "review", previousBestWpm: 85, currentWpm: 90),
        .init(tag: "fresh", previousBestWpm: nil, currentWpm: 90),
      ])
    XCTAssertFalse(feedback[0].isNewPersonalBest)
    XCTAssertNil(feedback[0].improvement)
    XCTAssertTrue(feedback[0].showsPreviousBestLine)
    XCTAssertTrue(feedback[1].isNewPersonalBest)
    XCTAssertEqual(feedback[1].improvement, 5)
    XCTAssertFalse(feedback[1].showsPreviousBestLine)
    XCTAssertTrue(feedback[2].isNewPersonalBest)
    XCTAssertFalse(feedback[2].showsPreviousBestLine)
    XCTAssertTrue(TagPersonalBestPolicy.feedback(
      for: result(wpm: 90, tags: ["focus"], configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        language: .english)),
      previousResults: [current]).isEmpty)
  }

  func testResultPersonalBestFeedbackUsesAllComparableCompletedLocalResults() {
    let configuration = TestConfiguration.words(25, language: .english)
    func result(
      wpm: Int, configuration: TestConfiguration = configuration, outcome: TestOutcome = .completed
    ) -> CompletedTestResult {
      .init(
        id: UUID(), configuration: configuration, outcome: outcome, startedAt: start,
        finishedAt: start.addingTimeInterval(30), typedCharacterCount: 100,
        correctCharacterCount: 100, errorCount: 0, wpm: wpm, rawWpm: wpm, accuracy: 100)
    }

    let current = result(wpm: 90)
    let feedback = ResultPersonalBestPolicy.feedback(
      for: current,
      previousResults: [
        result(wpm: 100),
        result(wpm: 85),
        result(wpm: 250, configuration: .words(50, language: .english)),
        result(wpm: 300, outcome: .abandoned),
      ])

    XCTAssertEqual(feedback, .init(previousBestWpm: 100, currentWpm: 90))
    XCTAssertTrue(feedback?.showsPreviousBestLine == true)
    XCTAssertFalse(feedback?.isNewPersonalBest == true)
    let newFeedback = ResultPersonalBestPolicy.feedback(
      for: result(wpm: 110), previousResults: [result(wpm: 100)])
    XCTAssertTrue(newFeedback?.isNewPersonalBest == true)
    XCTAssertEqual(newFeedback?.improvement, 10)
    XCTAssertFalse(newFeedback?.showsPreviousBestLine == true)
    let firstFeedback = ResultPersonalBestPolicy.feedback(
      for: result(wpm: 90), previousResults: [])
    XCTAssertTrue(firstFeedback?.isNewPersonalBest == true)
    XCTAssertNil(firstFeedback?.previousBestWpm)
    XCTAssertNil(ResultPersonalBestPolicy.feedback(
      for: result(wpm: 90, configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        language: .english)),
      previousResults: [current]))
  }

  func testResultPerformanceVisibilityDefaultsPBLinesForLegacySettings() throws {
    let legacy = try JSONDecoder().decode(
      ResultPerformanceVisibility.self,
      from: Data(#"{"raw":false,"burst":false,"errors":true}"#.utf8))

    XCTAssertEqual(
      legacy,
      .init(raw: false, burst: false, errors: true, personalBestLine: true, tagPersonalBestLine: true))
    let restored = try JSONDecoder().decode(
      ResultPerformanceVisibility.self, from: JSONEncoder().encode(legacy))
    XCTAssertEqual(restored, legacy)
  }

  func testWordBurstHeatmapUsesCurrentResultQuintilesAndLeavesMissingBurstsNeutral() throws {
    let heatmap = try XCTUnwrap(
      WordBurstHeatmapPolicy.make(bursts: [20, 40, 60, 80, 100, nil, 0]))

    XCTAssertEqual(heatmap.lowerBounds, [20, 40, 60, 80, 100])
    XCTAssertEqual(
      heatmap.tones,
      [.slow, .measured, .steady, .fast, .swift, .unmeasured, .unmeasured])
    XCTAssertNil(WordBurstHeatmapPolicy.make(bursts: [nil, 0]))
  }

  func testResultPerformanceTraceRebuildsSpeedBurstAndCorrectedErrorsFromReplay() {
    let points = ResultPerformanceTrace.points(
      prompt: "amber",
      events: [
        .init(offset: 0, kind: .insert, text: "a"),
        .init(offset: 1, kind: .insert, text: "m"),
        .init(offset: 2, kind: .insert, text: "x"),
        .init(offset: 3, kind: .delete, text: ""),
        .init(offset: 4, kind: .insert, text: "b"),
      ],
      duration: 4)

    XCTAssertEqual(points.map(\.elapsed), [1, 2, 3, 4])
    XCTAssertEqual(points.map(\.wpm), [24, 12, 8, 9])
    XCTAssertEqual(points.map(\.rawWpm), [24, 18, 8, 9])
    XCTAssertEqual(points.map(\.burstWpm), [36, 24, 36, 12])
    XCTAssertEqual(points.map(\.errorCount), [0, 1, 0, 0])
    XCTAssertEqual(
      ResultPerformanceTrace.points(
        prompt: "amber", events: [.init(offset: 0, kind: .insert, text: "a")], duration: 121),
      [])
  }

  func testOfflineAchievementsAreDerivedFromCompletedLocalMetrics() {
    let metrics = [
      ResultMetric(finishedAt: start, wpm: 84, accuracy: 99, typingSeconds: 16),
      ResultMetric(
        finishedAt: start.addingTimeInterval(60), wpm: 52, accuracy: 92, typingSeconds: 884),
    ]
    let achievements = TypebarAchievementPolicy.achievements(metrics: metrics)
    XCTAssertEqual(
      achievements.filter(\.isUnlocked).map(\.id),
      ["first-finish", "clear-key", "swift-line", "steady-room"])
    XCTAssertEqual(achievements.first(where: { $0.id == "swift-line" })?.progress, "80/80 WPM")

    let empty = TypebarAchievementPolicy.achievements(metrics: [])
    XCTAssertTrue(empty.allSatisfy { !$0.isUnlocked })
    XCTAssertEqual(empty.first?.progress, "0/1")
  }

  func testChallengeEvaluatorReportsEveryUnmetRequirement() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "calm-thirty"))
    let result = CompletedTestResult(
      id: UUID(),
      configuration: challenge.preset.configuration.with(challengeID: challenge.id),
      outcome: .completed,
      startedAt: start,
      finishedAt: start.addingTimeInterval(30),
      typedCharacterCount: 60,
      correctCharacterCount: 50,
      errorCount: 11,
      wpm: 34,
      rawWpm: 40,
      accuracy: 93
    )

    let evaluation = ChallengeEvaluator.evaluate(result, challenge: challenge)

    XCTAssertFalse(evaluation.passed)
    XCTAssertEqual(evaluation.failedRequirements.count, 3)
  }

  func testChallengeEvaluatorPassesWhenEveryRequirementIsMet() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "clean-twenty-five"))
    let result = CompletedTestResult(
      id: UUID(),
      configuration: challenge.preset.configuration.with(challengeID: challenge.id),
      outcome: .completed,
      startedAt: start,
      finishedAt: start.addingTimeInterval(20),
      typedCharacterCount: 100,
      correctCharacterCount: 100,
      errorCount: 0,
      wpm: 60,
      rawWpm: 60,
      accuracy: 100
    )

    XCTAssertTrue(ChallengeEvaluator.evaluate(result, challenge: challenge).passed)
  }

  func testDailyChallengeIsStableForOneCalendarDayAndCyclesLibrary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let morning = ISO8601DateFormatter().date(from: "2026-09-02T01:00:00Z")!
    let evening = ISO8601DateFormatter().date(from: "2026-09-02T23:00:00Z")!
    XCTAssertEqual(
      TypebarChallengeLibrary.dailyChallenge(on: morning, calendar: calendar),
      TypebarChallengeLibrary.dailyChallenge(on: evening, calendar: calendar))
    XCTAssertTrue(
      TypebarChallengeLibrary.all.contains(
        TypebarChallengeLibrary.dailyChallenge(on: morning, calendar: calendar)))
  }

  func testChallengeConfigurationRoundTripsWithoutAffectingLegacyConfiguration() throws {
    let challenge = try XCTUnwrap(TypebarChallengeLibrary.challenge(id: "long-breath"))
    let encoded = try JSONEncoder().encode(
      challenge.preset.configuration.with(challengeID: challenge.id))
    let decoded = try JSONDecoder().decode(TestConfiguration.self, from: encoded)
    XCTAssertEqual(decoded.challengeID, challenge.id)

    let legacy = """
      {"mode":"words","duration":null,"wordLimit":25,"difficulty":"normal","rules":{},"language":"english","englishVariant":"american","quoteLength":"all","customTextCompletion":"finish","customTextOrdering":"inOrder","modifiers":[],"contentOptions":{"includePunctuation":false,"includeNumbers":false}}
      """
    XCTAssertNil(
      try JSONDecoder().decode(TestConfiguration.self, from: Data(legacy.utf8)).challengeID)
  }

  func testRepeatedAttemptRestoresTheInitialPromptAndRepeatSource() {
    let configuration = TestConfiguration(
      mode: .custom, duration: 30, wordLimit: nil, difficulty: .normal, rules: .init(),
      customTextCompletion: .time)
    var session = TypingSession(
      configuration: configuration, prompt: "ember pilot ember pilot", repeatingPrompt: "ember pilot")
    session.insert("ember pilot ember pilot", at: start)

    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.configuration, configuration)
    XCTAssertEqual(repeated.prompt, "ember pilot ember pilot")
    XCTAssertFalse(repeated.hasStarted)
    XCTAssertEqual(repeated.outcome, .active)
    repeated.insert("ember pilot ember pilot", at: start)
    repeated.insert(" ", at: start.addingTimeInterval(1))
    XCTAssertGreaterThan(repeated.prompt.count, "ember pilot ember pilot".count)
  }

  func testWPMHistogramKeepsEmptyIntervalsBetweenSelectedResults() {
    let metrics = [
      ResultMetric(finishedAt: start, wpm: 11, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 19, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 20, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 26, accuracy: 95, typingSeconds: 30),
      ResultMetric(finishedAt: start, wpm: 41, accuracy: 95, typingSeconds: 30),
    ]

    let buckets = WPMHistogram.buckets(metrics: metrics)

    XCTAssertEqual(buckets.map(\.label), ["10–19", "20–29", "30–39", "40–49"])
    XCTAssertEqual(buckets.map(\.count), [2, 2, 0, 1])
  }

  func testResultHistoryFilterCombinesModeLanguageTagContentOptionsAndPersonalBest() {
    let timeEnglish = UUID()
    let wordsEnglish = UUID()
    let wordsChinese = UUID()
    let entries = [
      ResultHistoryEntry(
        id: timeEnglish, mode: .time, language: .english, tags: ["morning"], difficulty: .normal,
        includesPunctuation: false, includesNumbers: false),
      ResultHistoryEntry(
        id: wordsEnglish, mode: .words, language: .english, tags: ["focus"], difficulty: .expert,
        includesPunctuation: true, includesNumbers: false),
      ResultHistoryEntry(
        id: wordsChinese, mode: .words, language: .simplifiedChinese, tags: ["focus", "evening"],
        difficulty: .normal, includesPunctuation: true, includesNumbers: true),
    ]
    let filter = ResultHistoryFilter(
      mode: .words, language: .english, tag: "focus", personalBestOnly: true, difficulty: .expert,
      punctuation: .included, numbers: .excluded)
    XCTAssertEqual(
      filter.matchingIDs(entries: entries, personalBestIDs: [wordsEnglish, wordsChinese]),
      [wordsEnglish])

    let plainContent = ResultHistoryFilter(punctuation: .excluded, numbers: .excluded)
    XCTAssertEqual(plainContent.matchingIDs(entries: entries, personalBestIDs: []), [timeEnglish])

    let all = ResultHistoryFilter()
    XCTAssertEqual(
      all.matchingIDs(entries: entries, personalBestIDs: []),
      Set([timeEnglish, wordsEnglish, wordsChinese]))
  }

  func testResultHistoryBinaryFiltersSupportEveryReferenceToggleCombination() {
    let withBoth = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [],
      includesPunctuation: true, includesNumbers: true)
    let withoutBoth = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [],
      includesPunctuation: false, includesNumbers: false)
    let legacyUnknown = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [],
      includesPunctuation: nil, includesNumbers: nil)
    let entries = [withBoth, withoutBoth, legacyUnknown]

    XCTAssertEqual(
      ResultHistoryFilter(punctuation: .included, numbers: .included).matchingIDs(
        entries: entries, personalBestIDs: []),
      [withBoth.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter(punctuation: .excluded, numbers: .excluded).matchingIDs(
        entries: entries, personalBestIDs: []),
      [withoutBoth.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter(punctuation: .all, numbers: .all).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )
    XCTAssertTrue(
      ResultHistoryFilter(punctuation: .noMatches).matchingIDs(
        entries: entries, personalBestIDs: []).isEmpty)
    XCTAssertTrue(
      ResultHistoryFilter(numbers: .noMatches).matchingIDs(
        entries: entries, personalBestIDs: []).isEmpty)
  }

  func testResultHistoryQuoteLengthUsesTheCompletedPrompt() {
    let completedQuote = OfflineContent.quotes.first { $0.length == .medium }!
    let quote = ResultHistoryEntry(
      id: UUID(), mode: .quote, language: completedQuote.language, tags: [],
      quoteLength: QuoteLengthPolicy.actualLength(
        for: completedQuote.text, language: completedQuote.language))
    let standard = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], quoteLength: nil)

    XCTAssertEqual(quote.quoteLength, .medium)
    XCTAssertEqual(
      ResultHistoryFilter(quoteLength: .medium).matchingIDs(
        entries: [quote, standard], personalBestIDs: []), [quote.id])
    XCTAssertEqual(
      ResultHistoryFilter(quoteLength: .extended).matchingIDs(
        entries: [quote, standard], personalBestIDs: []), [])
    XCTAssertEqual(
      QuoteLengthPolicy.actualLength(for: String(repeating: "x", count: 120), language: .english), .short)
    XCTAssertEqual(
      QuoteLengthPolicy.actualLength(for: String(repeating: "x", count: 121), language: .english), .medium)
    XCTAssertEqual(
      QuoteLengthPolicy.actualLength(for: String(repeating: "x", count: 241), language: .english), .long)
    XCTAssertEqual(
      QuoteLengthPolicy.actualLength(for: String(repeating: "x", count: 481), language: .english), .extended)
  }

  func testResultHistoryQuoteLengthFilterSupportsMultiSelectAndReferenceFallbackBucket() throws {
    let short = ResultHistoryEntry(
      id: UUID(), mode: .quote, language: .english, tags: [], quoteLength: .short)
    let medium = ResultHistoryEntry(
      id: UUID(), mode: .quote, language: .english, tags: [], quoteLength: .medium)
    let long = ResultHistoryEntry(
      id: UUID(), mode: .quote, language: .english, tags: [], quoteLength: .long)
    let standard = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], quoteLength: nil)
    let entries = [short, medium, long, standard]

    XCTAssertEqual(
      ResultHistoryFilter(quoteLengths: [.short, .long]).matchingIDs(
        entries: entries, personalBestIDs: []),
      [short.id, long.id, standard.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter(quoteLengths: ResultHistoryFilter.filterableQuoteLengths).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )
    XCTAssertEqual(
      ResultHistoryFilter(quoteLengths: []).matchingIDs(entries: entries, personalBestIDs: []),
      [standard.id]
    )
    XCTAssertEqual(ResultHistoryFilter.quoteLengthSelectionSummary([]), "仅非引语")

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"quoteLength":"long"}"#.utf8))
    XCTAssertNil(legacy.quoteLengths)
    XCTAssertEqual(
      legacy.matchingIDs(entries: entries, personalBestIDs: []), [long.id])
  }

  func testResultHistoryTimeAndWordLimitsSupportMultiSelectAndCustomValues() {
    let fifteenSeconds = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .english, tags: [], duration: 15)
    let thirtySeconds = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .english, tags: [], duration: 30)
    let customSeconds = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .english, tags: [], duration: 45)
    let tenWords = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], wordLimit: 10)
    let fiftyWords = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], wordLimit: 50)
    let customWords = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], wordLimit: 200)
    let quote = ResultHistoryEntry(id: UUID(), mode: .quote, language: .english, tags: [])
    let filter = ResultHistoryFilter(
      timeLimits: [.seconds15, .custom], wordLimits: [.words50, .custom])

    XCTAssertEqual(
      filter.matchingIDs(
        entries: [fifteenSeconds, thirtySeconds, customSeconds, tenWords, fiftyWords, customWords, quote],
        personalBestIDs: []),
      [fifteenSeconds.id, customSeconds.id, fiftyWords.id, customWords.id, quote.id])
    XCTAssertEqual(
      ResultHistoryFilter(timeLimits: [], wordLimits: []).matchingIDs(
        entries: [fifteenSeconds, thirtySeconds, customSeconds, tenWords, fiftyWords, customWords, quote],
        personalBestIDs: []),
      [quote.id])
    XCTAssertTrue(ResultHistoryTimeLimit.selectionSummary([]).contains("无匹配"))
    XCTAssertEqual(ResultHistoryWordLimit.selectionSummary(Set(ResultHistoryWordLimit.allCases)), "全部")
  }

  func testResultHistoryModifierFilterMatchesNoModifierAndAnySelectedModifier() {
    let plain = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [], modifiers: [])
    let crt = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], modifiers: [.crtVisual])
    let binary = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], modifiers: [.binaryStream])
    let combined = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [],
      modifiers: [.uppercase, .crtVisual])
    let entries = [plain, crt, binary, combined]

    let noModifierOrBinary = ResultHistoryFilter(
      modifierFilter: .init(includesNoModifiers: true, modifiers: [.binaryStream]))
    XCTAssertEqual(
      noModifierOrBinary.matchingIDs(entries: entries, personalBestIDs: []), [plain.id, binary.id])

    let crtOnly = ResultHistoryFilter(
      modifierFilter: .init(includesNoModifiers: false, modifiers: [.crtVisual]))
    XCTAssertEqual(crtOnly.matchingIDs(entries: entries, personalBestIDs: []), [crt.id, combined.id])
    XCTAssertEqual(
      ResultHistoryFilter(modifierFilter: .init(includesNoModifiers: false, modifiers: [])).matchingIDs(
        entries: entries, personalBestIDs: []), [])
  }

  func testResultHistoryCurrentSettingsFilterUsesLocalConfigurationSemantics() {
    var contentOptions = ContentOptions()
    contentOptions.includePunctuation = true
    let configuration = TestConfiguration.timed(
      seconds: 60, difficulty: .expert, language: .spanish, contentOptions: contentOptions
    ).with(modifiers: [.crtVisual, .binaryStream])
    let filter = ResultHistoryFilter.currentSettings(configuration, activeTags: ["focus"])
    let matching = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .spanish, tags: ["focus"],
      difficulty: .expert, includesPunctuation: true, includesNumbers: false,
      duration: 60, modifiers: [.crtVisual])
    let untagged = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .spanish, tags: [], difficulty: .expert,
      includesPunctuation: true, includesNumbers: false, duration: 60, modifiers: [.crtVisual])
    let wrongDuration = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .spanish, tags: [], difficulty: .expert,
      includesPunctuation: true, includesNumbers: false, duration: 30, modifiers: [.crtVisual])
    let missingModifier = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .spanish, tags: [], difficulty: .expert,
      includesPunctuation: true, includesNumbers: false, duration: 60, modifiers: [])
    let wrongLanguage = ResultHistoryEntry(
      id: UUID(), mode: .time, language: .english, tags: [], difficulty: .expert,
      includesPunctuation: true, includesNumbers: false, duration: 60, modifiers: [.crtVisual])

    XCTAssertEqual(
      filter.matchingIDs(
        entries: [matching, untagged, wrongDuration, missingModifier, wrongLanguage], personalBestIDs: []),
      [matching.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter.currentSettings(configuration).matchingIDs(
        entries: [matching, untagged, wrongDuration, missingModifier, wrongLanguage],
        personalBestIDs: []),
      [untagged.id]
    )
    XCTAssertEqual(filter.quoteLength, nil)
    XCTAssertEqual(filter.languageSelections, [.spanish])
    XCTAssertEqual(filter.timeLimits, [.seconds60])
    XCTAssertEqual(filter.wordLimits, Set(ResultHistoryWordLimit.allCases))

    let quoteFilter = ResultHistoryFilter.currentSettings(
      .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init(),
        quoteLength: .long
      )
    )
    XCTAssertEqual(quoteFilter.quoteLengthSelections, [.long])
  }

  func testResultHistoryLanguageFilterSupportsMultiSelectAndLegacySingleLanguagePresets() throws {
    let english = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [])
    let spanish = ResultHistoryEntry(id: UUID(), mode: .words, language: .spanish, tags: [])
    let german = ResultHistoryEntry(id: UUID(), mode: .words, language: .german, tags: [])
    let legacyUnknown = ResultHistoryEntry(id: UUID(), mode: .words, language: nil, tags: [])
    let entries = [english, spanish, german, legacyUnknown]

    let multiLanguage = ResultHistoryFilter(languages: [.english, .spanish])
    XCTAssertEqual(
      multiLanguage.matchingIDs(entries: entries, personalBestIDs: []),
      [english.id, spanish.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter.languageSelectionSummary([.english, .spanish]), "English、Español")
    XCTAssertEqual(
      ResultHistoryFilter(languages: Set(TypingLanguage.allCases)).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"language":"german"}"#.utf8))
    XCTAssertNil(legacy.languages)
    XCTAssertEqual(legacy.languageSelections, [.german])
  }

  func testResultHistoryModeFilterSupportsMultiSelectAndLegacySingleModePresets() throws {
    let timed = ResultHistoryEntry(id: UUID(), mode: .time, language: .english, tags: [])
    let words = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [])
    let quote = ResultHistoryEntry(id: UUID(), mode: .quote, language: .english, tags: [])
    let legacyUnknown = ResultHistoryEntry(id: UUID(), mode: nil, language: .english, tags: [])
    let entries = [timed, words, quote, legacyUnknown]

    let multiMode = ResultHistoryFilter(modes: [.time, .words])
    XCTAssertEqual(
      multiMode.matchingIDs(entries: entries, personalBestIDs: []),
      [timed.id, words.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter.modeSelectionSummary([.time, .words]), "时间、字数")
    XCTAssertEqual(
      ResultHistoryFilter(modes: Set(TestMode.allCases)).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )
    XCTAssertTrue(
      ResultHistoryFilter(modes: []).matchingIDs(entries: entries, personalBestIDs: []).isEmpty)

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"mode":"quote"}"#.utf8))
    XCTAssertNil(legacy.modes)
    XCTAssertEqual(legacy.modeSelections, [.quote])
  }

  func testResultHistoryDifficultyFilterSupportsMultiSelectAndLegacySingleDifficultyPresets() throws {
    let normal = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], difficulty: .normal)
    let expert = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], difficulty: .expert)
    let master = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], difficulty: .master)
    let legacyUnknown = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: [], difficulty: nil)
    let entries = [normal, expert, master, legacyUnknown]

    let multiDifficulty = ResultHistoryFilter(difficulties: [.normal, .expert])
    XCTAssertEqual(
      multiDifficulty.matchingIDs(entries: entries, personalBestIDs: []),
      [normal.id, expert.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter.difficultySelectionSummary([.normal, .expert]), "普通、专家")
    XCTAssertEqual(
      ResultHistoryFilter(difficulties: Set(Difficulty.allCases)).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )
    XCTAssertTrue(
      ResultHistoryFilter(difficulties: []).matchingIDs(entries: entries, personalBestIDs: []).isEmpty)

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"difficulty":"master"}"#.utf8))
    XCTAssertNil(legacy.difficulties)
    XCTAssertEqual(legacy.difficultySelections, [.master])
  }

  func testResultHistoryTagFilterSupportsNoTagAnyTagAndLegacySingleTagPresets() throws {
    let noTags = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [])
    let focus = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: ["focus"])
    let review = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: ["review"])
    let both = ResultHistoryEntry(
      id: UUID(), mode: .words, language: .english, tags: ["focus", "review"])
    let entries = [noTags, focus, review, both]

    let noTagOrFocus = ResultHistoryFilter(
      tagFilter: .init(isUnrestricted: false, includesNoTags: true, tags: ["focus"]))
    XCTAssertEqual(
      noTagOrFocus.matchingIDs(entries: entries, personalBestIDs: []),
      [noTags.id, focus.id, both.id]
    )
    XCTAssertEqual(noTagOrFocus.effectiveTagFilter.selectionSummary, "无标签、focus")
    XCTAssertEqual(
      ResultHistoryFilter(tagFilter: .init(isUnrestricted: true)).matchingIDs(
        entries: entries, personalBestIDs: []),
      Set(entries.map(\.id))
    )
    XCTAssertTrue(
      ResultHistoryFilter(
        tagFilter: .init(isUnrestricted: false, includesNoTags: false, tags: [])
      ).matchingIDs(entries: entries, personalBestIDs: []).isEmpty)

    var allTags = ResultHistoryTagFilter()
    allTags.setTag("focus", selected: false, availableTags: ["focus", "review"])
    XCTAssertFalse(allTags.isUnrestricted)
    XCTAssertTrue(allTags.includesNoTags)
    XCTAssertEqual(allTags.tags, ["review"])

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"tag":"review"}"#.utf8))
    XCTAssertNil(legacy.tagFilter)
    XCTAssertEqual(
      legacy.matchingIDs(entries: entries, personalBestIDs: []), [review.id, both.id])
  }

  func testResultHistoryPersonalBestFilterSupportsAllStatesAndLegacyBooleanPresets() throws {
    let personalBest = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [])
    let ordinary = ResultHistoryEntry(id: UUID(), mode: .words, language: .english, tags: [])
    let entries = [personalBest, ordinary]
    let personalBestIDs: Set<UUID> = [personalBest.id]

    XCTAssertEqual(
      ResultHistoryFilter(personalBestFilter: .only).matchingIDs(
        entries: entries, personalBestIDs: personalBestIDs),
      [personalBest.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter(personalBestFilter: .excluded).matchingIDs(
        entries: entries, personalBestIDs: personalBestIDs),
      [ordinary.id]
    )
    XCTAssertEqual(
      ResultHistoryFilter(personalBestFilter: .all).matchingIDs(
        entries: entries, personalBestIDs: personalBestIDs),
      Set(entries.map(\.id))
    )
    XCTAssertTrue(
      ResultHistoryFilter(personalBestFilter: .noMatches).matchingIDs(
        entries: entries, personalBestIDs: personalBestIDs).isEmpty)

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"personalBestOnly":true}"#.utf8))
    XCTAssertNil(legacy.personalBestFilter)
    XCTAssertEqual(legacy.effectivePersonalBestFilter, .only)
  }

  func testResultHistoryDateRangesUseReferenceRollingWindowsAndPreserveLegacyPresets() throws {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let onBoundary = UUID()
    let recent = UUID()
    let stale = UUID()
    let entries = [
      ResultHistoryEntry(
        id: onBoundary, mode: .time, language: .english, tags: [],
        finishedAt: now.addingTimeInterval(-24 * 60 * 60)),
      ResultHistoryEntry(
        id: recent, mode: .time, language: .english, tags: [],
        finishedAt: now.addingTimeInterval(-24 * 60 * 60 + 1)),
      ResultHistoryEntry(
        id: stale, mode: .time, language: .english, tags: [],
        finishedAt: now.addingTimeInterval(-24 * 60 * 60 - 1)),
    ]
    let lastDay = ResultHistoryFilter(dateRange: .lastDay)
    XCTAssertEqual(
      lastDay.matchingIDs(entries: entries, personalBestIDs: [], now: now), [onBoundary, recent])
    XCTAssertNil(ResultHistoryDateRange.all.cutoff(relativeTo: now))
    XCTAssertEqual(
      ResultHistoryDateRange.lastThreeMonths.cutoff(relativeTo: now),
      now.addingTimeInterval(-90 * 24 * 60 * 60))

    let legacy = try JSONDecoder().decode(
      ResultHistoryFilter.self, from: Data(#"{"personalBestOnly":true}"#.utf8))
    XCTAssertTrue(legacy.personalBestOnly)
    XCTAssertNil(legacy.difficulty)
    XCTAssertEqual(legacy.dateRange, .all)
    XCTAssertEqual(legacy.punctuation, .all)
    XCTAssertEqual(legacy.numbers, .all)
    XCTAssertNil(legacy.quoteLength)
    XCTAssertEqual(legacy.timeLimits, Set(ResultHistoryTimeLimit.allCases))
    XCTAssertEqual(legacy.wordLimits, Set(ResultHistoryWordLimit.allCases))
    XCTAssertTrue(legacy.modifierFilter.isUnfiltered)
  }

  func testPersonalBestMarksEveryTiedHighestResult() {
    let first = UUID()
    let second = UUID()
    let third = UUID()
    let best = ResultStatistics.personalBestIDs(metrics: [
      .init(id: first, finishedAt: start, wpm: 70, accuracy: 95, typingSeconds: 30),
      .init(id: second, finishedAt: start, wpm: 92, accuracy: 90, typingSeconds: 30),
      .init(id: third, finishedAt: start, wpm: 92, accuracy: 98, typingSeconds: 30),
    ])
    XCTAssertEqual(best, [second, third])
  }

  func testArchiveRoundTripsIndependentLocalData() throws {
    let settings = AppSettingsSnapshot(fontSize: 32)
    let result = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), afkDuration: 7, typedCharacterCount: 50,
      correctCharacterCount: 48, errorCount: 2, wpm: 19, rawWpm: 20, accuracy: 96)
    let preset = NamedPreset(
      name: "Short", definition: .init(configuration: .words(10), quoteID: nil, customText: nil))
    let savedTexts = [
      NamedSavedText(title: "Notes", text: "An original text for focused practice."),
      NamedSavedText(title: "Chapter", text: "amber harbor willow", longProgress: 6),
    ]
    let data = try TypebarDataTransfer.exportArchive(
      settings: settings, results: [result], presets: [preset], savedTexts: savedTexts, at: start)
    let archive = try TypebarDataTransfer.importArchive(from: data)
    XCTAssertEqual(archive.settings, settings)
    XCTAssertEqual(archive.results, [result])
    XCTAssertEqual(archive.presets, [preset])
    XCTAssertEqual(archive.savedTexts, savedTexts)
  }

  func testCompletedResultDecodesArchivesWrittenBeforeInactivityTracking() throws {
    let result = CompletedTestResult(
      id: UUID(), configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), afkDuration: 7, typedCharacterCount: 50,
      correctCharacterCount: 48, errorCount: 2, wpm: 19, rawWpm: 20, accuracy: 96)
    let encoded = try JSONEncoder().encode(result)
    var legacyPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacyPayload.removeValue(forKey: "afkDuration")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyPayload)

    let restored = try JSONDecoder().decode(CompletedTestResult.self, from: legacyData)
    XCTAssertEqual(restored.afkDuration, 0)
    XCTAssertEqual(restored.engagedDuration, 30)
    XCTAssertEqual(restored.afkPercentage, 0)
  }

  func testArchiveMergeSkipsExistingResultsAndPresets() {
    let existingID = UUID()
    let retainedResult = CompletedTestResult(
      id: existingID, configuration: .timed(seconds: 30), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(30), typedCharacterCount: 50, correctCharacterCount: 50,
      errorCount: 0, wpm: 20, rawWpm: 20, accuracy: 100)
    let newResult = CompletedTestResult(
      id: UUID(), configuration: .words(10), outcome: .completed, startedAt: start,
      finishedAt: start.addingTimeInterval(20), typedCharacterCount: 50, correctCharacterCount: 49,
      errorCount: 1, wpm: 29, rawWpm: 30, accuracy: 98)
    let existingPreset = NamedPreset(
      name: "Short", definition: .init(configuration: .words(10), quoteID: nil, customText: nil))
    let newPreset = NamedPreset(
      name: "Long",
      definition: .init(configuration: .timed(seconds: 120), quoteID: nil, customText: nil))
    let existingText = NamedSavedText(title: "Existing", text: "Already here")
    let newText = NamedSavedText(title: "New", text: "Bring this one in")
    let archive = TypebarArchive(
      version: 2, exportedAt: start, settings: .init(), results: [retainedResult, newResult],
      presets: [existingPreset, newPreset], savedTexts: [existingText, newText])

    XCTAssertEqual(
      TypebarArchiveMerge.resultsToInsert(from: archive, existingIDs: [existingID]), [newResult])
    XCTAssertEqual(
      TypebarArchiveMerge.presetsToInsert(from: archive, existing: [existingPreset]), [newPreset])
    XCTAssertEqual(
      TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [existingText]), [newText])
  }

  func testVersionOneArchiveImportsWithoutSavedTexts() throws {
    let oldArchive = """
      {"version":1,"exportedAt":"2001-01-01T02:46:40Z","settings":{"difficulty":"normal","strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false,"fontSize":28},"results":[],"presets":[]}
      """
    let archive = try TypebarDataTransfer.importArchive(from: Data(oldArchive.utf8))
    XCTAssertEqual(archive.version, 1)
    XCTAssertTrue(archive.savedTexts.isEmpty)
  }

  func testSavedTextArchiveDefaultsMissingLongProgressToAnOrdinaryText() throws {
    let data = Data("{\"title\":\"Notes\",\"text\":\"A local passage\"}".utf8)
    let savedText = try JSONDecoder().decode(NamedSavedText.self, from: data)
    XCTAssertNil(savedText.longProgress)
  }

  func testDailyActivityGroupsMetricsByCalendarDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let metrics = [
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 86_400 + 60), wpm: 40, accuracy: 90,
        typingSeconds: 30, consistency: 70),
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 86_400 + 3_600), wpm: 50, accuracy: 90,
        typingSeconds: 45, consistency: 90),
      ResultMetric(
        finishedAt: Date(timeIntervalSince1970: 172_800 + 60), wpm: 60, accuracy: 90,
        typingSeconds: 15, consistency: 50),
    ]
    let activity = ActivityAggregation.daily(metrics: metrics, calendar: calendar)
    XCTAssertEqual(activity.map(\.completedTests), [2, 1])
    XCTAssertEqual(activity.map(\.typingSeconds), [75, 15])
    XCTAssertEqual(activity.map(\.averageConsistency), [80, 50])
  }

  func testRecentActivityBarsFillEveryRequestedDayWithoutCollapsingGaps() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(
        day: end.addingTimeInterval(-172_800), completedTests: 2, typingSeconds: 75,
        averageConsistency: 80),
      DailyActivity(day: end, completedTests: 1, typingSeconds: 30, averageConsistency: 50),
    ]

    let points = ActivityAggregation.recentDays(
      activity: activity, days: 4, endingAt: end, calendar: calendar)

    XCTAssertEqual(points.map(\.completedTests), [0, 2, 0, 1])
    XCTAssertEqual(points.map(\.typingSeconds), [0, 75, 0, 30])
    XCTAssertEqual(points.map(\.averageConsistency), [0, 80, 0, 50])
    XCTAssertEqual(
      points.map(\.day),
      [
        end.addingTimeInterval(-259_200),
        end.addingTimeInterval(-172_800),
        end.addingTimeInterval(-86_400),
        end,
      ])
  }

  func testCurrentStreakOnlyCountsConsecutiveDaysEndingToday() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let today = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(day: today, completedTests: 1, typingSeconds: 10),
      DailyActivity(day: today.addingTimeInterval(-86_400), completedTests: 1, typingSeconds: 10),
      DailyActivity(day: today.addingTimeInterval(-259_200), completedTests: 1, typingSeconds: 10),
    ]
    XCTAssertEqual(
      ActivityAggregation.currentStreak(activity: activity, today: today, calendar: calendar), 2)
  }

  func testPracticeDayBoundaryMovesActivityChartsAndStreakTogether() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    XCTAssertTrue(StreakDayBoundaryPolicy.isSupported(-11))
    XCTAssertTrue(StreakDayBoundaryPolicy.isSupported(12))
    XCTAssertFalse(StreakDayBoundaryPolicy.isSupported(-11.5))
    XCTAssertFalse(StreakDayBoundaryPolicy.isSupported(3.25))
    XCTAssertEqual(StreakDayBoundaryPolicy.normalized(99), 12)
    let day = Date(timeIntervalSince1970: 86_400)
    let metrics = [
      ResultMetric(
        finishedAt: day.addingTimeInterval(2.5 * 3_600), wpm: 40, accuracy: 90,
        typingSeconds: 10),
      ResultMetric(
        finishedAt: day.addingTimeInterval(3.5 * 3_600), wpm: 60, accuracy: 95,
        typingSeconds: 20),
    ]
    let activity = ActivityAggregation.daily(
      metrics: metrics, dayBoundaryOffsetHours: 3, calendar: calendar)

    XCTAssertEqual(activity.map(\.day), [Date(timeIntervalSince1970: 0), day])
    XCTAssertEqual(activity.map(\.completedTests), [1, 1])
    let nextDayBeforeBoundary = day.addingTimeInterval(86_400 + 2 * 3_600)
    XCTAssertEqual(
      ActivityAggregation.currentStreak(
        activity: activity, today: nextDayBeforeBoundary, dayBoundaryOffsetHours: 3,
        calendar: calendar),
      2)
    XCTAssertEqual(
      ActivityAggregation.recentDays(
        activity: activity, days: 2, endingAt: nextDayBeforeBoundary, dayBoundaryOffsetHours: 3,
        calendar: calendar).map(\.completedTests),
      [1, 1])
    XCTAssertEqual(
      ActivityHeatmap.cells(
        activity: activity, days: 2, endingAt: nextDayBeforeBoundary, dayBoundaryOffsetHours: 3,
        calendar: calendar).map(\.completedTests),
      [1, 1])
  }

  func testHeatmapIncludesEmptyDaysAndMapsIntensity() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let end = Date(timeIntervalSince1970: 345_600)
    let activity = [
      DailyActivity(day: end.addingTimeInterval(-86_400), completedTests: 1, typingSeconds: 10),
      DailyActivity(day: end, completedTests: 5, typingSeconds: 50),
    ]
    let cells = ActivityHeatmap.cells(
      activity: activity, days: 4, endingAt: end, calendar: calendar)

    XCTAssertEqual(cells.map(\.completedTests), [0, 0, 1, 5])
    XCTAssertEqual(cells.map(\.intensity), [0, 0, 1, 3])
  }

  @MainActor
  func testAppSettingsPersistAndRestore() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.difficulty = .master
    settings.strictSpace = true
    settings.deleteOnError = true
    settings.blindMode = true
    settings.fontSize = 34
    settings.practiceFont = .serif
    settings.installedPracticeFontName = NativePracticeFont.fallbackPostScriptName
    settings.theme = .midnight
    settings.publishCompletedResults = true
    settings.saveCompletedResults = false
    settings.keyboardLayout = .ansiDvorak
    settings.keyboardInputLayout = .swissGerman
    let customKeyboard = try XCTUnwrap(settings.addCustomKeyboardLayout(
      name: "Cyrillic", numberRow: "123", topRow: "ЙЦУ", homeRow: "ФЫВ", bottomRow: "ЯЧС"))
    XCTAssertEqual(settings.keyboardGuideLayoutSource, .custom)
    settings.keyboardGuideLayoutSource = .systemInput
    settings.layoutFluidLayouts = [.ansiWorkman, .frenchAzerty, .ansiQwerty]
    settings.quickEnd = true
    settings.quickRestartKey = .enter
    settings.showKeyTips = false
    settings.commandPaletteListMode = .grouped
    settings.systemLightTheme = .paper
    settings.systemDarkTheme = .grove
    settings.practiceBackdrop = .halos
    settings.reducePracticeMotion = true
    settings.showTypingCompanion = true
    settings.typingPowerMode = .over9000
    settings.toggleFavoriteTheme(.grove)
    settings.addCustomTheme(
      name: "Harbour", background: .black, panel: .gray, accent: .orange, prefersDark: true)
    let customThemeID = try XCTUnwrap(settings.customThemes.first?.id)
    settings.toggleFavoriteCustomTheme(customThemeID)
    settings.randomThemeMode = .custom
    settings.flipTestColors = true
    settings.colorfulMode = true
    settings.customBackgroundURL = "https://images.example.test/harbour.jpeg"
    settings.customBackgroundFit = .contain
    settings.customBackgroundFilter = .init(blur: 4, brightness: 0.85, saturation: 1.4, opacity: 0.7)
    settings.englishVariant = .british
    settings.freedomMode = true
    settings.confidenceMode = .maximum
    settings.oppositeShiftMode = .keymap
    settings.codeUnindentOnBackspace = true
    settings.minimumAccuracy = 97
    settings.minimumWpm = 85
    settings.minimumWordBurstWpm = 85
    settings.minimumWordBurstMode = .flex
    settings.practiceLineWidth = .wide
    settings.customPracticeLineColumns = 112
    settings.practiceTapeMode = .letter
    settings.practiceTapeMargin = 0.35
    settings.smoothPracticeLineScroll = false
    settings.showAllPracticeLines = true
    settings.smoothCaretMotion = .fast
    settings.caretStyle = .monkey
    settings.typoIndicatorStyle = .both
    settings.compositionDisplayStyle = .below
    settings.typingSpeedUnit = .cps
    settings.alwaysShowDecimalPlaces = true
    settings.alwaysShowWordsHistory = true
    settings.showWordBurstHeatmap = true
    settings.resultPerformanceVisibility = .init(raw: false, burst: false, errors: true)
    settings.startGraphsAtZero = false
    settings.mutateHistoryChartVisibility {
      $0.accuracy = false
      $0.average100 = false
    }
    settings.showAverage = .both
    settings.showPersonalBest = true
    settings.typedCharacterEffect = .dots
    settings.liveSpeedStyle = .mini
    settings.liveAccuracyStyle = .off
    settings.liveBurstStyle = .mini
    settings.liveProgressStyle = .flashMini
    settings.liveStatsColor = .black
    settings.liveStatsOpacity = .half
    settings.promptHighlightMode = .nextTwoWords
    settings.testModifiers = [.noSpaces, .uppercase]
    settings.favoriteQuoteIDs = ["craft"]
    settings.repeatQuotes = true
    settings.showKeyboardGuide = true
    settings.keyboardGuideMode = .react
    settings.keyboardGuideScale = 2.7
    settings.keyboardGuideLegendStyle = .dynamic
    settings.keyboardGuideKeysMode = .full
    settings.keyboardGuideStyle = .alice
    settings.showFocusWarning = false
    settings.showCapsLockWarning = false
    settings.playErrorBeep = true
    settings.playKeyclickSound = true
    settings.clickSoundStyle = .morse
    settings.errorSoundStyle = .submarine
    settings.timeWarningOffset = .threeSeconds
    settings.timeWarningSoundStyle = .frog
    settings.soundVolume = 0.4
    settings.globalHotkeyEnabled = true
    settings.paceGuideMode = .custom
    settings.paceGuideCustomWpm = 95
    settings.paceCaretStyle = .off
    settings.repeatedPace = true
    XCTAssertTrue(settings.setStreakDayBoundary(offsetHours: 3.5))
    XCTAssertFalse(settings.setStreakDayBoundary(offsetHours: 4))

    let exportedSnapshot = settings.snapshot
    XCTAssertTrue(exportedSnapshot.codeUnindentOnBackspace)
    XCTAssertEqual(exportedSnapshot.keyboardGuideMode, .react)
    XCTAssertEqual(exportedSnapshot.keyboardGuideScale, 2.7)
    XCTAssertEqual(exportedSnapshot.keyboardGuideLegendStyle, .dynamic)
    XCTAssertEqual(exportedSnapshot.keyboardGuideKeysMode, .full)
    XCTAssertEqual(exportedSnapshot.keyboardGuideStyle, .alice)
    XCTAssertEqual(exportedSnapshot.keyboardInputLayout, .swissGerman)
    XCTAssertEqual(exportedSnapshot.customKeyboardLayouts, [customKeyboard])
    XCTAssertEqual(exportedSnapshot.customKeyboardLayoutID, customKeyboard.id)
    XCTAssertEqual(exportedSnapshot.keyboardGuideLayoutSource, .systemInput)
    XCTAssertEqual(exportedSnapshot.randomThemeMode, .custom)
    XCTAssertFalse(exportedSnapshot.showKeyTips)
    XCTAssertEqual(exportedSnapshot.commandPaletteListMode, .grouped)
    XCTAssertEqual(exportedSnapshot.systemLightTheme, .paper)
    XCTAssertEqual(exportedSnapshot.systemDarkTheme, .grove)
    XCTAssertTrue(exportedSnapshot.flipTestColors)
    XCTAssertTrue(exportedSnapshot.colorfulMode)
    XCTAssertEqual(exportedSnapshot.customBackgroundURL, "https://images.example.test/harbour.jpeg")
    XCTAssertEqual(exportedSnapshot.customBackgroundFit, .contain)
    XCTAssertEqual(exportedSnapshot.customBackgroundFilter, .init(blur: 4, brightness: 0.85, saturation: 1.4, opacity: 0.7))
    XCTAssertTrue(exportedSnapshot.showTypingCompanion)
    XCTAssertEqual(exportedSnapshot.typingPowerMode, .over9000)
    XCTAssertEqual(
      exportedSnapshot.historyChartVisibility,
      .init(speed: true, accuracy: false, average10: true, average100: false))
    XCTAssertEqual(exportedSnapshot.liveProgressStyle, .flashMini)
    XCTAssertEqual(exportedSnapshot.liveStatsColor, .black)
    XCTAssertEqual(exportedSnapshot.liveStatsOpacity, .half)
    XCTAssertEqual(exportedSnapshot.promptHighlightMode, .nextTwoWords)
    XCTAssertEqual(exportedSnapshot.clickSoundStyle, .morse)
    XCTAssertEqual(exportedSnapshot.errorSoundStyle, .submarine)
    XCTAssertEqual(exportedSnapshot.timeWarningSoundStyle, .frog)
    XCTAssertEqual(exportedSnapshot.smoothCaretMotion, .fast)
    XCTAssertEqual(exportedSnapshot.installedPracticeFontName, NativePracticeFont.fallbackPostScriptName)
    XCTAssertEqual(exportedSnapshot.streakDayBoundaryOffsetHours, 3.5)
    XCTAssertTrue(exportedSnapshot.hasSetStreakDayBoundary)

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.difficulty, .master)
    XCTAssertTrue(restored.inputRules.strictSpace)
    XCTAssertFalse(restored.inputRules.deleteOnError)
    XCTAssertTrue(restored.inputRules.blindMode)
    XCTAssertEqual(restored.fontSize, 34)
    XCTAssertEqual(restored.practiceFont, .serif)
    XCTAssertEqual(restored.installedPracticeFontName, NativePracticeFont.fallbackPostScriptName)
    XCTAssertEqual(restored.theme, .midnight)
    XCTAssertTrue(restored.publishCompletedResults)
    XCTAssertFalse(restored.saveCompletedResults)
    XCTAssertEqual(restored.keyboardLayout, .ansiDvorak)
    XCTAssertEqual(restored.keyboardInputLayout, .swissGerman)
    XCTAssertEqual(restored.customKeyboardLayouts, [customKeyboard])
    XCTAssertEqual(restored.customKeyboardLayoutID, customKeyboard.id)
    XCTAssertEqual(restored.keyboardGuideLayoutSource, .systemInput)
    XCTAssertEqual(restored.layoutFluidLayouts, [.ansiWorkman, .frenchAzerty, .ansiQwerty])
    XCTAssertTrue(restored.quickEnd)
    XCTAssertEqual(restored.quickRestartKey, .enter)
    XCTAssertFalse(restored.showKeyTips)
    XCTAssertEqual(restored.commandPaletteListMode, .grouped)
    XCTAssertFalse(restored.followSystemTheme)
    XCTAssertEqual(restored.systemLightTheme, .paper)
    XCTAssertEqual(restored.systemDarkTheme, .grove)
    XCTAssertTrue(restored.randomThemeOnRestart)
    XCTAssertEqual(restored.randomThemeMode, .custom)
    XCTAssertTrue(restored.flipTestColors)
    XCTAssertTrue(restored.colorfulMode)
    XCTAssertEqual(restored.customBackgroundURL, "https://images.example.test/harbour.jpeg")
    XCTAssertEqual(restored.customBackgroundFit, .contain)
    XCTAssertEqual(restored.customBackgroundFilter, .init(blur: 4, brightness: 0.85, saturation: 1.4, opacity: 0.7))
    XCTAssertEqual(restored.practiceBackdrop, .halos)
    XCTAssertTrue(restored.reducePracticeMotion)
    XCTAssertTrue(restored.showTypingCompanion)
    XCTAssertEqual(restored.typingPowerMode, .over9000)
    XCTAssertTrue(restored.isFavoriteTheme(.grove))
    XCTAssertTrue(restored.isFavoriteCustomTheme(customThemeID))
    XCTAssertEqual(restored.englishVariant, .british)
    XCTAssertFalse(restored.freedomMode)
    XCTAssertEqual(restored.confidenceMode, .maximum)
    XCTAssertEqual(restored.oppositeShiftMode, .keymap)
    XCTAssertTrue(restored.codeUnindentOnBackspace)
    XCTAssertEqual(restored.minimumAccuracy, 97)
    XCTAssertEqual(restored.minimumWpm, 85)
    XCTAssertEqual(restored.minimumWordBurstWpm, 85)
    XCTAssertEqual(restored.minimumWordBurstMode, .flex)
    XCTAssertEqual(restored.practiceLineWidth, .wide)
    XCTAssertEqual(restored.customPracticeLineColumns, 112)
    XCTAssertEqual(restored.practiceTapeMode, .letter)
    XCTAssertEqual(restored.practiceTapeMargin, 0.35)
    XCTAssertFalse(restored.smoothPracticeLineScroll)
    XCTAssertTrue(restored.showAllPracticeLines)
    XCTAssertEqual(restored.smoothCaretMotion, .fast)
    XCTAssertEqual(restored.caretStyle, .monkey)
    XCTAssertEqual(restored.typoIndicatorStyle, .both)
    XCTAssertEqual(restored.compositionDisplayStyle, .below)
    XCTAssertEqual(restored.typingSpeedUnit, .cps)
    XCTAssertTrue(restored.alwaysShowDecimalPlaces)
    XCTAssertTrue(restored.alwaysShowWordsHistory)
    XCTAssertTrue(restored.showWordBurstHeatmap)
    XCTAssertEqual(restored.resultPerformanceVisibility, .init(raw: false, burst: false, errors: true))
    XCTAssertFalse(restored.startGraphsAtZero)
    XCTAssertEqual(
      restored.historyChartVisibility,
      .init(speed: true, accuracy: false, average10: true, average100: false))
    XCTAssertEqual(restored.showAverage, .both)
    XCTAssertTrue(restored.showPersonalBest)
    XCTAssertEqual(restored.typedCharacterEffect, .dots)
    XCTAssertEqual(restored.liveSpeedStyle, .mini)
    XCTAssertEqual(restored.liveAccuracyStyle, .off)
    XCTAssertEqual(restored.liveBurstStyle, .mini)
    XCTAssertEqual(restored.liveProgressStyle, .flashMini)
    XCTAssertEqual(restored.liveStatsColor, .black)
    XCTAssertEqual(restored.liveStatsOpacity, .half)
    XCTAssertEqual(restored.promptHighlightMode, .nextTwoWords)
    XCTAssertEqual(restored.testModifiers, [.noSpaces, .uppercase])
    XCTAssertTrue(restored.isFavoriteQuote("craft"))
    XCTAssertTrue(restored.repeatQuotes)
    XCTAssertEqual(restored.resolvedTheme(for: .dark).colorScheme, .dark)
    XCTAssertEqual(restored.resolvedTheme(for: .light).colorScheme, .dark)
    XCTAssertTrue(restored.showKeyboardGuide)
    XCTAssertEqual(restored.keyboardGuideMode, .react)
    XCTAssertEqual(restored.keyboardGuideScale, 2.7)
    XCTAssertEqual(restored.keyboardGuideLegendStyle, .dynamic)
    XCTAssertEqual(restored.keyboardGuideKeysMode, .full)
    XCTAssertEqual(restored.keyboardGuideStyle, .alice)
    XCTAssertEqual(restored.effectiveKeyboardGuideMode, .react)
    restored.keyboardGuideMode = .off
    XCTAssertFalse(restored.showKeyboardGuide)
    XCTAssertEqual(restored.effectiveKeyboardGuideMode, .off)
    restored.keyboardGuideMode = .next
    XCTAssertTrue(restored.showKeyboardGuide)
    XCTAssertEqual(restored.effectiveKeyboardGuideMode, .next)
    XCTAssertFalse(restored.showFocusWarning)
    XCTAssertFalse(restored.showCapsLockWarning)
    XCTAssertTrue(restored.playErrorBeep)
    XCTAssertTrue(restored.playKeyclickSound)
    XCTAssertEqual(restored.clickSoundStyle, .morse)
    XCTAssertEqual(restored.errorSoundStyle, .submarine)
    XCTAssertEqual(restored.timeWarningOffset, .threeSeconds)
    XCTAssertEqual(restored.timeWarningSoundStyle, .frog)
    XCTAssertEqual(restored.soundVolume, 0.4)
    XCTAssertTrue(restored.globalHotkeyEnabled)
    XCTAssertEqual(restored.paceGuideMode, .custom)
    XCTAssertEqual(restored.paceGuideCustomWpm, 95)
    XCTAssertEqual(restored.paceCaretStyle, .off)
    XCTAssertTrue(restored.repeatedPace)
    XCTAssertEqual(restored.streakDayBoundaryOffsetHours, 3.5)
    XCTAssertTrue(restored.hasSetStreakDayBoundary)
  }

  @MainActor
  func testErrorHandlingModesPersistAndNormalizeInSettings() {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.stopOnErrorMode = .word
    XCTAssertTrue(settings.stopOnError)
    XCTAssertEqual(settings.inputRules.stopOnErrorMode, .word)

    settings.deleteOnErrorMode = .wordHard
    XCTAssertFalse(settings.stopOnError)
    XCTAssertEqual(settings.stopOnErrorMode, .off)
    XCTAssertTrue(settings.deleteOnError)
    XCTAssertEqual(settings.inputRules.deleteOnErrorMode, .wordHard)

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.deleteOnErrorMode, .wordHard)
    XCTAssertEqual(restored.inputRules.deleteOnErrorMode, .wordHard)
  }

  @MainActor
  func testApplyingAConfigurationRestoresEveryInputRuleForRestart() {
    let suiteName = "TypebarTests.rules-\(UUID().uuidString)"
    let localDefaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { localDefaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: localDefaults)
    let rules = InputRules(
      strictSpace: true,
      stopOnError: true,
      deleteOnError: true,
      hideExtraLetters: true,
      blindMode: true,
      quickEnd: true,
      freedomMode: true,
      minimumAccuracy: 96,
      minimumWpm: 80,
      minimumWordBurstWpm: 90
    )
    settings.apply(TestConfiguration.words(25, rules: rules, language: .german))
    XCTAssertEqual(settings.inputRules, rules)
    XCTAssertEqual(settings.englishVariant, EnglishVariant.american)
  }

  @MainActor
  func testGlobalHotkeyUsesOnlyControlShiftSpace() {
    XCTAssertTrue(GlobalHotkeyMonitor.matches(keyCode: 49, modifiers: [.control, .shift]))
    XCTAssertFalse(GlobalHotkeyMonitor.matches(keyCode: 49, modifiers: [.control]))
    XCTAssertFalse(GlobalHotkeyMonitor.matches(keyCode: 36, modifiers: [.control, .shift]))
  }

  func testLegacySettingsSnapshotDefaultsToPaperTheme() throws {
    let legacy = """
      {"difficulty":"normal","strictSpace":false,"stopOnError":false,"deleteOnError":false,"hideExtraLetters":false,"fontSize":28}
      """
    let snapshot = try JSONDecoder().decode(AppSettingsSnapshot.self, from: Data(legacy.utf8))
    XCTAssertEqual(snapshot.theme, .paper)
    XCTAssertFalse(snapshot.publishCompletedResults)
    XCTAssertTrue(snapshot.saveCompletedResults)
    XCTAssertTrue(snapshot.customThemes.isEmpty)
    XCTAssertNil(snapshot.activeCustomThemeID)
    XCTAssertTrue(snapshot.favoriteThemeIDs.isEmpty)
    XCTAssertFalse(snapshot.showKeyboardGuide)
    XCTAssertEqual(snapshot.keyboardGuideMode, .off)
    XCTAssertEqual(snapshot.keyboardGuideScale, 1)
    XCTAssertEqual(snapshot.keyboardGuideLegendStyle, .lowercase)
    XCTAssertEqual(snapshot.keyboardGuideKeysMode, .minimal)
    XCTAssertEqual(snapshot.keyboardGuideStyle, .staggered)
    XCTAssertEqual(snapshot.keyboardLayout, .ansiQwerty)
    XCTAssertEqual(snapshot.keyboardInputLayout, .system)
    XCTAssertEqual(snapshot.keyboardGuideLayoutSource, .builtIn)
    XCTAssertTrue(snapshot.customKeyboardLayouts.isEmpty)
    XCTAssertNil(snapshot.customKeyboardLayoutID)
    XCTAssertEqual(
      AppSettingsSnapshot(keyboardGuideLayoutSource: .custom).keyboardGuideLayoutSource,
      .builtIn)
    XCTAssertFalse(snapshot.quickEnd)
    XCTAssertEqual(snapshot.quickRestartKey, .off)
    XCTAssertTrue(snapshot.showKeyTips)
    XCTAssertEqual(snapshot.commandPaletteListMode, .singleList)
    XCTAssertFalse(snapshot.followSystemTheme)
    XCTAssertEqual(snapshot.systemLightTheme, .paper)
    XCTAssertEqual(snapshot.systemDarkTheme, .midnight)
    XCTAssertFalse(snapshot.randomThemeOnRestart)
    XCTAssertEqual(snapshot.randomThemeMode, .off)
    XCTAssertFalse(snapshot.flipTestColors)
    XCTAssertFalse(snapshot.colorfulMode)
    XCTAssertEqual(snapshot.customBackgroundURL, "")
    XCTAssertEqual(snapshot.customBackgroundFit, .cover)
    XCTAssertEqual(snapshot.customBackgroundFilter, .init())
    XCTAssertEqual(snapshot.practiceBackdrop, .solid)
    XCTAssertFalse(snapshot.reducePracticeMotion)
    XCTAssertFalse(snapshot.showTypingCompanion)
    XCTAssertEqual(snapshot.typingPowerMode, .off)
    XCTAssertTrue(snapshot.startGraphsAtZero)
    XCTAssertEqual(snapshot.historyChartVisibility, .init())
    XCTAssertEqual(snapshot.englishVariant, .american)
    XCTAssertTrue(snapshot.favoriteQuoteIDs.isEmpty)
    XCTAssertTrue(snapshot.activeResultTags.isEmpty)
    XCTAssertFalse(snapshot.repeatQuotes)
    XCTAssertFalse(snapshot.freedomMode)
    XCTAssertEqual(snapshot.minimumAccuracy, 0)
    XCTAssertEqual(snapshot.minimumWpm, 0)
    XCTAssertEqual(snapshot.minimumWordBurstWpm, 0)
    XCTAssertEqual(snapshot.practiceLineWidth, .standard)
    XCTAssertEqual(snapshot.customPracticeLineColumns, 60)
    XCTAssertFalse(snapshot.smoothPracticeLineScroll)
    XCTAssertEqual(snapshot.smoothCaretMotion, .medium)
    XCTAssertEqual(snapshot.caretStyle, .bar)
    XCTAssertEqual(snapshot.installedPracticeFontName, "")
    XCTAssertEqual(snapshot.typoIndicatorStyle, .off)
    XCTAssertEqual(snapshot.typingSpeedUnit, .wpm)
    XCTAssertFalse(snapshot.alwaysShowWordsHistory)
    XCTAssertFalse(snapshot.showWordBurstHeatmap)
    XCTAssertEqual(snapshot.resultPerformanceVisibility, .init())
    XCTAssertEqual(snapshot.showAverage, .off)
    XCTAssertFalse(snapshot.showPersonalBest)
    XCTAssertEqual(snapshot.typedCharacterEffect, .keep)
    XCTAssertEqual(snapshot.liveSpeedStyle, .off)
    XCTAssertEqual(snapshot.liveAccuracyStyle, .off)
    XCTAssertEqual(snapshot.liveBurstStyle, .off)
    XCTAssertEqual(snapshot.liveProgressStyle, .mini)
    XCTAssertEqual(snapshot.liveStatsColor, .accent)
    XCTAssertEqual(snapshot.liveStatsOpacity, .full)
    XCTAssertEqual(snapshot.promptHighlightMode, .letter)
    XCTAssertTrue(snapshot.testModifiers.isEmpty)
    XCTAssertTrue(snapshot.showFocusWarning)
    XCTAssertTrue(snapshot.showCapsLockWarning)
    XCTAssertFalse(snapshot.playErrorBeep)
    XCTAssertEqual(snapshot.clickSoundStyle, .tink)
    XCTAssertEqual(snapshot.errorSoundStyle, .basso)
    XCTAssertEqual(snapshot.timeWarningOffset, .off)
    XCTAssertEqual(snapshot.timeWarningSoundStyle, .glass)
    XCTAssertEqual(snapshot.soundVolume, 0.5)
    XCTAssertEqual(snapshot.paceGuideMode, .off)
    XCTAssertEqual(snapshot.paceGuideCustomWpm, 100)
    XCTAssertEqual(snapshot.paceCaretStyle, .bar)
    XCTAssertTrue(snapshot.repeatedPace)
    XCTAssertEqual(snapshot.streakDayBoundaryOffsetHours, 0)
    XCTAssertFalse(snapshot.hasSetStreakDayBoundary)
    let legacyRandom = try JSONDecoder().decode(
      AppSettingsSnapshot.self, from: Data("{\"randomThemeOnRestart\":true}".utf8))
    XCTAssertEqual(legacyRandom.randomThemeMode, .on)
    XCTAssertTrue(legacyRandom.randomThemeOnRestart)
    let hiddenGuideLegacy = try JSONDecoder().decode(
      AppSettingsSnapshot.self, from: Data("{\"showKeyboardGuide\":false}".utf8))
    XCTAssertEqual(hiddenGuideLegacy.keyboardGuideMode, .off)
    let legacyEmulatedLayout = try JSONDecoder().decode(
      AppSettingsSnapshot.self, from: Data("{\"keyboardLayout\":\"ansiDvorak\"}".utf8))
    XCTAssertEqual(legacyEmulatedLayout.keyboardInputLayout, .ansiDvorak)
    let explicitSystemInput = try JSONDecoder().decode(
      AppSettingsSnapshot.self,
      from: Data("{\"keyboardLayout\":\"ansiDvorak\",\"keyboardInputLayout\":\"system\"}".utf8))
    XCTAssertEqual(explicitSystemInput.keyboardInputLayout, .system)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.compact.maximumWidth(fontSize: 20)), 520.8, accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.custom.maximumWidth(fontSize: 20, customColumns: 99)), 1227.6,
      accuracy: 0.001)
    XCTAssertEqual(
      try XCTUnwrap(PracticeLineWidth.custom.maximumWidth(fontSize: 20, customColumns: 999)), 1736,
      accuracy: 0.001)
    XCTAssertNil(PracticeLineWidth.fluid.maximumWidth(fontSize: 20))
  }

  func testTypingSpeedUnitsFormatCanonicalWpmPresentation() {
    XCTAssertEqual(TypingSpeedUnit.wpm.formatted(wpm: 72), "72")
    XCTAssertEqual(TypingSpeedUnit.cpm.formatted(wpm: 72), "360")
    XCTAssertEqual(TypingSpeedUnit.wps.formatted(wpm: 72), "1.2")
    XCTAssertEqual(TypingSpeedUnit.wpm.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "72.00")
    XCTAssertEqual(TypingSpeedUnit.cpm.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "360.00")
    XCTAssertEqual(TypingSpeedUnit.wps.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "1.20")
    XCTAssertEqual(TypingSpeedUnit.cps.formatted(wpm: 72), "6.0")
    XCTAssertEqual(TypingSpeedUnit.wph.formatted(wpm: 72), "4320")
    XCTAssertEqual(TypingSpeedUnit.cps.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "6.00")
    XCTAssertEqual(TypingSpeedUnit.wph.formatted(wpm: 72, alwaysShowDecimalPlaces: true), "4320.00")
    XCTAssertEqual(TypingSpeedUnit.wps.converted(wpm: 72), 1.2, accuracy: 0.001)
    XCTAssertEqual(TypingSpeedUnit.cps.converted(wpm: 72), 6, accuracy: 0.001)
  }

  func testPaceGuideUsesOnlyComparableCompletedResultsAndClampsProgress() {
    let calendar = Calendar(identifier: .gregorian)
    let today = Date(timeIntervalSinceReferenceDate: 10_000_000)
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let samples = [
      PaceGuideSample(
        configuration: configuration, outcome: .completed, finishedAt: today, wpm: 72),
      PaceGuideSample(
        configuration: configuration, outcome: .completed,
        finishedAt: today.addingTimeInterval(-86_400), wpm: 48),
      PaceGuideSample(
        configuration: .timed(seconds: 30, language: .simplifiedChinese), outcome: .completed,
        finishedAt: today, wpm: 180),
      PaceGuideSample(
        configuration: configuration, outcome: .abandoned, finishedAt: today, wpm: 250),
    ]

    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .personalBest, customWpm: 60, configuration: configuration, samples: samples,
        now: today, calendar: calendar), 72)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .average, customWpm: 60, configuration: configuration, samples: samples, now: today,
        calendar: calendar), 60)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .dailyAverage, customWpm: 60, configuration: configuration, samples: samples,
        now: today, calendar: calendar), 72)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .custom, customWpm: 1, configuration: configuration, samples: [], now: today,
        calendar: calendar), PaceGuidePolicy.minimumWpm)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .lastTest, customWpm: 60, configuration: configuration, samples: [],
        lastTestWpm: 360, now: today, calendar: calendar), PaceGuidePolicy.maximumWpm)
    XCTAssertNil(
      PaceGuidePolicy.targetWpm(
        mode: .lastTest, customWpm: 60, configuration: configuration, samples: [],
        lastTestWpm: nil, now: today, calendar: calendar))
    XCTAssertNil(
      PaceGuidePolicy.targetWpm(
        mode: .off, customWpm: 60, configuration: configuration, samples: samples, now: today,
        calendar: calendar))
    XCTAssertEqual(
      PaceGuidePolicy.expectedCharacterIndex(elapsed: 2, targetWpm: 60, promptLength: 40), 10)
    XCTAssertEqual(
      PaceGuidePolicy.expectedCharacterIndex(elapsed: 120, targetWpm: 300, promptLength: 40), 39)
  }

  func testActiveTagPersonalBestPaceGuideUsesOnlyMatchingCompletedResults() {
    let configuration = TestConfiguration.timed(seconds: 30, language: .english)
    let samples = [
      PaceGuideSample(
        configuration: configuration, outcome: .completed, finishedAt: start, wpm: 75,
        tags: ["morning"]),
      PaceGuideSample(
        configuration: configuration, outcome: .completed, finishedAt: start, wpm: 120,
        tags: ["focus"]),
      PaceGuideSample(
        configuration: configuration, outcome: .completed, finishedAt: start, wpm: 180,
        tags: []),
      PaceGuideSample(
        configuration: configuration, outcome: .abandoned, finishedAt: start, wpm: 240,
        tags: ["focus"]),
    ]

    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .activeTagPersonalBest, customWpm: 60, configuration: configuration, samples: samples,
        activeTags: ["FOCUS"]), 120)
    XCTAssertEqual(
      PaceGuidePolicy.targetWpm(
        mode: .activeTagPersonalBest, customWpm: 60, configuration: configuration, samples: samples,
        activeTags: ["morning", "focus"]), 120)
    XCTAssertNil(
      PaceGuidePolicy.targetWpm(
        mode: .activeTagPersonalBest, customWpm: 60, configuration: configuration, samples: samples,
        activeTags: []))
  }

  @MainActor
  func testRandomThemeModesUseEphemeralCompatibleNativePools() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = AppSettings(defaults: defaults)

    settings.selectBuiltInTheme(.grove)
    settings.randomThemeMode = .light
    settings.randomizeTheme(for: .dark, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .light)
    XCTAssertEqual(settings.theme, .grove)

    settings.selectBuiltInTheme(.midnight)
    settings.randomThemeMode = .dark
    settings.randomizeTheme(for: .light, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .dark)

    settings.toggleFavoriteTheme(.paper)
    settings.randomThemeMode = .favorites
    settings.randomizeTheme(for: .dark, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .light)

    settings.addCustomTheme(
      name: "Dawn", background: .white, panel: .gray, accent: .orange, prefersDark: false)
    settings.selectBuiltInTheme(.midnight)
    settings.randomThemeMode = .custom
    settings.randomizeTheme(for: .dark, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .light)
    XCTAssertEqual(settings.theme, .midnight)

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.randomThemeMode, .custom)
    XCTAssertEqual(restored.theme, .midnight)
    XCTAssertEqual(restored.activeTheme.colorScheme, .dark)

    settings.randomThemeMode = .auto
    settings.randomizeTheme(for: .dark, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .dark)
    settings.systemLightTheme = .paper
    settings.systemDarkTheme = .grove
    settings.followSystemTheme = true
    XCTAssertEqual(settings.randomThemeMode, .off)
    XCTAssertEqual(settings.resolvedTheme(for: .light).accent, AppTheme.paper.accent)
    XCTAssertEqual(settings.resolvedTheme(for: .dark).accent, AppTheme.grove.accent)
    settings.randomThemeMode = .on
    XCTAssertFalse(settings.followSystemTheme)
    XCTAssertTrue(settings.randomThemeOnRestart)
    settings.randomThemeMode = .off
    settings.randomizeTheme(for: .light, using: 0)
    XCTAssertEqual(settings.activeTheme.colorScheme, .dark)
  }

  @MainActor
  func testCustomThemePersistsSelectsAndFallsBackWhenDeleted() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.addCustomTheme(
      name: "Dawn",
      background: Color(red: 0.2, green: 0.3, blue: 0.4),
      panel: Color(red: 0.3, green: 0.4, blue: 0.5),
      accent: Color(red: 0.8, green: 0.5, blue: 0.2),
      prefersDark: true
    )
    let id = try XCTUnwrap(settings.activeCustomThemeID)
    XCTAssertEqual(settings.customThemes.first?.name, "Dawn")
    settings.toggleFavoriteCustomTheme(id)
    XCTAssertTrue(settings.isFavoriteCustomTheme(id))

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.activeCustomThemeID, id)
    let restoredBackground = try XCTUnwrap(restored.customThemes.first?.background)
    XCTAssertEqual(restoredBackground.red, 0.2, accuracy: 0.000_001)
    XCTAssertEqual(restoredBackground.green, 0.3, accuracy: 0.000_001)
    XCTAssertEqual(restoredBackground.blue, 0.4, accuracy: 0.000_001)

    restored.deleteCustomTheme(id)
    XCTAssertTrue(restored.customThemes.isEmpty)
    XCTAssertNil(restored.activeCustomThemeID)
    XCTAssertFalse(restored.isFavoriteCustomTheme(id))
    XCTAssertTrue(restored.favoriteThemeIDs.isEmpty)
    XCTAssertEqual(restored.activeTheme.colorScheme, .light)
  }

  @MainActor
  func testCustomThemeEditingPreservesIdentityFavoritesAndArchiveReferences() throws {
    let suiteName = "TypebarTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    let theme = try XCTUnwrap(settings.addCustomTheme(
      name: "Dawn", background: .white, panel: .gray, accent: .orange, prefersDark: false))
    settings.toggleFavoriteCustomTheme(theme.id)
    XCTAssertTrue(settings.updateCustomTheme(
      id: theme.id, name: "Dusk", background: .black, panel: .blue, accent: .purple,
      text: .yellow, secondaryText: .cyan, error: .pink, extraInput: .mint,
      caret: .indigo, fadedText: .gray, colorfulError: .orange, colorfulExtraInput: .purple,
      prefersDark: true))
    XCTAssertEqual(settings.activeCustomThemeID, theme.id)
    XCTAssertTrue(settings.isFavoriteCustomTheme(theme.id))
    XCTAssertEqual(settings.customThemes.first?.id, theme.id)
    XCTAssertEqual(settings.customThemes.first?.name, "Dusk")
    XCTAssertTrue(settings.customThemes.first?.prefersDark == true)
    XCTAssertEqual(settings.customThemes.first?.text, ThemeColor(color: .yellow))
    XCTAssertEqual(settings.customThemes.first?.secondaryText, ThemeColor(color: .cyan))
    XCTAssertEqual(settings.customThemes.first?.error, ThemeColor(color: .pink))
    XCTAssertEqual(settings.customThemes.first?.extraInput, ThemeColor(color: .mint))
    XCTAssertEqual(settings.customThemes.first?.caret, ThemeColor(color: .indigo))
    XCTAssertEqual(settings.customThemes.first?.fadedText, ThemeColor(color: .gray))
    XCTAssertEqual(settings.customThemes.first?.colorfulError, ThemeColor(color: .orange))
    XCTAssertEqual(settings.customThemes.first?.colorfulExtraInput, ThemeColor(color: .purple))
    XCTAssertFalse(settings.updateCustomTheme(
      id: theme.id, name: " ", background: .white, panel: .white, accent: .white,
      prefersDark: false))
    XCTAssertEqual(settings.customThemes.first?.name, "Dusk")

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.customThemes.first?.id, theme.id)
    XCTAssertEqual(restored.customThemes.first?.name, "Dusk")
    XCTAssertTrue(restored.customThemes.first?.prefersDark == true)
    XCTAssertEqual(restored.customThemes.first?.text, ThemeColor(color: .yellow))
    XCTAssertEqual(restored.customThemes.first?.secondaryText, ThemeColor(color: .cyan))
    XCTAssertEqual(restored.customThemes.first?.error, ThemeColor(color: .pink))
    XCTAssertEqual(restored.customThemes.first?.extraInput, ThemeColor(color: .mint))
    XCTAssertEqual(restored.customThemes.first?.caret, ThemeColor(color: .indigo))
    XCTAssertEqual(restored.customThemes.first?.fadedText, ThemeColor(color: .gray))
    XCTAssertEqual(restored.customThemes.first?.colorfulError, ThemeColor(color: .orange))
    XCTAssertEqual(restored.customThemes.first?.colorfulExtraInput, ThemeColor(color: .purple))
    XCTAssertTrue(restored.isFavoriteCustomTheme(theme.id))
  }

  func testLegacyCustomThemeUsesNativePracticeColorDefaults() throws {
    let legacy = """
      {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","background":{"red":0.1,"green":0.2,"blue":0.3,"opacity":1},"panel":{"red":0.2,"green":0.3,"blue":0.4,"opacity":1},"accent":{"red":0.3,"green":0.4,"blue":0.5,"opacity":1},"prefersDark":true}
      """
    let theme = try JSONDecoder().decode(CustomThemeDefinition.self, from: Data(legacy.utf8))
    XCTAssertEqual(theme.text, ThemeColor(color: ResolvedTheme.defaultTextColor(for: .dark)))
    XCTAssertEqual(
      theme.secondaryText,
      ThemeColor(color: ResolvedTheme.defaultSecondaryTextColor(for: .dark)))
    XCTAssertEqual(theme.error, ThemeColor(color: ResolvedTheme.defaultErrorColor))
    XCTAssertEqual(theme.extraInput, ThemeColor(color: ResolvedTheme.defaultErrorColor))
    XCTAssertEqual(theme.caret, theme.accent)
    XCTAssertEqual(theme.fadedText, theme.secondaryText)
    XCTAssertEqual(theme.colorfulError, theme.error)
    XCTAssertEqual(theme.colorfulExtraInput, theme.extraInput)
  }

  func testCustomThemeFeedbackColorsFollowColorfulMode() {
    let theme = CustomThemeDefinition(
      name: "Feedback", background: .init(red: 0.1, green: 0.2, blue: 0.3),
      panel: .init(red: 0.2, green: 0.3, blue: 0.4), accent: .init(red: 0.3, green: 0.4, blue: 0.5),
      error: .init(color: .red), extraInput: .init(color: .pink),
      colorfulError: .init(color: .orange), colorfulExtraInput: .init(color: .purple),
      prefersDark: true)
    let resolved = theme.resolvedTheme

    XCTAssertEqual(ThemeColor(color: resolved.errorColor(usesColorfulMode: false)), theme.error)
    XCTAssertEqual(ThemeColor(color: resolved.errorColor(usesColorfulMode: true)), theme.colorfulError)
    XCTAssertEqual(ThemeColor(color: resolved.extraInputColor(usesColorfulMode: false)), theme.extraInput)
    XCTAssertEqual(
      ThemeColor(color: resolved.extraInputColor(usesColorfulMode: true)),
      theme.colorfulExtraInput)
  }

  @MainActor
  func testResultRecordRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
      for: TestResultRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    var session = TypingSession(
      configuration: .init(
        mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      prompt: "amber")
    session.insert("a", at: start)
    session.insert("mber", at: start.addingTimeInterval(6))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.afkDuration, 4)
    XCTAssertEqual(result.engagedDuration, 2)
    XCTAssertEqual(CurrentProcessPractice(result: result).typingSeconds, 2)
    container.mainContext.insert(TestResultRecord(result: result))
    try container.mainContext.save()

    let stored = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<TestResultRecord>()).first)
    XCTAssertEqual(stored.id, result.id)
    XCTAssertEqual(stored.configuration?.mode, .quote)
    XCTAssertEqual(stored.wpm, result.wpm)
    XCTAssertEqual(stored.accuracy, 100)
    XCTAssertEqual(stored.afkDuration, 4)
    XCTAssertEqual(stored.afkPercentage, 66.666_666_666_7, accuracy: 0.000_001)
    XCTAssertEqual(stored.portableResult, result)

    stored.addTag("morning")
    stored.addTag("MORNING")
    stored.addTag(" focus ")
    try container.mainContext.save()
    XCTAssertEqual(stored.tags, ["morning", "focus"])
    XCTAssertEqual(stored.portableResult?.tags, ["morning", "focus"])
  }

  func testResultTagPolicyNormalizesDeduplicatesAndLimitsTags() {
    let tags = ResultTagPolicy.normalized([
      "  flow", "FLOW", "review", "", "a very long tag that cannot be accepted", "one", "two",
      "three", "four",
    ])
    XCTAssertEqual(tags, ["flow", "review", "one", "two", "three"])
  }

  @MainActor
  func testActiveResultTagsPersistNormalizeAndCanBeCleared() {
    let suiteName = "TypebarTests.active-tags.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: defaults)
    settings.activateResultTag(" morning ")
    settings.activateResultTag("MORNING")
    settings.activateResultTag("focus")
    settings.activateResultTag("review")
    settings.activateResultTag("sprint")
    settings.activateResultTag("extra")
    XCTAssertEqual(settings.activeResultTags, ["morning", "focus", "review", "sprint", "extra"])
    XCTAssertEqual(settings.snapshot.activeResultTags, settings.activeResultTags)

    let restored = AppSettings(defaults: defaults)
    XCTAssertEqual(restored.activeResultTags, settings.activeResultTags)
    restored.deactivateResultTag("FOCUS")
    XCTAssertEqual(restored.activeResultTags, ["morning", "review", "sprint", "extra"])
    restored.clearActiveResultTags()
    XCTAssertTrue(restored.activeResultTags.isEmpty)
  }

  func testQAStoreModeOnlyUsesExplicitBooleanBundleFlag() {
    XCTAssertFalse(QAStoreMode.usesInMemoryStore(info: [:]))
    XCTAssertTrue(QAStoreMode.usesInMemoryStore(info: [
      QAStoreMode.inMemoryInfoKey: true,
    ]))
    XCTAssertFalse(QAStoreMode.usesInMemoryStore(info: [
      QAStoreMode.inMemoryInfoKey: "YES",
    ]))
  }

  @MainActor
  func testResultFilterPresetPersistsACompleteFilter() throws {
    let container = try ModelContainer(
      for: ResultFilterPresetRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let filter = ResultHistoryFilter(
      language: .english, modes: [.quote, .zen],
      tagFilter: .init(isUnrestricted: false, includesNoTags: true, tags: ["focus", "review"]),
      personalBestFilter: .excluded,
      difficulties: [.normal, .expert], dateRange: .lastMonth, punctuation: .included, numbers: .noMatches,
      quoteLengths: [.medium, .long], timeLimits: [.seconds15, .custom], wordLimits: [.words50, .custom],
      modifierFilter: .init(includesNoModifiers: false, modifiers: [.crtVisual, .binaryStream]))
    let preset = try XCTUnwrap(ResultFilterPresetRecord(name: " Focused English ", filter: filter))
    container.mainContext.insert(preset)
    try container.mainContext.save()

    let stored = try XCTUnwrap(
      container.mainContext.fetch(FetchDescriptor<ResultFilterPresetRecord>()).first)
    XCTAssertEqual(stored.name, "Focused English")
    XCTAssertEqual(stored.filter, filter)
    XCTAssertNil(ResultFilterPresetRecord(name: " ", filter: filter))
    XCTAssertNil(ResultFilterPresetRecord(name: String(repeating: "a", count: 41), filter: filter))
  }

  @MainActor
  func testSavedCustomTextRoundTripsThroughSwiftData() throws {
    let container = try ModelContainer(
      for: SavedCustomTextRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(
      SavedCustomTextRecord(title: "Morning", text: "A deliberate beginning."))
    container.mainContext.insert(
      SavedCustomTextRecord(title: "Chapter", text: "amber harbor willow", longProgress: 6))
    try container.mainContext.save()

    let savedTexts = try container.mainContext.fetch(FetchDescriptor<SavedCustomTextRecord>())
    let savedText = try XCTUnwrap(savedTexts.first { $0.title == "Morning" })
    XCTAssertEqual(savedText.title, "Morning")
    XCTAssertEqual(savedText.text, "A deliberate beginning.")
    XCTAssertFalse(savedText.isLong)
    let longText = try XCTUnwrap(savedTexts.first { $0.title == "Chapter" })
    XCTAssertTrue(longText.isLong)
    XCTAssertEqual(longText.longProgress, 6)
    XCTAssertEqual(longText.selection.longProgress, 6)
  }

  func testLongSavedTextProgressAdvancesOnlyThroughFullyMatchedWords() {
    let text = "amber  harbor\nwillow"
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(
      in: text, from: 0, typed: "amber  har"), 7)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(
      in: text, from: 0, typed: "amber  harbor"), 14)
    XCTAssertEqual(LongSavedTextProgress.advancedOffset(
      in: text, from: 0, typed: "amber  x"), 7)
    XCTAssertEqual(
      LongSavedTextProgress.remainingText(in: text, after: 14), "willow")
    XCTAssertEqual(LongSavedTextProgress.progressLabel(in: text, offset: 14), "2 / 3 词")
  }
}
