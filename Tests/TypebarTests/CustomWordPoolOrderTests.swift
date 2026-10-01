import XCTest
@testable import Typebar

final class CustomWordPoolOrderTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func config(_ completion: CustomTextCompletion, ordering: CustomTextOrdering,
    limit: Int? = nil, modifiers: [TestModifier] = [.backwards]) -> TestConfiguration {
    .init(mode: .custom, duration: completion == .time ? 120 : nil, wordLimit: limit,
      difficulty: .normal, rules: .init(), customTextCompletion: completion,
      customTextOrdering: ordering, customTextPipeDelimiter: false, modifiers: modifiers)
  }

  func testOrderedStreamReversesTheWholePoolBeforeTakingItsFirstHundredWords() {
    let source = (0..<105).map { "w\($0)" }
    let configuration = config(.time, ordering: .inOrder)
    var session = TestSessionFactory.make(configuration: configuration, customText: source.joined(separator: " "))
    let opening = source.reversed().prefix(100).map { String($0.reversed()) }.joined(separator: " ")
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening + " ", at: start)
    let expectedNext = Array(source.reversed().suffix(5)) + Array(source.reversed().prefix(95))
    XCTAssertEqual(session.prompt, opening + " " + expectedNext.map { String($0.reversed()) }.joined(separator: " "))
    XCTAssertEqual(session.completedWordCount, 100)
    XCTAssertEqual(session.errors, 0)
    XCTAssertFalse(session.isFinished)
    var repeated = session.repeatedAttempt()
    XCTAssertEqual(repeated.prompt, opening)
    repeated.insertBatch(opening + " ", at: start)
    XCTAssertEqual(repeated.prompt, session.prompt, "重复尝试从保存的初始游标独立续接")
  }

  func testOrderedFiniteUnderscoreStopsAtTheRealContinuationTarget() throws {
    let source = (0..<105).map { "w\($0)" }.joined(separator: " ")
    let configuration = config(.words, ordering: .inOrder, limit: 101,
      modifiers: [.backwards, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: configuration, customText: source)
    let opening = (0..<100).map { String("w\(104 - $0)".reversed()) + ($0 == 99 ? "" : "_") }.joined()
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.prompt, opening + (0..<100).map { String("w\((4 - $0 + 105) % 105)".reversed()) + "_" }.joined())
    XCTAssertFalse(session.isFinished)
    session.insertBatch("4w", at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("_", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.wordReviews.last?.target, "4w_")
    XCTAssertEqual(session.errors, 0)
    if let result = session.result() {
      XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), opening + "4w_")
    } else { XCTFail("有限词池应完成") }
  }

  func testRandomFiniteDrawsFromTheReversedPoolWithoutReversingTheDrawSequence() {
    let configuration = config(.words, ordering: .random, limit: 5)
    var draw = 0
    let session = TestSessionFactory.make(configuration: configuration, customText: "ab cd ef gh",
      nextRandomWordIndex: { defer { draw += 1 }; return draw % 4 })
    XCTAssertEqual(session.prompt, "hg fe dc ba hg")
    XCTAssertEqual(draw, 5)
  }

  func testRandomAlterationsAndHiddenTargetsKeepTheirDrawOrder() throws {
    let configuration = config(.words, ordering: .random, limit: 5,
      modifiers: [.backwards, .titleCase, .underscoreSeparators])
    var draw = 0
    var session = TestSessionFactory.make(configuration: configuration, customText: "ab cd ef gh",
      nextRandomWordIndex: { defer { draw += 1 }; return draw % 4 })
    let target = "Hg_Fe_Dc_Ba_Hg"
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(target, at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.wordReviews.map(\.target), ["Hg_", "Fe_", "Dc_", "Ba_", "Hg"])
    XCTAssertEqual(session.errors, 0)
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.typedCharacterCount, target.count)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from:
      TypebarDataTransfer.exportArchive(settings: .init(), results: [result], presets: [], at: start)).results,
      [result])
  }

  func testShufflePreparesThePoolBeforeChoosingItsPermutation() {
    var session = TestSessionFactory.make(configuration: config(.finish, ordering: .shuffled),
      customText: "ab cd ef gh", nextRandomWordIndex: { 0 })
    XCTAssertEqual(session.prompt, "hg ba dc fe")
    session.insertBatch("hg ba dc fe", at: start)
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
  }

  func testDisabledBackwardsKeepsTheExistingDrawOrderAndFiniteFlatReversal() {
    var draw = 0
    let plain = TestSessionFactory.make(configuration: config(.words, ordering: .random, limit: 5, modifiers: []),
      customText: "ab cd ef gh", nextRandomWordIndex: { defer { draw += 1 }; return draw % 4 })
    XCTAssertEqual(plain.prompt, "ab cd ef gh ab")
    let finite = TestSessionFactory.make(configuration: config(.finish, ordering: .inOrder), customText: "ab cd")
    XCTAssertEqual(finite.prompt, "dc ba")
  }

  func testReversedRandomPoolRetainsRecentWordAvoidanceAndOneHundredRetryCap() {
    let pool = ["ab", "cd", "ef", "gh"]
    var draw = 0
    let selected = CustomTextOrderPolicy.randomWords(from: pool, count: 2,
      avoiding: ["gh", "ef"], reversesCandidatePool: true,
      random: { defer { draw += 1 }; return draw })
    XCTAssertEqual(selected, ["cd", "ab"])
    XCTAssertEqual(draw, 4)
    var retries = 0
    let fallback = CustomTextOrderPolicy.randomWords(from: pool, count: 1,
      avoiding: ["gh"], reversesCandidatePool: true,
      random: { retries += 1; return 0 })
    XCTAssertEqual(fallback, ["gh"])
    XCTAssertEqual(retries, 101)
    XCTAssertEqual(CustomTextOrderPolicy.randomWords(from: pool, count: 1,
      reversesCandidatePool: true, random: { Int.min }), ["gh"])
    XCTAssertEqual(CustomTextOrderPolicy.randomWords(from: [], count: 100,
      reversesCandidatePool: true), [])
  }

  func testPreparedGenerationKeepsWordOrderWhileApplyingCanonicalAlterations() {
    let configuration = config(.finish, ordering: .inOrder,
      modifiers: [.backwards, .titleCase, .underscoreSeparators])
    let prepared = GeneratedWordChunk(source: "ab cd ef", configuration: configuration,
      preservesWordOrder: true)
    XCTAssertEqual(prepared.transformed, "Ba_Dc_Fe")
    XCTAssertEqual(prepared.noSpaceTargetWords, ["Ba_", "Dc_", "Fe"])
    XCTAssertEqual(GeneratedWordChunk(source: "ab cd ef", configuration: configuration).transformed, "Fe_Dc_Ba")
  }

  func testReversedShufflePoolConsumesEachPositionOnceAndCopiesItsCursorByValue() throws {
    var stream = try XCTUnwrap(CustomSequentialWordStream(source: "ab cd ef gh", ordering: .shuffled,
      reversesCandidatePool: true))
    XCTAssertEqual(stream.nextWords(count: 4, random: { 0 }), "gh ab cd ef")
    var copy = stream
    XCTAssertEqual(stream.nextWords(count: 8, random: { 0 }), " gh ab cd ef gh ab cd ef")
    XCTAssertEqual(copy.nextWords(count: 4, random: { 0 }), " gh ab cd ef")
  }

  func testEveryCodeLanguageCustomWordPoolKeepsItsReversedContinuation() {
    let source = (0..<105).map { "w\($0)" }.joined(separator: " ")
    let opening = (0..<100).map { String("w\(104 - $0)".reversed()) + ($0 == 99 ? "" : "_") }.joined()
    let languages = TypingLanguage.allCases.filter(\.isCodeLanguage)
    XCTAssertEqual(languages.count, 70)
    for language in languages {
      var configuration = config(.words, ordering: .inOrder, limit: 101,
        modifiers: [.backwards, .underscoreSeparators])
      configuration.language = language
      var session = TestSessionFactory.make(configuration: configuration, customText: source)
      XCTAssertEqual(session.prompt, opening, language.rawValue)
      session.insertBatch(opening, at: start)
      XCTAssertTrue(session.prompt.dropFirst(opening.count).hasPrefix("4w_"), language.rawValue)
      session.insertBatch("4w_", at: start.addingTimeInterval(1))
      XCTAssertEqual(session.outcome, .completed, language.rawValue)
      XCTAssertEqual(session.completedWordCount, 101, language.rawValue)
      XCTAssertEqual(session.errors, 0, language.rawValue)
    }
  }

  func testRandomTimedContinuationKeepsTheSharedUnderscoreBoundAndResult() throws {
    let configuration = config(.time, ordering: .random,
      modifiers: [.backwards, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: configuration, customText: "ab")
    let opening = String(repeating: "ba_", count: 99) + "ba"
    XCTAssertEqual(session.prompt, opening)
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.prompt, opening + String(repeating: "ba_", count: 100))
    session.insertBatch("ba_", at: start.addingTimeInterval(1))
    XCTAssertEqual(session.completedWordCount, 101)
    XCTAssertEqual(session.errors, 0)
    for second in 2..<120 {
      session.insertBatch("ba_", at: start.addingTimeInterval(Double(second)))
    }
    session.tick(at: start.addingTimeInterval(120))
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(result.outcome, .completed)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 120),
      opening + String(repeating: "ba_", count: 119))
  }
}
