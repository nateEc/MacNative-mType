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

  private func checkProductionHost(checksMarkedText: Bool) throws {
    for automaticSizing in [true, false, false, true] {
      let suite = "PracticeCompositionHostTests.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let settings = AppSettings(defaults: defaults)
      let reduceMotion = ProcessInfo.processInfo.environment["TYPEBAR_TEST_REDUCE_MOTION"] == "1"
      settings.reducePracticeMotion = reduceMotion
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
