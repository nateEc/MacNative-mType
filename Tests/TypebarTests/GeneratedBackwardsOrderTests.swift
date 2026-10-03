import XCTest
@testable import Typebar

final class GeneratedBackwardsOrderTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func binary(_ index: Int) -> String {
    let value = String(index % 256, radix: 2)
    return String(repeating: "0", count: 8 - value.count) + value
  }

  private func target(_ range: Range<Int>, omitted: Int? = nil) -> String {
    range.map { String(binary($0).reversed()) + ($0 == omitted ? "" : "_") }.joined()
  }

  func testGeneratedBinaryOpeningKeepsGenerationOrderBeforeReversingEachWord() {
    let config = TestConfiguration.words(3).with(modifiers: [.binaryStream, .backwards])
    let session = TestSessionFactory.make(configuration: config)
    XCTAssertEqual(session.configuration.modifiers, config.modifiers)
    XCTAssertTrue(config.modifiers.contains(.backwards))
    XCTAssertEqual(session.prompt, (0..<3).map { String(binary($0).reversed()) }.joined(separator: " "))
  }

  func testGeneratedContinuationKeepsGlobalOrderAndTheRealUnderscoreBound() throws {
    let config = TestConfiguration.words(103).with(modifiers: [.binaryStream, .backwards, .underscoreSeparators])
    var cursor = GeneratedStreamContinuation(configuration: config, batchWordCount: 3, nextTokenIndex: 100)
    let chunk = try XCTUnwrap(cursor.nextChunk())
    XCTAssertEqual(chunk.source, (100..<103).map(binary).joined(separator: " "))
    XCTAssertEqual(chunk.transformed, target(100..<103))
    XCTAssertEqual(chunk.noSpaceTargetWords, (100..<103).map { String(binary($0).reversed()) + "_" })
    XCTAssertEqual(cursor.nextTokenIndex, 103)
    XCTAssertNil(cursor.nextChunk())
  }

  func testFiniteStreamCompletesAfterTheFinalGeneratedSuffixNotTheReversedBatchHead() throws {
    let config = TestConfiguration.words(501).with(modifiers: [.binaryStream, .backwards, .underscoreSeparators])
    var session = TestSessionFactory.make(configuration: config)
    let opening = target(0..<500, omitted: 99)
    XCTAssertEqual(session.prompt, target(0..<100, omitted: 99))
    session.insertBatch(opening, at: start)
    XCTAssertEqual(session.completedWordCount, 500)
    XCTAssertFalse(session.isFinished)
    XCTAssertEqual(session.prompt, opening + target(500..<501))
    session.insertBatch(String(binary(500).reversed()), at: start.addingTimeInterval(1))
    XCTAssertFalse(session.isFinished)
    session.insertBatch("_", at: start.addingTimeInterval(2))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.completedWordCount, 501)
    XCTAssertEqual(session.wordReviews.last?.target, String(binary(500).reversed()) + "_")
    let result = try XCTUnwrap(session.result())
    XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 2), session.prompt)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
  }

  func testWholePreviewChangesOnlyTheFinalSuffixNotGeneratedDrawOrder() {
    let config = TestConfiguration.words(101).with(modifiers: [.binaryStream, .backwards, .underscoreSeparators])
    let ordinary = TestSessionFactory.make(configuration: config)
    let whole = TestSessionFactory.make(configuration: config, showAllLines: true)
    XCTAssertEqual(ordinary.prompt, target(0..<100, omitted: 99))
    XCTAssertEqual(whole.prompt, target(0..<101, omitted: 100))
    XCTAssertEqual(whole.repeatedAttempt().prompt, whole.prompt)
    XCTAssertEqual(whole.configuration, config)
  }

  func testEveryCompatibleOwnedStreamPreservesItsGeneratedOrder() throws {
    let sources: [TestModifier] = [.binaryStream, .accountingStream, .hexadecimalStream,
      .symbolStream, .asciiStream, .specialCharacterStream, .gibberishStream,
      .poetryStream, .referenceStream, .ipv4Stream, .ipv6Stream, .pseudolangStream]
    for modifier in sources {
      let config = TestConfiguration.words(4).with(modifiers: [modifier, .backwards])
      XCTAssertTrue(config.modifiers.contains(modifier), modifier.rawValue)
      XCTAssertTrue(config.modifiers.contains(.backwards), modifier.rawValue)
      let source = try XCTUnwrap(TypebarStreamContent.prompt(configuration: config, wordCount: 4))
      let words = source.split(separator: " ").map { String($0.reversed()) }
      var session = TestSessionFactory.make(configuration: config)
      XCTAssertEqual(session.prompt, words.joined(separator: " "), modifier.rawValue)
      session.insertBatch(session.prompt, at: start)
      XCTAssertEqual(session.outcome, .completed, modifier.rawValue)
      XCTAssertEqual(session.completedWordCount, 4, modifier.rawValue)
      XCTAssertEqual(session.errors, 0, modifier.rawValue)
      XCTAssertEqual(session.wordReviews.map(\.target), words, modifier.rawValue)
    }
  }

  func testNoSpaceGenerationDoesNotChangeOrderWhenChunkSizesChange() throws {
    let config = TestConfiguration.words(203).with(modifiers: [.binaryStream, .backwards, .noSpaces])
    let expected = (0..<203).map { String(binary($0).reversed()) }
    for size in [1, 3, 100, 500] {
      var cursor = GeneratedStreamContinuation(configuration: config, batchWordCount: size, nextTokenIndex: 0)
      var words: [String] = []
      while let chunk = cursor.nextChunk() { words += chunk.noSpaceTargetWords }
      XCTAssertEqual(words, expected, "分批大小 \(size) 不应改变已生成的词序")
      XCTAssertEqual(cursor.nextTokenIndex, 203)
      XCTAssertNil(cursor.nextChunk())
    }
  }

  func testInfiniteGenerationAndRepeatKeepTheOpeningAndAdvanceTheSameCursor() {
    let config = TestConfiguration.words(0).with(modifiers: [.binaryStream, .backwards, .underscoreSeparators])
    for showAll in [false, true] {
      var session = TestSessionFactory.make(configuration: config, showAllLines: showAll)
      let count = 100
      let opening = target(0..<count, omitted: 99)
      XCTAssertEqual(session.prompt, opening)
      session.insertBatch(opening, at: start)
      XCTAssertEqual(session.completedWordCount, count)
      XCTAssertFalse(session.isFinished)
      XCTAssertEqual(session.prompt, opening + target(count..<(count + 100)))
      XCTAssertEqual(session.errors, 0)
      var repeated = session.repeatedAttempt()
      XCTAssertEqual(repeated.prompt, opening)
      repeated.insertBatch(opening, at: start.addingTimeInterval(1))
      XCTAssertEqual(repeated.prompt, session.prompt)
      XCTAssertEqual(repeated.completedWordCount, count)
      XCTAssertEqual(repeated.errors, 0)
    }
  }

  func testLegacySavedPromptAndFixedMetricsAreNotRegeneratedOnArchiveImport() throws {
    let config = TestConfiguration.words(3).with(modifiers: [.binaryStream, .backwards])
    let oldPrompt = (0..<3).reversed().map { String(binary($0).reversed()) }.joined(separator: " ")
    var oldSession = TypingSession(configuration: config, prompt: oldPrompt)
    oldSession.insertBatch(oldPrompt, at: start)
    let oldResult = try XCTUnwrap(oldSession.result())
    let archive = try TypebarDataTransfer.exportArchive(settings: .init(), results: [oldResult], presets: [], at: start)
    let restored = try XCTUnwrap(TypebarDataTransfer.importArchive(from: archive).results.first)
    XCTAssertEqual(restored, oldResult)
    XCTAssertEqual(restored.prompt, oldPrompt)
    XCTAssertEqual(restored.wpm, oldResult.wpm)
    XCTAssertNotEqual(TestSessionFactory.make(configuration: config).prompt, restored.prompt)
    XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: restored).portableResult), oldResult)
  }
}
