import Foundation
import SwiftData
import XCTest
@testable import Typebar

final class CustomSourceAdmissionTests: XCTestCase {
  private let start = Date(timeIntervalSinceReferenceDate: 830_000_000)

  private func config(_ completion: CustomTextCompletion = .finish, pipe: Bool = true,
    limit: Int = 2, difficulty: Difficulty = .normal) -> TestConfiguration {
    .init(mode: .custom, duration: completion == .time ? 120 : nil,
      wordLimit: completion == .words ? limit : nil, difficulty: difficulty, rules: .init(),
      customTextCompletion: completion, customTextSectionLimit: completion == .sections ? limit : nil,
      customTextOrdering: .inOrder, customTextPipeDelimiter: pipe)
  }

  func testNewlineCandidatesAreValidWithoutAddingAnyVisibleWord() {
    for source in ["\n", "\r", "\r\n", " \r\n \r \n ", "\u{00A0}\n\u{2002}"] {
      XCTAssertTrue(CustomTextPolicy.isValid(source), source.debugDescription)
      XCTAssertTrue(CustomTextPolicy.isValid(source, configuration: config()), source.debugDescription)
      XCTAssertTrue(CustomTextPolicy.isValid(source, configuration: config(pipe: false)), source.debugDescription)
    }
    XCTAssertTrue(CustomTextPolicy.isValid(String(repeating: "\n", count: CustomTextPolicy.maximumLength)))
    XCTAssertFalse(CustomTextPolicy.isValid(String(repeating: "\n", count: CustomTextPolicy.maximumLength + 1)))
  }

  func testLiteralControlAndUnmappedWhitespaceContentIsNotTreatedAsAnEmptyPool() {
    for source in ["\t", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}", "\u{200B}", "\u{FEFF}"] {
      XCTAssertTrue(CustomTextPolicy.isValid(source), source.debugDescription)
      XCTAssertTrue(CustomTextPolicy.isValid(source, configuration: config()), source.debugDescription)
    }
  }

  func testEmptyAndMappedSpaceOnlySourcesRemainRejectedAndPipeHasItsOwnGuard() {
    for source in ["", "  ", "\u{00A0}\u{2002}\u{202F}\u{205F}"] {
      XCTAssertFalse(CustomTextPolicy.isValid(source), source.debugDescription)
    }
    XCTAssertTrue(CustomTextPolicy.isValid("|"))
    XCTAssertFalse(CustomTextPolicy.isValid("|", configuration: config()))
    XCTAssertTrue(CustomTextPolicy.isValid("|", configuration: config(pipe: false)))
    XCTAssertFalse(CustomTextPolicy.isValid(" | | ", configuration: config()))
  }

  func testSectionSummaryUsesTheSameLFAndLiteralDelimiterPreparationAsTheFactory() {
    XCTAssertEqual(CustomTextPolicy.sections(in: " \r\n | \n | bay "), ["\n", "\n", "bay"])
    XCTAssertEqual(CustomTextPolicy.sections(in: "\n"), ["\n"])
    XCTAssertEqual(CustomTextPolicy.sections(in: " \u{0301}a | bay "), ["\u{0301}a", "bay"])
    XCTAssertEqual(CustomTextPolicy.sections(in: " | | "), [])
  }

  func testOrdinarySavedLFTextsKeepTitleAndLengthBounds() {
    XCTAssertTrue(CustomTextPolicy.isValidSavedText(title: "Owned blank exercise", text: "\n\n"))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: " \n", text: "\n"))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: String(repeating: "a", count: 81), text: "\n"))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned", text: " "))
    XCTAssertFalse(CustomTextPolicy.isValidSavedText(title: "Owned",
      text: String(repeating: "\n", count: CustomTextPolicy.maximumLength + 1)))
  }

  func testLFSourceAndExplicitDelimiterRoundTripEveryNativeShareMode() throws {
    for completion in CustomTextCompletion.allCases {
      for pipe in [false, true] {
        let preset = SavedTestPreset(configuration: config(completion, pipe: pipe), customText: "\n\n")
        let link = try TestConfigurationShare.link(for: preset)
        let decoded = try TestConfigurationShare.preset(from: link)
        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.customText, "\n\n", "分享不能把原始文本改成清理后的候选")
      }
    }
  }

  func testSelectionRestoresLFSourceFromAnIsolatedDefaultsDomain() throws {
    let name = "Typebar.CustomSourceAdmissionTests." + UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preset = SavedTestPreset(configuration: config(.sections), customText: "\r\n\n")
    let document = ActiveTestSelectionDocument(preset: preset,
      testParameterMemory: .legacyDefaults(configuration: preset.configuration))
    XCTAssertEqual(ActiveTestSelectionPolicy.validated(document), document)
    XCTAssertTrue(ActiveTestSelectionStore(defaults: defaults).save(document))
    XCTAssertEqual(ActiveTestSelectionStore(defaults: defaults).load(), document)
  }

  func testFormalArchiveAndMergeKeepOrdinaryLFTextAndSelectionWithoutBackfill() throws {
    let text = NamedSavedText(id: UUID(), title: "Owned blank exercise", text: "\r\n\n")
    let preset = SavedTestPreset(configuration: config(), customText: text.text)
    let selection = ActiveTestSelectionDocument(preset: preset,
      testParameterMemory: .legacyDefaults(configuration: preset.configuration))
    let archive = try TypebarDataTransfer.importArchive(from: TypebarDataTransfer.exportArchive(
      settings: .init(), results: [], presets: [], savedTexts: [text], activeTestSelection: selection, at: start))
    XCTAssertEqual(archive.savedTexts, [text])
    XCTAssertEqual(archive.activeTestSelection, selection)
    XCTAssertEqual(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: []), [text])
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [text]).isEmpty)
    XCTAssertTrue(TypebarArchiveMerge.savedTextsToInsert(from: archive, existing: [],
      deletedIDs: [try XCTUnwrap(text.id)]).isEmpty)
  }

  @MainActor
  func testOrdinaryLFRecordCanBeStoredAndSelectedInAnInMemorySwiftDataContainer() throws {
    XCTAssertTrue(CustomTextPolicy.isValidSavedText(title: "Owned blank exercise", text: "\n"))
    let container = try ModelContainer(for: SavedCustomTextRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let record = SavedCustomTextRecord(title: "Owned blank exercise", text: "\n")
    container.mainContext.insert(record)
    try container.mainContext.save()
    let stored = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<SavedCustomTextRecord>()).first)
    XCTAssertEqual(stored.selection.text, "\n")
    XCTAssertFalse(stored.selection.isLong)
    var attempt = TestSessionFactory.make(configuration: config(), customText: stored.selection.text)
    XCTAssertEqual(attempt.prompt, "\n")
    attempt.insert("\n", at: start)
    XCTAssertEqual(attempt.outcome, .completed)
    XCTAssertEqual(attempt.errors, 0)
  }

  func testPureLFCanFinishPipeTextAndSingleNonPipeTextWithoutFallback() throws {
    for difficulty in Difficulty.allCases {
      for pipe in [false, true] {
        var attempt = TestSessionFactory.make(configuration: config(pipe: pipe, difficulty: difficulty), customText: "\n")
        XCTAssertEqual(attempt.prompt, "\n")
        attempt.insert("\n", at: start)
        XCTAssertEqual(attempt.outcome, .completed)
        XCTAssertEqual(attempt.completedWordCount, 1)
        XCTAssertEqual(attempt.errors, 0)
        XCTAssertTrue(attempt.wordReviews.allSatisfy(\.isCorrect))
        let result = try XCTUnwrap(attempt.result())
        XCTAssertEqual(try XCTUnwrap(TestResultRecord(result: result).portableResult), result)
        XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 1), "\n")
      }
    }
  }

  func testPureNewlineSectionAndPipeWordBudgetsContinueAcrossOneHundredSlots() {
    for completion in [CustomTextCompletion.words, .sections] {
      for pipe in completion == .sections ? [false, true] : [true] {
        var attempt = TestSessionFactory.make(configuration: config(completion, pipe: pipe, limit: 101), customText: "\r\n")
        let initial = String(repeating: "\n", count: 100)
        XCTAssertEqual(attempt.prompt, initial)
        attempt.insertBatch(initial, at: start)
        XCTAssertEqual(attempt.outcome, .active)
        attempt.insert("\n", at: start.addingTimeInterval(1))
        XCTAssertEqual(attempt.prompt, initial + "\n")
        XCTAssertEqual(attempt.outcome, .completed)
        XCTAssertEqual(attempt.completedWordCount, 101)
        XCTAssertEqual(attempt.errors, 0)
        XCTAssertEqual(attempt.wordReviews.count, 101)
        XCTAssertEqual(attempt.repeatedAttempt().prompt, initial)
      }
    }
  }

  func testPureLFInfiniteAndTimedPipeInputsRemainPlayableWithoutChangingTheirLimits() throws {
    for completion in [CustomTextCompletion.words, .time] {
      var attempt = TestSessionFactory.make(configuration: config(completion, limit: 0), customText: "\n")
      if completion == .time {
        for index in 0..<205 {
          attempt.insert("\n", at: start.addingTimeInterval(Double(index) * 119 / 204))
        }
      } else {
        attempt.insertBatch(String(repeating: "\n", count: 205), at: start)
      }
      XCTAssertEqual(attempt.completedWordCount, 205)
      XCTAssertEqual(attempt.outcome, .active)
      XCTAssertEqual(attempt.errors, 0)
      if completion == .time { attempt.tick(at: start.addingTimeInterval(120)) }
      else { attempt.bailOut(at: start.addingTimeInterval(1)) }
      let result = try XCTUnwrap(attempt.result())
      XCTAssertEqual(result.outcome, completion == .time ? .completed : .bailedOut)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: 120), attempt.typed)
    }
  }
}
