import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PracticeLanguagePickerTests: XCTestCase {
  private final class SelectionOwner { var selected: [TypingLanguage] = [] }

  func testAllLanguagesRetainOrderedIdentityAndMenuItemsAcrossInputUpdates() throws {
    let view = PracticeLanguagePopUp(frame: .zero, pullsDown: false)
    let languages = TypingLanguage.allCases
    var selected: [TypingLanguage] = []
    view.configure(languages: languages, selection: .english, enabled: true) { selected.append($0) }
    XCTAssertEqual(view.itemArray.map(\.title), languages.map(\.displayName))
    XCTAssertEqual(view.itemArray.compactMap { $0.representedObject as? String }, languages.map(\.rawValue))
    XCTAssertEqual(view.accessibilityLabel(), "语言")
    let items = view.itemArray
    for language in [TypingLanguage.arabic, .bangla, .english] {
      view.configure(languages: languages, selection: language, enabled: true) { selected.append($0) }
      XCTAssertEqual(view.numberOfItems, items.count)
      XCTAssertTrue(zip(items, view.itemArray).allSatisfy { $0 === $1 })
      XCTAssertEqual(view.selectedItem?.representedObject as? String, language.rawValue)
    }
    XCTAssertTrue(selected.isEmpty, "Programmatic updates must not invoke the selection binding")
  }

  func testCurrentBindingDisabledStateAndQuoteOptionsAreHonored() throws {
    _ = NSApplication.shared
    let view = PracticeLanguagePopUp(frame: .zero, pullsDown: false)
    var old: [TypingLanguage] = [], latest: [TypingLanguage] = []
    view.configure(languages: [.english, .arabic], selection: .english, enabled: true) { old.append($0) }
    view.configure(languages: [.english, .arabic], selection: .english, enabled: true) { latest.append($0) }
    view.selectItem(at: 1)
    view.sendAction(try XCTUnwrap(view.action), to: view.target)
    XCTAssertTrue(old.isEmpty)
    XCTAssertEqual(latest, [.arabic])
    view.configure(languages: [.english, .arabic], selection: .arabic, enabled: false) { latest.append($0) }
    view.selectItem(at: 0)
    view.sendAction(try XCTUnwrap(view.action), to: view.target)
    XCTAssertFalse(view.isEnabled)
    XCTAssertEqual(latest, [.arabic], "Disabled hidden configuration must not invoke a binding")
    let quotes = TypingLanguage.allCases.filter(\.supportsQuotes)
    view.configure(languages: quotes, selection: .english, enabled: true) { latest.append($0) }
    XCTAssertEqual(view.itemArray.compactMap { $0.representedObject as? String }, quotes.map(\.rawValue))
    view.configure(languages: [], selection: .english, enabled: true) { latest.append($0) }
    XCTAssertNil(view.selectedItem)
    view.sendAction(try XCTUnwrap(view.action), to: view.target)
    XCTAssertEqual(latest, [.arabic], "Missing options must never select an unrelated fallback")
  }

  func testDetachingControlReleasesItsSelectionOwner() {
    let parent = NSView(), view = PracticeLanguagePopUp(frame: .zero, pullsDown: false)
    parent.addSubview(view)
    weak var retainedOwner: SelectionOwner?
    func configureOwner() {
      let owner = SelectionOwner()
      retainedOwner = owner
      view.configure(languages: [.english], selection: .english, enabled: true) { owner.selected.append($0) }
    }
    configureOwner()
    XCTAssertNotNil(retainedOwner)
    view.removeFromSuperview()
    XCTAssertNil(retainedOwner, "A retired control must not keep a stale practice selection alive")
    XCTAssertNil(view.target)
    XCTAssertNil(view.action)
  }

  func testHostedRejectedSelectionRestoresTheActualBindingAndInheritsDisabledState() throws {
    var requested: [TypingLanguage] = []
    var selected = TypingLanguage.english
    var rejects = true
    func root(disabled: Bool) -> some View {
      PracticeLanguagePicker(languages: [.english, .arabic], selection: .init(
        get: { selected }, set: {
          requested.append($0)
          if !rejects { selected = $0 }
        }))
        .disabled(disabled).frame(width: 600, height: 60)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    let host = NSHostingView(rootView: root(disabled: false))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 60),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func flush() {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.03))
      host.layoutSubtreeIfNeeded()
    }
    func controls(_ view: NSView) -> [PracticeLanguagePopUp] {
      (view as? PracticeLanguagePopUp).map { [$0] } ?? view.subviews.flatMap(controls)
    }
    flush()
    let view = try XCTUnwrap(controls(host).first)
    view.selectItem(at: 1)
    XCTAssertTrue(view.sendAction(try XCTUnwrap(view.action), to: view.target))
    XCTAssertEqual(requested, [.arabic])
    XCTAssertEqual(view.selectedItem?.representedObject as? String, TypingLanguage.english.rawValue,
      "A rejected configuration change must not display an unaccepted language")
    rejects = false
    view.selectItem(at: 1)
    XCTAssertTrue(view.sendAction(try XCTUnwrap(view.action), to: view.target))
    XCTAssertEqual(selected, .arabic)
    XCTAssertEqual(requested, [.arabic, .arabic])
    XCTAssertEqual(view.selectedItem?.representedObject as? String, selected.rawValue)
    flush()
    if let path = ProcessInfo.processInfo.environment["TYPEBAR_LANGUAGE_PICKER_CAPTURE_PATH"] {
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        .write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    host.rootView = root(disabled: true)
    flush()
    XCTAssertTrue(controls(host).contains { $0 === view })
    XCTAssertFalse(view.isEnabled)
    XCTAssertFalse(window.isVisible)
  }
}
