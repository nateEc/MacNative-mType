import XCTest
@testable import Typebar

@MainActor final class WholePreviewChunkAssemblyTests: XCTestCase {
  func testAboveFormerCeilingAssemblesEveryNoSpaceWordAndBoundary() async throws {
    let configuration = TestConfiguration.words(100_001).with(modifiers: [.binaryStream, .noSpaces])
    let chunks = try await WholePreviewWordPreparation.prepare(configuration: configuration)
    XCTAssertEqual(chunks.count, 1001)
    let actual = try await WholePreviewChunkAssembly.assemble(chunks)
    XCTAssertEqual(Array(actual.prompt.utf8), Array(chunks.map(\.transformed).joined().utf8))
    XCTAssertEqual(actual.prompt.count, 800_008)
    XCTAssertEqual(actual.targetWords, chunks.flatMap(\.noSpaceTargetWords))
    XCTAssertEqual(actual.targetWords.count, 100_001)
    XCTAssertEqual(actual.endIndices, (1...100_001).map { $0 * 8 })
  }

  func testAssemblyPreservesExactUnicodePromptBoundariesAndTargets() async throws {
    for modifiers: [TestModifier] in [[], [.noSpaces], [.underscoreSeparators], [.messagingStyle]] {
      let configuration = TestConfiguration.words(201).with(modifiers: modifiers)
      let words = ["e\u{301}", "👩🏽‍💻", "中文", "سلام"]
      var draw = 0
      let chunks = try await WholePreviewWordPreparation.prepare(configuration: configuration,
        sourceWords: words, nextRandomWordIndex: { defer { draw += 1 }; return draw % words.count })
      var counts: [Int] = []
      let actual = try await WholePreviewChunkAssembly.assemble(chunks, didAssemble: { counts.append($0) })
      XCTAssertEqual(Array(actual.prompt.utf8), Array(chunks.map(\.transformed).joined().utf8))
      for word in words { XCTAssertTrue(actual.prompt.contains(word), "The fixture must exercise every Unicode sample") }
      XCTAssertEqual(actual.endIndices,
        NoSpaceWordBoundaryPolicy.endIndices(for: chunks.flatMap(\.noSpaceWordLengths)))
      XCTAssertEqual(actual.targetWords, chunks.flatMap(\.noSpaceTargetWords))
      XCTAssertEqual(counts, Array(1...chunks.count))
    }
  }

  func testCancellationDuringAssemblyDoesNotPublishPartialPromptOrConsumeLaterChunks() async throws {
    let chunks = try await WholePreviewWordPreparation.prepare(configuration: .words(301),
      sourceWords: ["north"], nextRandomWordIndex: { 0 })
    var counts: [Int] = []
    let task = Task { @MainActor in
      try await WholePreviewChunkAssembly.assemble(chunks, didAssemble: { count in
        counts.append(count)
        withUnsafeCurrentTask { $0?.cancel() }
      })
    }
    do { _ = try await task.value; XCTFail("Cancellation must not return an assembly result") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    XCTAssertEqual(counts, [1])
  }

  func testCancellationAfterLastChunkStillRejectsPublication() async throws {
    let chunks = try await WholePreviewWordPreparation.prepare(configuration: .words(1),
      sourceWords: ["north"], nextRandomWordIndex: { 0 })
    let task = Task { @MainActor in
      try await WholePreviewChunkAssembly.assemble(chunks,
        didAssemble: { _ in withUnsafeCurrentTask { $0?.cancel() } })
    }
    do { _ = try await task.value; XCTFail("Last-chunk cancellation must not publish") }
    catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
  }
}
