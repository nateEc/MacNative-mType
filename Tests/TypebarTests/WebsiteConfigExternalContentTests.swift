import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigExternalContentTests: XCTestCase {
  private enum AdmissionFailure: Error, Equatable { case retired }
  func testAdmissionRunsBeforeTransportAndBeforeInterpretingFailedReply() async throws {
    for initiallyRetired in [false, true] {
      var current = !initiallyRetired, reads = 0
      do {
        _ = try await WebsiteConfigExternalContent.prepare(source: .poetry,
          configuration: .words(4).with(modifiers: [.poetryStream]), showAllLines: true,
          checkCurrent: { if !current { throw AdmissionFailure.retired } }) { _, _ in
          reads += 1; current = false; return nil
        }
        XCTFail("Retired read was admitted")
      } catch { XCTAssertEqual(error as? AdmissionFailure, .retired) }
      XCTAssertEqual(reads, initiallyRetired ? 0 : 1)
    }
  }
  func testInitialBudgetRetainsSectionTailAndWholePreviewReadsDistinctSections() async throws {
    let configuration = TestConfiguration.words(201).with(modifiers: [.referenceStream])
    for allLines in [false, true] {
      var reads = 0
      let result = try await WebsiteConfigExternalContent.prepare(source: .encyclopedia,
        configuration: configuration, showAllLines: allLines) { source, language in
        XCTAssertEqual(source, .encyclopedia); XCTAssertEqual(language, .english)
        let start = reads * 60; reads += 1
        return .init(source: source, title: "Section \(reads)", byline: nil,
          tokens: (start..<(start + 60)).map { "owned\($0)" }, separator: " ")
      }
      let initialCount = allLines ? 201 : 100
      XCTAssertEqual(result.initial.text, (0..<initialCount).map { "owned\($0)" }.joined(separator: " "))
      XCTAssertEqual(reads, allLines ? 4 : 2)
      if allLines { XCTAssertNil(result.continuation) }
      else {
        XCTAssertEqual(result.continuation?.text, (100..<120).map { "owned\($0)" }.joined(separator: " "))
      }
      XCTAssertTrue(result.attribution?.contains("Section \(reads)") == true)
    }
  }

  func testNoSpaceSourceRetainsExplicitBoundariesAcrossInitialAndTail() async throws {
    let configuration = TestConfiguration.words(120, language: .simplifiedChinese).with(modifiers: [.referenceStream])
    let tokens = (0..<110).map { "海\($0)" }
    let result = try await WebsiteConfigExternalContent.prepare(source: .encyclopedia,
      configuration: configuration, showAllLines: false) { source, _ in
      .init(source: source, title: "Owned", byline: nil, tokens: tokens, separator: "")
    }
    XCTAssertEqual(result.initial.text, tokens.prefix(100).joined())
    XCTAssertEqual(result.initial.noSpaceBoundarySource, tokens.prefix(100).joined(separator: " "))
    XCTAssertEqual(result.continuation?.text, tokens.suffix(10).joined())
    XCTAssertEqual(result.continuation?.noSpaceBoundarySource, tokens.suffix(10).joined(separator: " "))
  }

  func testNilAndDecodedEmptyHaveDifferentPoetryRecoverySemantics() async throws {
    for source in [LivePracticeContentSource.poetry, .encyclopedia] {
      for empty in [false, true] {
        let configuration = TestConfiguration.words(2).with(modifiers: [source == .poetry ? .poetryStream : .referenceStream])
        do {
          _ = try await WebsiteConfigExternalContent.prepare(source: source, configuration: configuration,
            showAllLines: true) { _, _ in
            empty ? .init(source: source, title: "Empty", byline: nil, tokens: [], separator: " ") : nil
          }
          XCTFail("Unavailable section delivered")
        } catch {
          if source == .poetry && !empty {
            XCTAssertEqual(error as? WebsiteConfigExternalContentError, .poetryUnavailable)
          } else {
            guard case WebsiteConfigSessionBuildError.generationFailed = error else { return XCTFail("\(error)") }
          }
        }
      }
    }
  }

  func testPoetryFailureDuringFillIsNotReplacedWithRepeatedOpening() async throws {
    var reads = 0
    do {
      _ = try await WebsiteConfigExternalContent.prepare(source: .poetry,
        configuration: .words(4).with(modifiers: [.poetryStream]), showAllLines: true) { _, _ in
        reads += 1
        return reads == 1 ? .init(source: .poetry, title: "Short", byline: nil, tokens: ["ab"], separator: " ") : nil
      }
      XCTFail("Short section was repeated to hide a failed pull")
    } catch { XCTAssertEqual(error as? WebsiteConfigExternalContentError, .poetryUnavailable) }
    XCTAssertEqual(reads, 2)
  }

  func testWrongSourceAndIncompatibleSelectionDoNotRequestPoetryDisablement() async throws {
    var reads = 0
    for modifier in [TestModifier.poetryStream, .referenceStream] {
      do {
        _ = try await WebsiteConfigExternalContent.prepare(source: .poetry,
          configuration: .words(2).with(modifiers: [modifier]), showAllLines: true) { _, _ in
          reads += 1
          return .init(source: .encyclopedia, title: "Wrong", byline: nil, tokens: ["ab", "cd"], separator: " ")
        }
        XCTFail("Wrong source admitted")
      } catch {
        guard case WebsiteConfigSessionBuildError.invalidExternalSource = error else { return XCTFail("\(error)") }
      }
    }
    XCTAssertEqual(reads, 1, "An incompatible selection must fail before transport")
  }

  func testCancellationAfterFailedFetchDoesNotDisablePoetry() async throws {
    let task = Task { @MainActor in
      try await WebsiteConfigExternalContent.prepare(source: .poetry,
        configuration: .words(2).with(modifiers: [.poetryStream]), showAllLines: true) { _, _ in
        withUnsafeCurrentTask { $0?.cancel() }
        return nil
      }
    }
    do { _ = try await task.value; XCTFail("Cancelled fetch delivered") }
    catch is CancellationError {}
  }
}
