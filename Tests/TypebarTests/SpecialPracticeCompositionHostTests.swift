import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class SpecialPracticeCompositionHostTests: XCTestCase {
  func testProductionASLCompositionUpdatesActualSlotsAndCancellationRestoresGeometry() throws {
    let suite = "SpecialPracticeCompositionHostTests.ASL.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.testModifiers = [.aslVisual]
    let prompt = "quiet harbor morning"
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .english, modifiers: [.aslVisual])
    XCTAssertTrue(settings.saveActiveTestSelection(.init(
      preset: .init(configuration: configuration, customText: prompt),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults),
      announcements: RemoteAnnouncementCenter(defaults: defaults), hotkey: GlobalHotkeyMonitor(),
      systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor())
      .modelContainer(container).frame(width: 1000, height: 720)
    let host = NSHostingView(rootView: content)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    flush()
    let input = try XCTUnwrap(descendants(host, TypingInputView.self).first)
    let owner = try XCTUnwrap(descendants(host, ASLPromptCaretContainer.self).first)
    let initial = try Dictionary(uniqueKeysWithValues: (0..<prompt.count).map {
      ($0, try XCTUnwrap(owner.measuredRect(for: $0)))
    })
    let frame = host.frame
    var session = TypingSession(configuration: configuration, prompt: prompt)
    let longCandidate = String(repeating: "中文", count: 20)
    for style in CompositionDisplayStyle.allCases {
      settings.compositionDisplayStyle = style
      flush()
      for candidate in ["候", "中文", longCandidate] {
        input.setMarkedText(candidate, selectedRange: .init(location: candidate.utf16.count, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        XCTAssertTrue(input.hasMarkedText())
        XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
        XCTAssertTrue(descendants(host, ASLPromptCaretContainer.self).first === owner)
        let projection = try XCTUnwrap(session.promptCompositionProjection(composition: candidate, style: style))
        for cell in projection.cells {
          let rect = try XCTUnwrap(owner.measuredRect(for: cell.id))
          XCTAssertTrue(rect.origin.x.isFinite && rect.origin.y.isFinite)
          XCTAssertGreaterThan(rect.height, 0)
        }
        if style == .replace {
          let marked = projection.cells.filter { $0.compositionIndex != nil }
          XCTAssertEqual(marked.count, candidate.count)
          if marked.count == 2 {
            XCTAssertLessThan(try XCTUnwrap(owner.measuredRect(for: marked[0].id)).minX,
              try XCTUnwrap(owner.measuredRect(for: marked[1].id)).minX,
              "Two marked characters must occupy separate actual ASL layout cells")
          }
          if candidate == longCandidate {
            let rows = try Set(marked.map {
              try XCTUnwrap(owner.measuredRect(for: $0.id)).minY
            })
            XCTAssertGreaterThan(rows.count, 1,
              "The long candidate must actually exercise ASL cross-row layout")
          }
        }
        let rows = descendants(host, NSTextField.self).filter {
          $0.accessibilityLabel()?.hasPrefix("正在组合：") == true
        }
        XCTAssertEqual(rows.count, style == .below ? 1 : 0)
        if style == .below { XCTAssertEqual(rows.first?.stringValue, candidate) }
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(host.frame, frame)
      }
      input.unmarkText()
      flush()
      XCTAssertFalse(input.hasMarkedText())
      for (id, rect) in initial {
        XCTAssertEqual(owner.measuredRect(for: id), rect,
          "Cancellation must restore every original ASL target allocation")
      }
    }
    settings.compositionDisplayStyle = .replace
    flush()
    input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
    session.insertBatch("q", at: Date())
    flush()
    XCTAssertFalse(input.hasMarkedText())
    input.setMarkedText("中文", selectedRange: .init(location: 2, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    let afterCommit = try XCTUnwrap(session.promptCompositionProjection(composition: "中文", style: .replace))
    let marked = afterCommit.markedCells
    XCTAssertEqual(marked.count, 2)
    let firstMarked = try XCTUnwrap(marked.first)
    XCTAssertGreaterThan(try XCTUnwrap(owner.measuredRect(for: firstMarked.id)).minX,
      try XCTUnwrap(owner.measuredRect(for: 0)).minX,
      "The next ASL candidate must follow the accepted q rather than replace it")
    XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
    XCTAssertTrue(descendants(host, ASLPromptCaretContainer.self).first === owner)
    input.unmarkText()
    flush()
    for (id, rect) in initial { XCTAssertEqual(owner.measuredRect(for: id), rect) }
    XCTAssertFalse(window.isVisible)
  }

  func testProductionChooCompositionModesUpdateAndCancelWithoutConsumingTargets() throws {
    let suite = "SpecialPracticeCompositionHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.testModifiers = [.chooVisual]
    let prompt = "quiet harbor morning"
    let configuration = TestConfiguration(mode: .custom, duration: nil, wordLimit: nil,
      difficulty: .normal, rules: .init(), language: .english, modifiers: [.chooVisual])
    XCTAssertTrue(settings.saveActiveTestSelection(.init(
      preset: .init(configuration: configuration, customText: prompt),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let container = try ModelContainer(for: TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self, LocalPersonalBestLedgerRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults),
      announcements: RemoteAnnouncementCenter(defaults: defaults), hotkey: GlobalHotkeyMonitor(),
      systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor())
      .modelContainer(container).frame(width: 1000, height: 720)
    let host = NSHostingView(rootView: content)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, type) }
    }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      host.layoutSubtreeIfNeeded()
    }
    flush()
    let input = try XCTUnwrap(descendants(host, TypingInputView.self).first)
    let owner = try XCTUnwrap(descendants(host, ChooLayerView.self).first)
    XCTAssertEqual(owner.accessibilityLabel(), prompt)
    func textLayers() -> [CATextLayer] {
      owner.layer?.sublayers?.compactMap { $0 as? CATextLayer }.filter { $0.name != "chooHint" } ?? []
    }
    func allocations() -> [CGRect] {
      textLayers().map { CGRect(origin: $0.position, size: $0.bounds.size) }.sorted {
        $0.minY == $1.minY ? $0.minX < $1.minX : $0.minY < $1.minY
      }
    }
    let initialAllocations = allocations()
    XCTAssertFalse(initialAllocations.isEmpty)
    let longCandidate = String(repeating: "中文", count: 20)
    let frame = host.frame
    for style in CompositionDisplayStyle.allCases {
      settings.compositionDisplayStyle = style
      flush()
      for candidate in ["候", "中文", longCandidate] {
        input.setMarkedText(candidate, selectedRange: .init(location: candidate.utf16.count, length: 0),
          replacementRange: .init(location: NSNotFound, length: 0))
        flush()
        XCTAssertTrue(input.hasMarkedText())
        XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
        XCTAssertTrue(descendants(host, ChooLayerView.self).first === owner)
        let displayed = try XCTUnwrap(owner.accessibilityLabel())
        XCTAssertEqual(displayed.hasPrefix(candidate), style == .replace)
        let expected = style == .replace
          ? candidate + String(prompt.dropFirst(min(5, candidate.count)))
          : "quiet" + String(candidate.dropFirst(5)) + " harbor morning"
        XCTAssertEqual(displayed, expected,
          "Off/below retain target ink but must preserve candidate overflow beyond quiet")
        let ink = owner.layer?.sublayers?.compactMap { $0 as? CATextLayer }
          .compactMap { ($0.string as? NSAttributedString)?.string }.joined() ?? ""
        XCTAssertEqual(ink.contains("候") || ink.contains("中"), style == .replace || candidate.count > 5,
          "style=\(style) candidateCount=\(candidate.count) label=\(displayed) ink=\(ink)")
        if candidate == longCandidate, style == .replace {
          let markedLayers = textLayers().filter {
            let value = ($0.string as? NSAttributedString)?.string
            return value == "中" || value == "文"
          }
          XCTAssertEqual(markedLayers.count, candidate.count,
            "Every marked character must own an actual Choo text layer")
          XCTAssertGreaterThan(Set(markedLayers.map { $0.position.y }).count, 1,
            "The long candidate must actually exercise cross-row Choo layout")
        }
        let candidateRows = descendants(host, NSTextField.self).filter {
          $0.accessibilityLabel()?.hasPrefix("正在组合：") == true
        }
        XCTAssertEqual(candidateRows.count, style == .below ? 1 : 0)
        if style == .below {
          XCTAssertEqual(candidateRows.first?.stringValue, candidate)
        }
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(host.frame, frame)
      }
      input.unmarkText()
      flush()
      XCTAssertFalse(input.hasMarkedText())
      XCTAssertEqual(owner.accessibilityLabel(), prompt,
        "Cancellation must restore the complete unconsumed target")
      XCTAssertEqual(allocations(), initialAllocations,
        "Cancellation must restore layer allocations independently of animated rotation")
    }
    settings.compositionDisplayStyle = .replace
    flush()
    input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    input.insertText("q", replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertFalse(input.hasMarkedText())
    input.setMarkedText("候", selectedRange: .init(location: 1, length: 0),
      replacementRange: .init(location: NSNotFound, length: 0))
    flush()
    XCTAssertTrue(owner.accessibilityLabel()?.hasPrefix("q候") == true,
      "After confirmation the next candidate must start after exactly one accepted target")
    XCTAssertTrue(descendants(host, ChooLayerView.self).first === owner)
    XCTAssertTrue(descendants(host, TypingInputView.self).first === input)
    input.unmarkText()
    flush()
    XCTAssertEqual(owner.accessibilityLabel(), prompt)
    XCTAssertFalse(window.isVisible)
  }
}
