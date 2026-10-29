import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PolishPracticeHostTests: XCTestCase {
  @MainActor private final class Preparation {
    var calls = 0
    var configuration: TestConfiguration?
    var prompt: String?
    var typed = ""
  }

  func testActualPracticePagePreparesTheLargeChoiceAndAcceptsItsFirstWord() async throws {
    for language: TypingLanguage in [.polish2k, .polish5k, .polish10k, .polish20k, .polish40k, .polish200k] {
      try await PracticeHostLifetime.withModelContainer { container, track in
        try await verifyPracticePage(language, container: container, trackCallbacks: track)
      }
    }
  }

  private func verifyPracticePage(_ language: TypingLanguage, container: ModelContainer, trackCallbacks: (AnyObject) -> Void) async throws {
    _ = NSApplication.shared
    let suite = "PolishPracticeHostTests.\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.set("", forKey: "remoteAccount.endpoint.v1")
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.reducePracticeMotion = true
    settings.showAllPracticeLines = true
    // Whole-preview preparation is used only beyond the initial 100-word batch.
    let configuration = TestConfiguration.words(153, language: language)
    XCTAssertTrue(settings.saveActiveTestSelection(.init(preset: .init(configuration: configuration),
      testParameterMemory: .legacyDefaults(configuration: configuration))))
    let preparation = Preparation()
    trackCallbacks(preparation)
    let content = TypebarApp.practiceContent(settings: settings,
      account: AccountSession(defaults: defaults), announcements: RemoteAnnouncementCenter(defaults: defaults),
      hotkey: GlobalHotkeyMonitor(), systemKeyboardGuide: SystemKeyboardGuideMonitor(observesInputSourceChanges: false),
      network: NetworkConnectivityMonitor(), systemAppearance: SystemAppearanceMonitor(),
      wholePreviewPrepare: { configuration, scores, decoration in
        preparation.calls += 1
        preparation.configuration = configuration
        // Observe the production preparation; do not substitute a fixture prompt.
        let session = try await WholePreviewWordPreparation.prepareSession(configuration: configuration,
          weakSpotScores: scores, wordDecorationState: decoration)
        preparation.prompt = session.prompt
        return session
      }, promptRender: { session, composition, style in
        preparation.typed = session.typed
        return PromptRenderPlan(session: session, composition: composition, style: style).render()
      }, wholePreviewViewportEnabled: false).modelContainer(container)
    let host = NSHostingView(rootView: AnyView(content.frame(width: 1000, height: 720)))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
      (view as? T).map { [$0] } ?? view.subviews.flatMap { views(type, in: $0) }
    }
    func waitUntil(_ condition: () -> Bool) async {
      let deadline = Date().addingTimeInterval(15)
      repeat {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(20))
      } while !condition() && Date() < deadline
      XCTAssertTrue(condition())
    }
    await waitUntil {
      guard let prompt = preparation.prompt else { return false }
      return views(PromptFieldNativeView.self, in: host).contains { $0.accessibilityValue() as? String == prompt }
        && views(TypingInputView.self, in: host).first?.acceptsTextInput == true
    }
    XCTAssertEqual(preparation.configuration?.language, language)
    let prompt = try XCTUnwrap(preparation.prompt)
    let words = prompt.split(separator: " ")
    XCTAssertEqual(words.count, 153)
    let owned = Set(language.ownedPracticeWords().map { word in
      word.utf8.contains { (65...90).contains($0) } ? word.lowercased() : word
    })
    XCTAssertTrue(words.allSatisfy { owned.contains(String($0)) })
    let input = try XCTUnwrap(views(TypingInputView.self, in: host).first)
    let first = try XCTUnwrap(words.first)
    input.insertText(String(first) + " ", replacementRange: NSRange(location: NSNotFound, length: 0))
    await waitUntil { preparation.typed == String(first) + " " }
    XCTAssertTrue(views(TypingInputView.self, in: host).first === input)
    XCTAssertEqual(preparation.calls, 1)
    XCTAssertFalse(window.isVisible)
    XCTAssertNil(window.attachedSheet)
  }
}
