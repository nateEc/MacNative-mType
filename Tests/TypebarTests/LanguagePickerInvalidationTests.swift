import AppKit
import SwiftUI
import XCTest

@testable import Typebar

@MainActor final class LanguagePickerInvalidationTests: XCTestCase {
  private final class Probe {
    var toggle: (() -> Void)?
    var bodyCount = 0
    var disabled = false
    var selection: TypingLanguage?
  }

  private struct Content: View {
    let languages: [TypingLanguage]
    let probe: Probe
    var usesFocusPresentation = false
    @State private var disabled = false
    @State private var language = TypingLanguage.english

    var body: some View {
      probe.bodyCount += 1
      probe.disabled = disabled
      probe.selection = language
      probe.toggle = { disabled.toggle() }
      let picker = Picker("语言", selection: $language) {
        ForEach(languages, id: \.self) { Text($0.displayName).tag($0) }
      }
      .disabled(disabled)
      .frame(width: 400, height: 100)
      return Group {
        if usesFocusPresentation {
          picker.opacity(disabled ? 0 : 1)
            .allowsHitTesting(!disabled)
            .accessibilityHidden(disabled)
            .animation(.easeInOut(duration: 0.125), value: disabled)
        } else {
          picker
        }
      }
    }
  }

  func testHostedPickerDisabledTransitionsWithSmallAndCompleteLanguageCatalogs() throws {
    for usesFocusPresentation in [false, true] {
      for languages in [Array(TypingLanguage.allCases.prefix(2)), TypingLanguage.allCases] {
        let probe = Probe()
        let host = NSHostingView(
          rootView: Content(
            languages: languages, probe: probe,
            usesFocusPresentation: usesFocusPresentation))
        let window = NSWindow(
          contentRect: .init(x: 0, y: 0, width: 400, height: 100),
          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
          probe.toggle = nil
          window.contentView = nil
          window.close()
        }
        func flush() {
          host.layoutSubtreeIfNeeded()
          RunLoop.main.run(until: Date().addingTimeInterval(0.2))
          host.layoutSubtreeIfNeeded()
        }
        let start = ProcessInfo.processInfo.systemUptime
        flush()
        print(
          "language-picker focus=\(usesFocusPresentation) options=\(languages.count) initial=\(ProcessInfo.processInfo.systemUptime - start)"
        )
        for transition in 1...4 {
          let before = probe.bodyCount
          let start = ProcessInfo.processInfo.systemUptime
          try XCTUnwrap(probe.toggle)()
          flush()
          print(
            "language-picker focus=\(usesFocusPresentation) options=\(languages.count) transition=\(transition) elapsed=\(ProcessInfo.processInfo.systemUptime - start) bodies=\(probe.bodyCount - before)"
          )
          XCTAssertGreaterThan(probe.bodyCount, before)
          XCTAssertEqual(probe.disabled, transition % 2 == 1)
          XCTAssertEqual(probe.selection, .english)
          XCTAssertFalse(window.isVisible)
        }
      }
    }
  }
}
