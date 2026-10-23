import XCTest
@testable import Typebar

final class PolyglotSpeechTests: XCTestCase {
  func testPolyglotSelectionRetainsListeningThroughEffectiveConfiguration() {
    let selected = TestModifierPolicy.modifiersCompatibleWithPolyglot([.listening, .rot13])
    XCTAssertEqual(Set(selected), Set([.listening, .rot13]))
    let effective = EffectiveTestModifierPolicy.modifiers(requested: selected,
      language: .mixedLanguages, mode: .words, mixedLanguageComponents: [.english, .german],
      automaticallyEnabledArabic: false)
    XCTAssertEqual(Set(effective), Set([.listening, .rot13]))
    let configuration = TestConfiguration.words(3, language: .mixedLanguages,
      mixedLanguageComponents: [.english, .german], polyglotBaseLanguage: .german)
      .with(modifiers: effective)
    var session = TestSessionFactory.make(configuration: configuration)
    XCTAssertEqual(Set(session.configuration.modifiers), Set([.listening, .rot13]))
    session.insert(session.prompt, at: Date(timeIntervalSinceReferenceDate: 920_400_000))
    XCTAssertTrue(session.isFinished)
    XCTAssertEqual(session.completedWordCount, 3)
    XCTAssertEqual(TestModifierPolicy.modifiersCompatibleWithPolyglot(
      [.binaryStream, .zipf, .weakSpot, .listening]), [.listening])
  }

  func testEveryPromptReadingCallUsesResolvedSessionPrimaryLanguage() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    let calls = app.components(separatedBy: .newlines).filter { $0.contains("NativeSpeech.shared.speak(") }
    XCTAssertEqual(calls.count, 5)
    for call in calls {
      XCTAssertTrue(call.contains("language: session.configuration.wordPoolBaseLanguage"), call)
    }
  }

  func testResolvedPrimaryFollowsDirectionCorrectionAndSurvivesRoundTrip() throws {
    for (base, components, expected) in [
      (TypingLanguage.german, [TypingLanguage.english, .french], TypingLanguage.german),
      (.english, [.arabic, .hebrew], .arabic),
      (.arabic, [.german, .english], .german),
    ] {
      let requested = TestConfiguration.words(3, language: .mixedLanguages,
        mixedLanguageComponents: components, polyglotBaseLanguage: base).with(modifiers: [.listening])
      let session = TestSessionFactory.make(configuration: requested)
      XCTAssertEqual(session.configuration.wordPoolBaseLanguage, expected)
      let restored = try JSONDecoder().decode(TestConfiguration.self,
        from: JSONEncoder().encode(session.configuration))
      XCTAssertEqual(restored.wordPoolBaseLanguage, expected)
      XCTAssertTrue(restored.modifiers.contains(.listening))
    }
    XCTAssertEqual(TestConfiguration.words(3, language: .mixedLanguages).wordPoolBaseLanguage, .english)
    XCTAssertEqual(TestConfiguration.words(3, language: .french).wordPoolBaseLanguage, .french)
  }

  func testPinnedTTSUsesPrimaryNotPolyglotComponents() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    struct Row: Decodable { var language: String; var locale: String; var text: String }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules",
      root.appendingPathComponent("Scripts/check-source-polyglot-speech.mjs").path, reference]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let rows = try JSONDecoder().decode([Row].self, from: data)
    XCTAssertEqual(rows.count, 7)
    for row in rows {
      let base = try XCTUnwrap(row.language == "code_python" ? .codePython : TypingLanguage(rawValue: row.language))
      let configuration = TestConfiguration.words(3, language: .mixedLanguages,
        mixedLanguageComponents: [.english, .german], polyglotBaseLanguage: base)
      XCTAssertEqual(configuration.wordPoolBaseLanguage.speechLocaleIdentifier, row.locale, row.language)
      XCTAssertFalse(row.text.isEmpty)
    }
  }
}
