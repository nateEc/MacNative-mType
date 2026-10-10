import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Typebar

@MainActor private final class PracticeLayoutCountingHost<Content: View>: NSHostingView<Content> {
  private(set) var layoutCount = 0
  var captureLayoutAtCount: Int?
  private(set) var capturedLayoutStack: [String] = []
  private(set) var invalidationCount = 0
  var captureInvalidationAtCount: Int?
  private(set) var capturedInvalidationStack: [String] = []

  override var needsLayout: Bool {
    didSet {
      guard needsLayout else { return }
      invalidationCount += 1
      if invalidationCount == captureInvalidationAtCount {
        captureInvalidationAtCount = nil
        capturedInvalidationStack = Array(Thread.callStackSymbols.prefix(40))
      }
    }
  }

  override func layout() {
    layoutCount += 1
    if layoutCount == captureLayoutAtCount {
      captureLayoutAtCount = nil
      capturedLayoutStack = Array(Thread.callStackSymbols.prefix(40))
    }
    super.layout()
  }
}

@MainActor final class PracticeCompositionHostTests: XCTestCase {
  func testProductionPracticeCompositionMountsNativeInputAndSurvivesFirstInsertion() throws {
    try checkProductionHost(checksMarkedText: false)
  }

  func testProductionCompositionModesUpdateAndCancelWithoutCommitting() throws {
    try checkProductionHost(checksMarkedText: true)
  }

  func testBelowCandidateWrapsAlongsideActiveTagsAndPaceWithoutOpeningWindow() throws {
    try checkProductionHost(checksMarkedText: true, checksBelowStatus: true)
  }

  func testMixedDirectionProductionCompositionUsesAllCandidateSlots() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .hebrew)
  }

  func testArabicMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .arabic)
  }

  func testPersianMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .persian)
  }

  func testUrduMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .urdu)
  }

  func testPashtoMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .pashto)
  }

  func testSindhiMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .sindhi)
  }

  func testKurdishMixedDirectionProductionCompositionPreservesJoinedRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .kurdishCentral)
  }

  func testYiddishMixedDirectionProductionCompositionPreservesRTLRun() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .yiddish)
  }

  func testArabicBanglaMixedProductionCompositionPreservesOppositeJoiningRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .bangla)
  }

  func testArabicHindiMixedProductionCompositionPreservesOppositeJoiningRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .hindi)
  }

  func testArabicHindi1kMixedProductionCompositionPreservesOppositeJoiningRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .hindi1k)
  }

  func testArabicTamilMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .tamil)
  }

  func testArabicTamil1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .tamil1k)
  }

  func testArabicTamilOldMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .tamilOld)
  }

  func testArabicGujaratiMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .gujarati)
  }

  func testArabicGujarati1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .gujarati1k)
  }

  func testArabicNepaliMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .nepali)
  }

  func testArabicNepali1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .nepali1k)
  }

  func testArabicSanskritMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .sanskrit)
  }

  func testArabicKannadaMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .kannada)
  }

  func testArabicKhmerMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .khmer)
  }

  func testArabicKoreanMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .korean)
  }

  func testArabicKorean1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .korean1k)
  }

  func testArabicKorean5kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .korean5k)
  }

  func testArabicMalayalamMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .malayalam)
  }

  func testArabicSinhalaMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .sinhala)
  }

  func testArabicTeluguMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .telugu)
  }

  func testArabicTelugu1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .telugu1k)
  }

  func testArabicTibetanMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .tibetan)
  }

  func testArabicTibetan1kMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .tibetan1k)
  }

  func testArabicMyanmarBurmeseMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .myanmarBurmese)
  }

  func testArabicLikanuMixedProductionCompositionPreservesOppositeShapedRuns() throws {
    try checkProductionHost(checksMarkedText: true, mixedLanguage: .likanu)
  }

  private func checkProductionHost(checksMarkedText: Bool, mixedLanguage: TypingLanguage? = nil,
    checksBelowStatus: Bool = false) throws {
    let mixedDirection = mixedLanguage != nil
    let checksDevanagari = [.hindi, .hindi1k, .nepali, .nepali1k, .sanskrit].contains(mixedLanguage)
    let checksTamil = [.tamil, .tamil1k, .tamilOld].contains(mixedLanguage)
    let checksGujarati = [.gujarati, .gujarati1k].contains(mixedLanguage)
    let checksKannada = mixedLanguage == .kannada
    let checksKhmer = mixedLanguage == .khmer
    let checksKorean = [.korean, .korean1k, .korean5k].contains(mixedLanguage)
    let checksMalayalam = mixedLanguage == .malayalam
    let checksSinhala = mixedLanguage == .sinhala
    let checksTelugu = [.telugu, .telugu1k].contains(mixedLanguage)
    let checksTibetan = [.tibetan, .tibetan1k].contains(mixedLanguage)
    let checksMyanmar = mixedLanguage == .myanmarBurmese
    let checksLikanu = mixedLanguage == .likanu
    let checksLTRJoiningRun = mixedLanguage == .bangla || checksDevanagari || checksTamil || checksGujarati || checksKannada || checksKhmer || checksKorean || checksMalayalam || checksSinhala || checksTelugu || checksTibetan || checksMyanmar || checksLikanu
    let checksConnectedRun = checksLTRJoiningRun || [.arabic, .persian, .urdu, .pashto, .sindhi, .kurdishCentral].contains(mixedLanguage)
    let extendedWord: String?
    switch mixedLanguage {
    case .persian: extendedWord = "پیام"
    case .urdu: extendedWord = "ٹماٹر"
    case .pashto: extendedWord = "پښتو"
    case .sindhi: extendedWord = "سنڌي"
    case .kurdishCentral: extendedWord = "کوردی"
    case .yiddish: extendedWord = "ייִדיש"
    case .bangla: extendedWord = "বাংলা"
    case .hindi, .hindi1k, .nepali, .nepali1k, .sanskrit: extendedWord = "किरण"
    case .tamil, .tamil1k, .tamilOld: extendedWord = "கொடி"
    case .gujarati, .gujarati1k: extendedWord = "કિરણ"
    case .kannada: extendedWord = "ಕಿರಣ"
    case .khmer: extendedWord = "ខ្មែរ"
    case .korean, .korean1k, .korean5k: extendedWord = "한글"
    case .malayalam: extendedWord = "കിരണം"
    case .sinhala: extendedWord = "කිරණ"
    case .telugu, .telugu1k: extendedWord = "కిరణం"
    case .tibetan, .tibetan1k: extendedWord = "བོད་སྐད་"
    case .myanmarBurmese: extendedWord = "မြန်မာ"
    case .likanu: extendedWord = "x\u{0304}ʌʃ"
    default: extendedWord = nil
    }
    let prefix = checksConnectedRun ? "ab سلام" : "ab אב"
    let mixedText = prefix + (extendedWord.map { " " + $0 } ?? "") + " cd"
    let extendedFirstSlot = prefix.count + 1
    let extendedLastSlot = extendedWord.map { extendedFirstSlot + $0.count - 1 }
    let lastRTLSlot = checksConnectedRun ? 6 : 4
    for (hostIndex, automaticSizing) in [true, false, false, true].enumerated() {
      let suite = "PracticeCompositionHostTests.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let settings = AppSettings(defaults: defaults)
      let reduceMotion = ProcessInfo.processInfo.environment["TYPEBAR_TEST_REDUCE_MOTION"] == "1"
      settings.reducePracticeMotion = reduceMotion
      if checksBelowStatus {
        settings.activeResultTags = ["候选行避让验证"]
        settings.paceGuideMode = .custom
        settings.paceGuideCustomWpm = 80
        let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
          difficulty: .normal, rules: .init(), language: .english)
        XCTAssertTrue(settings.saveActiveTestSelection(.init(
          preset: .init(configuration: configuration, customText: "quiet harbor carries a patient silver morning"),
          testParameterMemory: .legacyDefaults(configuration: configuration))))
      }
      if let mixedLanguage {
        let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
          difficulty: .normal, rules: .init(), language: .mixedLanguages,
          mixedLanguageComponents: checksLTRJoiningRun
            ? [.english, .arabic, mixedLanguage] : [.english, mixedLanguage])
        let selection = ActiveTestSelectionDocument(
          preset: .init(configuration: configuration, customText: mixedText),
          testParameterMemory: .legacyDefaults(configuration: configuration))
        XCTAssertTrue(settings.saveActiveTestSelection(selection))
      }
      let container = try ModelContainer(
        for: TestResultRecord.self, TestPresetRecord.self,
        SavedCustomTextRecord.self, ResultFilterPresetRecord.self,
        LocalPersonalBestLedgerRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
      let root = TypebarApp.practiceContent(
        settings: settings,
        account: AccountSession(defaults: defaults),
        announcements: RemoteAnnouncementCenter(defaults: defaults),
        hotkey: GlobalHotkeyMonitor(),
        systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
        network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor()
      )
      .modelContainer(container).frame(width: 1000, height: 720)
      let host = PracticeLayoutCountingHost(rootView: root)
      if !automaticSizing { host.sizingOptions = [] }
      let window = NSWindow(
        contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer {
        window.contentView = nil
        window.close()
      }
      func flush() {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
      }
      func inputs(in view: NSView) -> [TypingInputView] {
        (view as? TypingInputView).map { [$0] } ?? view.subviews.flatMap { inputs(in: $0) }
      }
      flush()
      let input = try XCTUnwrap(inputs(in: host).first)
      func fields(in view: NSView) -> [PromptFieldNativeView] {
        (view as? PromptFieldNativeView).map { [$0] } ?? view.subviews.flatMap { fields(in: $0) }
      }
      func candidateElements(in view: NSView) -> [NSTextField] {
        let own: [NSTextField]
        if let field = view as? NSTextField,
          let label = field.accessibilityLabel(),
          label.hasPrefix("正在组合：") || label == "组合输入候选行" {
          own = [field]
        } else { own = [] }
        return own + view.subviews.flatMap { candidateElements(in: $0) }
      }
      func checkExtendedRun(_ field: PromptFieldNativeView) throws {
        guard let extendedLastSlot else { return }
        let first = try XCTUnwrap(field.measuredRect(for: extendedFirstSlot))
        let last = try XCTUnwrap(field.measuredRect(for: extendedLastSlot))
        if checksLTRJoiningRun {
          XCTAssertLessThan(first.minX, last.minX,
            "The Indic run must retain LTR shaping next to the Arabic RTL run")
        } else {
          XCTAssertGreaterThan(first.minX, last.minX,
            "Language-specific letters must retain their own RTL shaping and source slots")
        }
      }
      if mixedDirection {
        let field = try XCTUnwrap(fields(in: host).first)
        XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
        let firstRTL = try XCTUnwrap(field.measuredRect(for: 3))
        let lastRTL = try XCTUnwrap(field.measuredRect(for: lastRTLSlot))
        XCTAssertGreaterThan(firstRTL.minX, lastRTL.minX,
          "Production word shaping must retain the RTL run's physical order")
        try checkExtendedRun(field)
      }
      if checksMarkedText {
        for style in CompositionDisplayStyle.allCases {
          settings.compositionDisplayStyle = style
          flush()
          let emptyCandidate = candidateElements(in: host).first
          if !mixedDirection, style == .below {
            XCTAssertEqual(try XCTUnwrap(emptyCandidate).stringValue, " ")
          }
          input.setMarkedText(
            "候", selectedRange: .init(location: 1, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertTrue(input.hasMarkedText())
          if !mixedDirection {
            let candidates = candidateElements(in: host)
            XCTAssertEqual(candidates.count, style == .below ? 1 : 0)
            if style == .below, let candidate = candidates.first {
              XCTAssertEqual(candidate.accessibilityLabel(), "正在组合：候")
              XCTAssertEqual(candidate.stringValue, "候")
              XCTAssertTrue(candidate === emptyCandidate)
              XCTAssertEqual(candidate.alignment, .center)
              XCTAssertEqual(try XCTUnwrap(candidate.font).pointSize, settings.fontSize)
              let frame = candidate.convert(candidate.bounds, to: host)
              XCTAssertEqual(frame.midX, host.bounds.midX, accuracy: 2,
                "Below composition must be centered, not a bottom-leading badge")
              XCTAssertGreaterThanOrEqual(frame.height, settings.fontSize,
                "Below composition must retain the selected practice font size")
              XCTAssertGreaterThan(frame.width, host.bounds.width * 0.7)
              let field = try XCTUnwrap(fields(in: host).first)
              let promptFrame = field.convert(field.visibleRect, to: host)
              if host.isFlipped {
                XCTAssertGreaterThanOrEqual(frame.minY, promptFrame.maxY)
              } else {
                XCTAssertLessThanOrEqual(frame.maxY, promptFrame.minY)
              }
            }
          }
          let field = try XCTUnwrap(fields(in: host).first)
          let firstValue = try XCTUnwrap(field.accessibilityValue() as? String)
          XCTAssertEqual(
            firstValue.hasPrefix("候"), style == .replace,
            "The production renderer must honor the selected composition display style")
          input.setMarkedText(
            "中文", selectedRange: .init(location: 2, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          if fields(in: host).isEmpty {
            print("BELOW HOST missing field style=\(style) marked=\(input.hasMarkedText()) inputs=\(inputs(in: host).count) sameInput=\(inputs(in: host).contains { $0 === input }) sizing=\(automaticSizing)")
          }
          XCTAssertTrue(
            fields(in: host).contains { $0 === field },
            "Updating marked text must retain the field renderer")
          if !mixedDirection, style == .below {
            XCTAssertEqual(candidateElements(in: host).first?.stringValue, "中文")
            XCTAssertTrue(candidateElements(in: host).first === emptyCandidate)
            if checksBelowStatus {
              let long = String(repeating: "候选文本换行验证", count: 8)
              input.setMarkedText(long, selectedRange: .init(location: long.utf16.count, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
              let candidate = try XCTUnwrap(candidateElements(in: host).first)
              XCTAssertEqual(candidate.stringValue, long)
              XCTAssertTrue(candidate === emptyCandidate)
              XCTAssertGreaterThan(candidate.bounds.height, settings.fontSize * 1.5)
              if let directory = ProcessInfo.processInfo.environment["TYPEBAR_BELOW_QA_IMAGE_DIRECTORY"] {
                candidate.scrollToVisible(candidate.bounds.insetBy(dx: 0, dy: -120))
                flush()
                XCTAssertTrue(host.bounds.contains(candidate.convert(candidate.bounds, to: host)),
                  "The complete candidate row must be visible before visual QA")
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(
                  to: URL(fileURLWithPath: directory).appendingPathComponent("below-status-\(hostIndex).png"))
              }
              XCTAssertFalse(window.isVisible)
              input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
            }
          }
          if style == .replace {
            XCTAssertTrue((field.accessibilityValue() as? String)?.hasPrefix("中文") == true)
            if mixedDirection {
              XCTAssertGreaterThan(try XCTUnwrap(field.measuredRect(for: 3)).minX,
                try XCTUnwrap(field.measuredRect(for: lastRTLSlot)).minX,
                "Candidate projection must not reverse the untouched RTL run")
              try checkExtendedRun(field)
            }
          }
          input.unmarkText()
          flush()
          XCTAssertFalse(input.hasMarkedText())
          if !mixedDirection, style == .below {
            let candidate = try XCTUnwrap(candidateElements(in: host).first)
            XCTAssertEqual(candidate.stringValue, " ")
            XCTAssertTrue(candidate === emptyCandidate)
            XCTAssertGreaterThanOrEqual(candidate.bounds.height, settings.fontSize)
          }
          input.setMarkedText(
            "候", selectedRange: .init(location: 1, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertEqual(
            try XCTUnwrap(fields(in: host).first).accessibilityValue() as? String,
            firstValue, "Cancellation must not commit either candidate or consume target slots")
          input.unmarkText()
          flush()
          XCTAssertTrue(inputs(in: host).contains { $0 === input })
          XCTAssertFalse(window.isVisible)
        }
        settings.compositionDisplayStyle = .replace
        input.setMarkedText(
          "候", selectedRange: .init(location: 1, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        input.insertText("Q", replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        XCTAssertFalse(input.hasMarkedText(), "Accepting text must clear the native marked range")
        input.setMarkedText(
          "候", selectedRange: .init(location: 1, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        let afterCommit = try XCTUnwrap(fields(in: host).first?.accessibilityValue() as? String)
        XCTAssertTrue(afterCommit.contains("候"))
        XCTAssertFalse(
          afterCommit.hasPrefix("候"), "Accepted input must advance the production caret")
        input.unmarkText()
        input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        input.setMarkedText(
          "候", selectedRange: .init(location: 1, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        XCTAssertTrue(
          (fields(in: host).first?.accessibilityValue() as? String)?.hasPrefix("候") == true,
          "Deleting the accepted character must restore the first target slot")
        input.unmarkText()
        flush()
        XCTAssertTrue(inputs(in: host).contains { $0 === input })
        XCTAssertFalse(window.isVisible)
        if checksConnectedRun {
          input.insertText("ab ", replacementRange: .init(location: NSNotFound, length: 0))
          input.setMarkedText("سلا", selectedRange: .init(location: 3, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          let field = try XCTUnwrap(fields(in: host).first)
          XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
          XCTAssertEqual(try XCTUnwrap(field.measuredRect(for: 4)),
            try XCTUnwrap(field.measuredRect(for: 5)),
            "A marked lam-alef must stay joined within the active Arabic field")
          input.unmarkText(); flush()
          XCTAssertEqual(field.accessibilityValue() as? String, mixedText,
            "Cancelling the Arabic candidate must preserve the original source")
          input.insertText("س", replacementRange: .init(location: NSNotFound, length: 0))
          input.setMarkedText("لا", selectedRange: .init(location: 2, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
          XCTAssertTrue(inputs(in: host).contains { $0 === input })
          XCTAssertTrue(fields(in: host).contains { $0 === field })
          input.unmarkText(); flush()
          XCTAssertFalse(input.hasMarkedText())
          XCTAssertFalse(window.isVisible)
          if checksLTRJoiningRun {
            let firstPart: String, lastPart: String
            if checksLikanu { (firstPart, lastPart) = ("x\u{0304}", "ʌʃ") }
            else if checksMyanmar { (firstPart, lastPart) = ("မြန်", "မာ") }
            else if checksTibetan { (firstPart, lastPart) = ("བོད་", "སྐད་") }
            else if checksTelugu { (firstPart, lastPart) = ("కి", "రణం") }
            else if checksSinhala { (firstPart, lastPart) = ("කි", "රණ") }
            else if checksMalayalam { (firstPart, lastPart) = ("കി", "രണം") }
            else if checksKorean { (firstPart, lastPart) = ("한", "글") }
            else if checksKhmer { (firstPart, lastPart) = ("ខ្មែ", "រ") }
            else if checksKannada { (firstPart, lastPart) = ("ಕಿ", "ರಣ") }
            else if checksGujarati { (firstPart, lastPart) = ("કિ", "રણ") }
            else if checksTamil { (firstPart, lastPart) = ("கொ", "டி") }
            else if checksDevanagari { (firstPart, lastPart) = ("कि", "रण") }
            else { (firstPart, lastPart) = ("বাং", "লা") }
            let wholeWord = try XCTUnwrap(extendedWord)
            input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            input.insertText("سلام ", replacementRange: .init(location: NSNotFound, length: 0))
            for style in CompositionDisplayStyle.allCases {
              settings.compositionDisplayStyle = style
              if checksKorean {
                for candidate in ["ㅎ", "하", "한"] {
                  input.setMarkedText(candidate,
                    selectedRange: .init(location: candidate.utf16.count, length: 0),
                    replacementRange: .init(location: NSNotFound, length: 0))
                  flush()
                  XCTAssertTrue(input.hasMarkedText())
                  XCTAssertEqual(field.accessibilityValue() as? String,
                    style == .replace ? "ab سلام " + candidate + "글 cd" : mixedText)
                  XCTAssertTrue(inputs(in: host).contains { $0 === input })
                  XCTAssertTrue(fields(in: host).contains { $0 === field })
                }
                input.unmarkText(); flush()
                XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
              }
              input.setMarkedText("X", selectedRange: .init(location: 1, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
              XCTAssertEqual(field.accessibilityValue() as? String,
                style == .replace ? "ab سلام X" + wholeWord.dropFirst() + " cd" : mixedText,
                "The selected style must affect the active Indic field, not only the initial Latin field")
              input.unmarkText(); flush()
              XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
              input.setMarkedText(firstPart, selectedRange: .init(location: firstPart.utf16.count, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
              input.setMarkedText(wholeWord, selectedRange: .init(location: wholeWord.utf16.count, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
              XCTAssertTrue(input.hasMarkedText())
              XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
              try checkExtendedRun(field)
              input.unmarkText(); flush()
              XCTAssertEqual(field.accessibilityValue() as? String, mixedText,
                "Cancelling the Indic candidate must retain the source after the completed Arabic word")
              input.insertText(firstPart, replacementRange: .init(location: NSNotFound, length: 0))
              input.setMarkedText(lastPart, selectedRange: .init(location: lastPart.utf16.count, length: 0),
                replacementRange: .init(location: NSNotFound, length: 0))
              flush()
              XCTAssertTrue(input.hasMarkedText())
              XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
              try checkExtendedRun(field)
              XCTAssertTrue(inputs(in: host).contains { $0 === input })
              XCTAssertTrue(fields(in: host).contains { $0 === field })
              input.unmarkText(); flush()
              XCTAssertFalse(input.hasMarkedText())
              XCTAssertFalse(window.isVisible)
              for _ in firstPart.utf16 {
                input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
              }
              flush()
              XCTAssertEqual(field.accessibilityValue() as? String, mixedText)
              XCTAssertTrue(inputs(in: host).contains { $0 === input })
              XCTAssertTrue(fields(in: host).contains { $0 === field })
            }
          }
        }
        continue
      }
      for (insertion, text) in ["a", "b", "c"].enumerated() {
        let initialFrame = host.frame
        let initialLayoutCount = host.layoutCount
        let start = ProcessInfo.processInfo.systemUptime
        input.insertText(text, replacementRange: .init(location: NSNotFound, length: 0))
        let inserted = ProcessInfo.processInfo.systemUptime
        host.layoutSubtreeIfNeeded()
        let laidOut = ProcessInfo.processInfo.systemUptime
        let synchronousLayouts = host.layoutCount - initialLayoutCount
        if insertion == 1,
          ProcessInfo.processInfo.environment["TYPEBAR_TEST_LAYOUT_STACK"] == "1"
        {
          host.captureLayoutAtCount = host.layoutCount + 10
          host.captureInvalidationAtCount = host.invalidationCount + 10
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let delivered = ProcessInfo.processInfo.systemUptime
        let deliveredLayouts = host.layoutCount - initialLayoutCount - synchronousLayouts
        host.layoutSubtreeIfNeeded()
        let finished = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(
          inputs(in: host).contains { $0 === input },
          "First input must retain the native input owner"
        )
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(host.frame, initialFrame, "Input must not resize the fixed practice host")
        print(
          "practice-host automaticSizing=\(automaticSizing) reduceMotion=\(reduceMotion) insertion=\(insertion) input=\(inserted - start) layout=\(laidOut - inserted) delivery=\(delivered - laidOut) finalLayout=\(finished - delivered) synchronousLayouts=\(synchronousLayouts) deliveredLayouts=\(deliveredLayouts) finalLayouts=\(host.layoutCount - initialLayoutCount - synchronousLayouts - deliveredLayouts)"
        )
        if insertion == 1, !host.capturedLayoutStack.isEmpty {
          print(
            "practice-host layout-stack automaticSizing=\(automaticSizing)\n"
              + host.capturedLayoutStack.joined(separator: "\n"))
        }
        if insertion == 1, !host.capturedInvalidationStack.isEmpty {
          print(
            "practice-host invalidation-stack automaticSizing=\(automaticSizing)\n"
              + host.capturedInvalidationStack.joined(separator: "\n"))
        }
      }
      for backdrop in PracticeBackdropStyle.allCases {
        settings.practiceBackdrop = backdrop
        flush()
        XCTAssertTrue(
          inputs(in: host).contains { $0 === input },
          "Background branch changes must not replace the practice input owner")
      }
    }
  }
}
