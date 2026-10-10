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

  private func checkProductionHost(checksMarkedText: Bool, mixedLanguage: TypingLanguage? = nil) throws {
    let mixedDirection = mixedLanguage != nil
    let checksDevanagari = [.hindi, .hindi1k, .nepali, .nepali1k, .sanskrit].contains(mixedLanguage)
    let checksTamil = [.tamil, .tamil1k, .tamilOld].contains(mixedLanguage)
    let checksGujarati = [.gujarati, .gujarati1k].contains(mixedLanguage)
    let checksKannada = mixedLanguage == .kannada
    let checksLTRJoiningRun = mixedLanguage == .bangla || checksDevanagari || checksTamil || checksGujarati || checksKannada
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
    default: extendedWord = nil
    }
    let prefix = checksConnectedRun ? "ab سلام" : "ab אב"
    let mixedText = prefix + (extendedWord.map { " " + $0 } ?? "") + " cd"
    let extendedFirstSlot = prefix.count + 1
    let extendedLastSlot = extendedWord.map { extendedFirstSlot + $0.count - 1 }
    let lastRTLSlot = checksConnectedRun ? 6 : 4
    for automaticSizing in [true, false, false, true] {
      let suite = "PracticeCompositionHostTests.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let settings = AppSettings(defaults: defaults)
      let reduceMotion = ProcessInfo.processInfo.environment["TYPEBAR_TEST_REDUCE_MOTION"] == "1"
      settings.reducePracticeMotion = reduceMotion
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
          input.setMarkedText(
            "候", selectedRange: .init(location: 1, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertTrue(input.hasMarkedText())
          let field = try XCTUnwrap(fields(in: host).first)
          let firstValue = try XCTUnwrap(field.accessibilityValue() as? String)
          XCTAssertEqual(
            firstValue.hasPrefix("候"), style == .replace,
            "The production renderer must honor the selected composition display style")
          input.setMarkedText(
            "中文", selectedRange: .init(location: 2, length: 0),
            replacementRange: .init(location: NSNotFound, length: 0))
          flush()
          XCTAssertTrue(
            fields(in: host).contains { $0 === field },
            "Updating marked text must retain the field renderer")
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
            if checksKannada { (firstPart, lastPart) = ("ಕಿ", "ರಣ") }
            else if checksGujarati { (firstPart, lastPart) = ("કિ", "રણ") }
            else if checksTamil { (firstPart, lastPart) = ("கொ", "டி") }
            else if checksDevanagari { (firstPart, lastPart) = ("कि", "रण") }
            else { (firstPart, lastPart) = ("বাং", "লা") }
            let wholeWord = try XCTUnwrap(extendedWord)
            input.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            input.insertText("سلام ", replacementRange: .init(location: NSNotFound, length: 0))
            for style in CompositionDisplayStyle.allCases {
              settings.compositionDisplayStyle = style
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
