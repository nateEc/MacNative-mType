import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Typebar

@MainActor final class PracticeCompositionHostTests: XCTestCase {
  func testProductionPracticeCompositionMountsNativeInputAndSurvivesFirstInsertion() throws {
    for automaticSizing in [true, false, false, true] {
      let suite = "PracticeCompositionHostTests.\(UUID())"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let settings = AppSettings(defaults: defaults)
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
      let host = NSHostingView(rootView: root)
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
      for (insertion, text) in ["a", "b", "c"].enumerated() {
        let start = ProcessInfo.processInfo.systemUptime
        input.insertText(text, replacementRange: .init(location: NSNotFound, length: 0))
        let inserted = ProcessInfo.processInfo.systemUptime
        host.layoutSubtreeIfNeeded()
        let laidOut = ProcessInfo.processInfo.systemUptime
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let delivered = ProcessInfo.processInfo.systemUptime
        host.layoutSubtreeIfNeeded()
        let finished = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(
          inputs(in: host).contains { $0 === input },
          "First input must retain the native input owner"
        )
        XCTAssertFalse(window.isVisible)
        print(
          "practice-host automaticSizing=\(automaticSizing) insertion=\(insertion) input=\(inserted - start) layout=\(laidOut - inserted) delivery=\(delivered - laidOut) finalLayout=\(finished - delivered)"
        )
      }
      for backdrop in PracticeBackdropStyle.allCases {
        settings.practiceBackdrop = backdrop
        flush()
        XCTAssertTrue(inputs(in: host).contains { $0 === input },
          "Background branch changes must not replace the practice input owner")
      }
    }
  }
}
