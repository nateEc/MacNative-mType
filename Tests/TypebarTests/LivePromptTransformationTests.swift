import XCTest
@testable import Typebar

@MainActor final class LivePromptTransformationTests: XCTestCase {
  func testSwissGermanSourceScanningCancelsAtOriginalScalarTailBeforeRandomDraws() async {
    let source = String(repeating: "ß", count: 5001)
    var scanned: [Int] = [], draws = 0
    let task = Task<Void, Error> { @MainActor in
      _ = try await LivePromptTransformation.prepare(source,
        configuration: .words(1, language: .swissGerman).with(modifiers: [.randomCase]),
        preservesNoSpaceBoundaries: false, wordOffset: 0, wordBound: 1,
        nextRandomCaseBit: { draws += 1; return true }, didScanSource: { count in
          scanned.append(count)
          if count == 5001 { withUnsafeCurrentTask { $0?.cancel() } }
        })
    }
    do { try await task.value; XCTFail("Cancelled source scan must reject the batch") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(scanned, [4096, 5001])
    XCTAssertEqual(draws, 0)
  }

  func testSwissGermanSourceFieldsMatchSynchronousTransformerAcrossAlterations() async throws {
    let source = "  maß straße e\u{301}ß 👩🏽‍💻ß\nß  "
    for modifiers: [TestModifier] in [[], [.backwards], [.randomCase], [.messagingStyle],
      [.noSpaces], [.backwards, .randomCase], [.underscoreSeparators]] {
      let configuration = TestConfiguration.words(1000, language: .swissGerman).with(modifiers: modifiers)
      for boundaries in [false, true] {
        var expectedDraws = 0, actualDraws = 0
        let expected = TestModifierPolicy.transformedBatch(source, modifiers: configuration.modifiers,
          language: configuration.language, preservesNoSpaceBoundaries: boundaries,
          wordOffset: 7, wordBound: 1000, preservesWordOrder: false, capturesSourceFields: true,
          britishEnglish: .init(configuration: configuration, authoredQuoteAlternate: false),
          nextRandomCaseBit: { expectedDraws += 1; return expectedDraws.isMultiple(of: 3) })
        let actual = try await LivePromptTransformation.prepare(source, configuration: configuration,
          preservesNoSpaceBoundaries: boundaries, wordOffset: 7, wordBound: 1000,
          preservesWordOrder: false,
          nextRandomCaseBit: { actualDraws += 1; return actualDraws.isMultiple(of: 3) })
        XCTAssertEqual(Array(actual.text.utf8), Array(expected.text.utf8))
        XCTAssertEqual(actual.sourceFields?.map { Array($0.utf8) }, expected.sourceFields?.map { Array($0.utf8) })
        XCTAssertEqual(actual.noSpaceTargetWords.map { Array($0.utf8) }, expected.noSpaceTargetWords.map { Array($0.utf8) })
        XCTAssertEqual(actualDraws, expectedDraws)
      }
    }
  }

  func testSourceScanningCanCancelBeforeAnyRandomTransformation() async {
    for cancelAt in [4096, 5001] {
      var scanned: [Int] = [], draws = 0
      let task = Task<Void, Error> { @MainActor in
        _ = try await LivePromptTransformation.prepare(String(repeating: "x", count: 5001),
          configuration: .words(1).with(modifiers: [.randomCase]),
          preservesNoSpaceBoundaries: false, wordOffset: 0, wordBound: 1,
          nextRandomCaseBit: { draws += 1; return true }, didScanSource: { count in
            scanned.append(count)
            if count == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
          })
      }
      do { try await task.value; XCTFail("Source scan cancellation must reject the batch") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(scanned, cancelAt == 4096 ? [4096] : [4096, 5001])
      XCTAssertEqual(draws, 0, "Cancelled parsing must not consume transformation random bits")
    }
  }

  func testOrderedLiveContractMatchesSynchronousTransformerAndRandomDraws() async throws {
    let sources = ["", "  e\u{301} 👩🏽‍💻 中文 سلام a\nb \u{301}end  ",
      "colour center organise HI! next\n"]
    let alterations: [[TestModifier]] = [[], [.uppercase], [.backwards], [.titleCase],
      [.doubleCharacters], [.messagingStyle], [.morseStream], [.randomCase], [.rot13],
      [.alternatingCase], [.underscoreSeparators], [.noSpaces], [.lazyLatin],
      [.randomCase, .underscoreSeparators], [.messagingStyle, .noSpaces]]
    for source in sources {
      for modifiers in alterations {
        for boundaries in [false, true] {
          let configuration = TestConfiguration.words(1000, englishVariant: .british).with(modifiers: modifiers)
          var expectedDraws = 0
          let expected = TestModifierPolicy.transformedBatch(source,
            modifiers: configuration.modifiers, language: configuration.language,
            preservesNoSpaceBoundaries: boundaries, wordOffset: 7, wordBound: 1000,
            preservesWordOrder: true, capturesSourceFields: true,
            britishEnglish: .init(configuration: configuration, authoredQuoteAlternate: false),
            nextRandomCaseBit: { expectedDraws += 1; return expectedDraws.isMultiple(of: 3) })
          var actualDraws = 0
          let actual = try await LivePromptTransformation.prepare(source, configuration: configuration,
            preservesNoSpaceBoundaries: boundaries, wordOffset: 7, wordBound: 1000,
            nextRandomCaseBit: { actualDraws += 1; return actualDraws.isMultiple(of: 3) })
          XCTAssertEqual(Array(actual.text.utf8), Array(expected.text.utf8))
          XCTAssertEqual(actual.sourceFields?.map { Array($0.utf8) }, expected.sourceFields?.map { Array($0.utf8) })
          XCTAssertEqual(actual.noSpaceTargetWords.map { Array($0.utf8) }, expected.noSpaceTargetWords.map { Array($0.utf8) })
          XCTAssertEqual(actual.noSpaceWordLengths, expected.noSpaceWordLengths)
          XCTAssertEqual(actualDraws, expectedDraws)
        }
      }
    }
  }

  func testScanBoundariesPreserveScalarBytesEmptyFieldsAndReverseOrdering() async throws {
    let sources = ["", " ", String(repeating: " ", count: 4096),
      String(repeating: "x", count: 4095) + "\u{301}👩🏽‍💻\t\n river  ",
      String(repeating: " ", count: 4095) + "\u{301}harbor\u{00a0}end  "]
    for source in sources {
      for modifiers: [TestModifier] in [[], [.backwards, .randomCase], [.messagingStyle, .noSpaces]] {
        let configuration = TestConfiguration.words(1000).with(modifiers: modifiers)
        var oldDraws = 0, newDraws = 0, scans: [Int] = []
        let expected = TestModifierPolicy.transformedBatch(source, modifiers: configuration.modifiers,
          language: configuration.language, wordOffset: 0, wordBound: 1000,
          preservesWordOrder: false, capturesSourceFields: true,
          britishEnglish: .init(configuration: configuration, authoredQuoteAlternate: false),
          nextRandomCaseBit: { oldDraws += 1; return oldDraws.isMultiple(of: 3) })
        let actual = try await LivePromptTransformation.prepare(source, configuration: configuration,
          preservesNoSpaceBoundaries: false, wordOffset: 0, wordBound: 1000, preservesWordOrder: false,
          nextRandomCaseBit: { newDraws += 1; return newDraws.isMultiple(of: 3) },
          didScanSource: { scans.append($0) })
        XCTAssertEqual(Array(actual.text.utf8), Array(expected.text.utf8))
        XCTAssertEqual(actual.sourceFields?.map { Array($0.utf8) }, expected.sourceFields?.map { Array($0.utf8) })
        XCTAssertEqual(actual.noSpaceTargetWords.map { Array($0.utf8) }, expected.noSpaceTargetWords.map { Array($0.utf8) })
        XCTAssertEqual(newDraws, oldDraws)
        let count = source.unicodeScalars.count
        var expectedScans = Array(stride(from: 4096, through: count, by: 4096))
        if count == 0 || !count.isMultiple(of: 4096) { expectedScans.append(count) }
        XCTAssertEqual(scans, expectedScans)
      }
    }
  }

  func testFirstAndFinalBatchCancellationRejectsPreparedBatch() async {
    let source = Array(repeating: "harbor", count: 301).joined(separator: " ")
    for cancelAt in [100, 301] {
      var batches: [Int] = []
      let task = Task { @MainActor in
        try await LivePromptTransformation.prepare(source, configuration: .words(1000),
          preservesNoSpaceBoundaries: false, wordOffset: 7, wordBound: 1000,
          didTransform: {
            batches.append($0)
            if $0 == cancelAt { withUnsafeCurrentTask { $0?.cancel() } }
          })
      }
      do { _ = try await task.value; XCTFail("Cancelled transformation must not publish") }
      catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(batches.last, cancelAt)
    }
  }

  func testAbsoluteFinalWordDoesNotAcquireAnUnderscoreCommit() async throws {
    let configuration = TestConfiguration.words(10).with(modifiers: [.underscoreSeparators])
    let actual = try await LivePromptTransformation.prepare("one two three", configuration: configuration,
      preservesNoSpaceBoundaries: false, wordOffset: 7, wordBound: 10)
    let expected = TestModifierPolicy.transformedBatch("one two three", modifiers: configuration.modifiers,
      language: configuration.language, wordOffset: 7, wordBound: 10,
      preservesWordOrder: true, capturesSourceFields: true)
    XCTAssertEqual(actual.text, expected.text)
    XCTAssertEqual(actual.sourceFields, expected.sourceFields)
    XCTAssertTrue(actual.text.hasSuffix("three"))
  }

  func testAboveOldCeilingTransformsEveryRetainedField() async throws {
    let source = Array(repeating: "harbor", count: 100_001).joined(separator: " ")
    let configuration = TestConfiguration.words(100_101)
    var batches: [Int] = []
    let actual = try await LivePromptTransformation.prepare(source, configuration: configuration,
      preservesNoSpaceBoundaries: false, wordOffset: 100, wordBound: 100_101,
      didTransform: { batches.append($0) })
    XCTAssertEqual(actual.text, source)
    XCTAssertEqual(actual.sourceFields?.count, 100_001)
    XCTAssertEqual(batches.count, 1001)
    XCTAssertEqual(batches.last, 100_001)
  }
}
