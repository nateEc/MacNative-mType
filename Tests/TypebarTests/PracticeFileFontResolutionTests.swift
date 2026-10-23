import AppKit
import CoreText
import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class PracticeFileFontResolutionTests: XCTestCase {
  func testActualPracticeFontPathKeepsTheSelectedFileWithACollidingPostScriptName() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-file-font-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appendingPathComponent("first.ttf"), second = root.appendingPathComponent("selected.otf")
    defer {
      for url in [first, second] { _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
      try? FileManager.default.removeItem(at: root)
    }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    try OwnedTestFontFixture.make(postScriptName: name).write(to: first)
    try OwnedTestFontFixture.makeOTF(postScriptName: name).write(to: second)
    XCTAssertTrue(CTFontManagerRegisterFontsForURL(first as CFURL, .process, nil))
    _ = CTFontManagerRegisterFontsForURL(second as CFURL, .process, nil)
    for size: CGFloat in [8, 28, 72] {
      let selected = try XCTUnwrap(LocalPracticeFontRegistration.font(at: second, size: size))
      let resolver = NativePracticeFont.Resolver(localFont: { requestedSize in
        XCTAssertEqual(requestedSize, size)
        return selected
      },
        installedFontName: { _ in XCTFail("The active file takes priority"); return nil })
      let actual = PracticeFont.monospaced.nsFont(size: size, installedFontName: "Courier", resolver: resolver)
      let source = CTFontCopyAttribute(actual as CTFont, kCTFontURLAttribute) as? URL
      XCTAssertEqual(source?.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
      XCTAssertEqual(actual.pointSize, size)
      XCTAssertTrue(actual === selected)
    }
  }

  @MainActor private final class Model {
    let settings: AppSettings
    let session: TypingSession
    var selectedURL: URL
    var ready: [PromptViewportPresentationReady] = []
    init(settings: AppSettings, url: URL) {
      self.settings = settings; selectedURL = url
      var session = TypingSession(configuration: .words(40).with(modifiers: [.noQuit]),
        prompt: Array(repeating: "xxx", count: 40).joined(separator: " "))
      session.insertBatch("x", at: Date(timeIntervalSince1970: 3000))
      self.session = session
    }
    var font: NSFont {
      _ = settings.localPracticeFontRevision
      return settings.practiceFont.nsFont(size: 28, installedFontName: settings.installedPracticeFontName,
        resolver: .init(localFont: { LocalPracticeFontRegistration.font(at: self.selectedURL, size: $0) }))
    }
  }

  private struct Root: View {
    let model: Model
    var body: some View {
      let font = model.font
      ScrollView {
        PromptViewportPracticePrompt(session: model.session,
        style: .init(theme: model.settings.resolvedTheme(for: .light), fontSize: 28), font: font,
        carets: .init(text: AttributedString(model.session.prompt), mainOffset: nil, paceOffset: nil,
          mainStyle: .off, paceStyle: .off, font: font, lineSpacing: 12, rightToLeft: false,
          accent: .blue, motion: .off, reducesMotion: true, frameRate: 60,
          attemptID: model.session.automaticInputAttemptID, coordinator: .init()),
        onFailure: { _ in XCTFail("The file-font viewport must remain renderable") },
        onReady: { model.ready.append($0) })
          .frame(width: 220)
      }.frame(width: 220, height: 400)
    }
  }

  func testFileRevisionReflowsMountedViewportWithoutConfigEventOrAttemptRestart() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-practice-file-reflow-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let first = root.appendingPathComponent("first.ttf"), second = root.appendingPathComponent("wide.ttf")
    defer {
      for url in [first, second] { _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
      try? FileManager.default.removeItem(at: root)
    }
    let name = "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    try OwnedTestFontFixture.make(postScriptName: name).write(to: first)
    try OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900).write(to: second)
    let original = try XCTUnwrap(LocalPracticeFontRegistration.font(at: first, size: 28))
    let selected = try XCTUnwrap(LocalPracticeFontRegistration.font(at: second, size: 28))
    XCTAssertEqual(original.fontName, selected.fontName)
    XCTAssertNotEqual(original, selected, "File identity must participate in the existing layout metric comparison")
    var character: UniChar = 120, glyph: CGGlyph = 0
    XCTAssertTrue(CTFontGetGlyphsForCharacters(selected as CTFont, &character, &glyph, 1))
    var advance = CGSize.zero
    CTFontGetAdvancesForGlyphs(selected as CTFont, .horizontal, &glyph, &advance, 1)
    XCTAssertEqual(advance.width, 28 * 0.9, accuracy: 0.01)

    let suite = "typebar.practice-file-reflow.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
    settings.installedPracticeFontName = "Courier"
    let owner = UUID()
    settings.setNoQuitConfigurationLock(true, for: owner)
    defer { settings.setNoQuitConfigurationLock(false, for: owner) }
    let before = settings.snapshot, epoch = settings.practiceFontApplicationRevision
    let wrapper = settings.practiceWrapperRevision
    let persisted = defaults.data(forKey: "appSettings.v1")
    let model = Model(settings: settings, url: first)
    let attempt = model.session.automaticInputAttemptID, target = model.session.promptTargetID
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 220, height: 400),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: Root(model: model)); window.contentView = host
    defer { window.contentView = nil; window.close() }
    @MainActor func waitUntil(_ condition: () -> Bool) {
      let deadline = Date().addingTimeInterval(10)
      while !condition(), Date() < deadline {
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      }
      XCTAssertTrue(condition())
    }
    waitUntil { model.ready.last?.font == original }
    let height = try XCTUnwrap(model.ready.last?.height)
    try settings.importLocalPracticeFont(data: Data([1]), originalFilename: "owned.ttf",
      save: { _, _ in model.selectedURL = second })
    waitUntil { model.ready.last?.font == selected && (model.ready.last?.height ?? 0) > height }
    let published = try XCTUnwrap(model.ready.last)
    XCTAssertEqual((CTFontCopyAttribute(published.font as CTFont, kCTFontURLAttribute) as? URL)?.resolvingSymlinksInPath(), second.resolvingSymlinksInPath())
    XCTAssertGreaterThan(published.height, height)
    XCTAssertEqual(published.attemptID, attempt)
    XCTAssertEqual(published.targetID, target)
    XCTAssertEqual(model.session.typed, "x")
    XCTAssertEqual(settings.snapshot, before)
    XCTAssertEqual(settings.practiceFontApplicationRevision, epoch)
    XCTAssertEqual(settings.practiceWrapperRevision, wrapper)
    XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), persisted)
    XCTAssertFalse(settings.allowsRestartingConfigurationChange)
  }

  func testMissingSelectedFileFallsBackOnlyToTheConfiguredFamily() throws {
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-missing-selected-\(UUID()).ttf")
    var localRequests: [CGFloat] = [], installedRequests: [String] = []
    let resolver = NativePracticeFont.Resolver(localFont: { size in
      localRequests.append(size)
      return LocalPracticeFontRegistration.font(at: missing, size: size)
    }, installedFontName: { name in
      installedRequests.append(name)
      return NSFont(name: name, size: 28)?.fontName
    })
    let actual = PracticeFont.monospaced.nsFont(size: 28, installedFontName: "Courier", resolver: resolver)
    XCTAssertEqual(actual.fontName, NSFont(name: "Courier", size: 28)?.fontName)
    XCTAssertEqual(localRequests, [28])
    XCTAssertEqual(installedRequests, ["Courier"])
    let preview = try XCTUnwrap(resolver.font(for: "Georgia", size: 15, purpose: .catalogPreview))
    XCTAssertEqual(preview.fontName, NSFont(name: "Georgia", size: 15)?.fontName)
    XCTAssertEqual(localRequests, [28], "Preview must not inspect even a missing local file")
    XCTAssertEqual(installedRequests, ["Courier", "Georgia"])
  }
}
