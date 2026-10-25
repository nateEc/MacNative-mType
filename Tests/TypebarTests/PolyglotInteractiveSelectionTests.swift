import XCTest
@testable import Typebar

final class PolyglotInteractiveSelectionTests: XCTestCase {
  func testPolyglotModeAdmissionIsBidirectionalAndDoesNotRestrictOrdinaryLanguages() {
    for mode in TestMode.allCases {
      let allowed = mode == .time || mode == .words
      XCTAssertEqual(TestModifierPolicy.acceptsPolyglotAddition(to: [.rot13], mode: mode), allowed)
      XCTAssertEqual(TestModifierPolicy.acceptsModeSelection(mode, modifiers: [.rot13],
        language: .mixedLanguages), allowed)
      XCTAssertTrue(TestModifierPolicy.acceptsModeSelection(mode, modifiers: [], language: .german))
    }
    XCTAssertFalse(TestModifierPolicy.acceptsPolyglotAddition(to: [.memory], mode: .time))
    XCTAssertTrue(TestModifierPolicy.acceptsPolyglotAddition(to: [.memory], mode: .words))
  }

  func testModeEntrypointsIncludeTheActivePolyglotContext() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("acceptsModeSelection(requested, modifiers: practiceRequestedModifiers, language: language)"))
    XCTAssertTrue(app.contains("acceptsModeSelection(mode, modifiers: modifiers, language: language)"))
    XCTAssertEqual(app.components(separatedBy:
      "acceptsPolyglotAddition(to: practiceRequestedModifiers, mode: mode)").count - 1, 2)
  }

  func testAdditionRejectsPolyglotConflictsInEitherOrderButAllowsRemoval() {
    for modifier: TestModifier in [.binaryStream, .accountingStream, .asciiStream, .symbolStream,
      .zipf, .weakSpot, .referenceStream, .pseudolangStream] {
      XCTAssertFalse(TestModifierPolicy.acceptsPolyglotAddition(to: [.rot13, modifier]))
      XCTAssertNil(FunboxCommandPolicy.updatedModifiers(for: .modifier(modifier), current: [.rot13],
        hasStarted: false, language: .mixedLanguages))
      XCTAssertEqual(InteractiveFunboxSelectionPolicy.updatedModifiers(toggling: modifier,
        current: [.rot13, modifier], language: .mixedLanguages), [.rot13])
    }
    for modifier: TestModifier in [.listening, .uppercase, .morseStream, .mirrorVisual, .noQuit, .lazyLatin] {
      XCTAssertTrue(TestModifierPolicy.acceptsPolyglotAddition(to: [.rot13, modifier]))
      XCTAssertEqual(FunboxCommandPolicy.updatedModifiers(for: .modifier(modifier), current: [.rot13],
        hasStarted: false, language: .mixedLanguages), [.rot13, modifier])
    }
    XCTAssertNil(FunboxCommandPolicy.updatedModifiers(for: .modifier(.noQuit), current: [.noQuit],
      hasStarted: true, language: .mixedLanguages))
    XCTAssertEqual(FunboxCommandPolicy.updatedModifiers(for: .modifier(.binaryStream), current: [.rot13],
      hasStarted: false, language: .english), [.rot13, .binaryStream])
  }

  @MainActor
  func testPreferenceRejectsBeforeWritingAndReadsTheActiveOwnersLiveLanguage() throws {
    let suite = "typebar.polyglot-interactive.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    settings.testModifiers = [.rot13]
    let first = UUID(), second = UUID()
    var language = TypingLanguage.mixedLanguages
    settings.preferenceConfigurationSaves.register(owner: first, selectedLanguage: { .english }) {}
    settings.preferenceConfigurationSaves.register(owner: second, selectedLanguage: { language }) {}
    XCTAssertEqual(settings.preferenceConfigurationSaves.selectedLanguage, .english,
      "Registration must not steal the active owner")
    settings.preferenceConfigurationSaves.activate(owner: second)
    let before = defaults.dictionaryRepresentation() as NSDictionary
    let revision = settings.testModifiersApplicationRevision
    XCTAssertFalse(settings.toggleTestModifier(.binaryStream))
    XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
    XCTAssertEqual(settings.testModifiersApplicationRevision, revision)
    XCTAssertEqual(settings.testModifiers, [.rot13])
    language = .german
    XCTAssertTrue(settings.toggleTestModifier(.binaryStream))
    XCTAssertEqual(Set(settings.testModifiers), Set([.rot13, .binaryStream]))
    language = .mixedLanguages
    XCTAssertTrue(settings.toggleTestModifier(.binaryStream), "Removal from an old invalid set remains possible")
    XCTAssertEqual(settings.testModifiers, [.rot13])
    settings.preferenceConfigurationSaves.remove(owner: second)
    XCTAssertEqual(settings.preferenceConfigurationSaves.selectedLanguage, .english)
    settings.preferenceConfigurationSaves.remove(owner: first)
    XCTAssertNil(settings.preferenceConfigurationSaves.selectedLanguage)
    XCTAssertTrue(settings.toggleTestModifier(.binaryStream), "No owner retains the existing native preference behavior")
  }

  @MainActor
  func testReplacingOrRemovingAnOwnerReleasesItsLanguageProvider() {
    final class Token {}
    let router = PreferenceConfigurationSaveRouter(), owner = UUID()
    var token: Token? = Token()
    weak var weakToken = token
    router.register(owner: owner, selectedLanguage: { [retained = token!] in
      _ = retained
      return .mixedLanguages
    }) {}
    token = nil
    XCTAssertNotNil(weakToken)
    router.register(owner: owner) {}
    XCTAssertNil(weakToken)
    XCTAssertNil(router.selectedLanguage)
    var removed: Token? = Token()
    weak var weakRemoved = removed
    router.register(owner: owner, selectedLanguage: { [retained = removed!] in
      _ = retained
      return .mixedLanguages
    }) {}
    removed = nil
    router.remove(owner: owner)
    XCTAssertNil(weakRemoved)
    XCTAssertNil(router.selectedLanguage)
  }

  func testProductionRoutesLanguageAndRejectsPolyglotBeforeChangingSelection() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let app = try String(contentsOf: root.appendingPathComponent("Sources/Typebar/TypebarApp.swift"), encoding: .utf8)
    XCTAssertTrue(app.contains("selectedLanguage: { committedPracticeDraft?.testParameters.language ?? language }"))
    XCTAssertTrue(app.contains("guard pageSession.practice == nil else {"), "Legacy selection must not edit a complete website practice")
    XCTAssertTrue(app.contains("modifier, to: practiceRequestedModifiers, language: language"))
    XCTAssertTrue(app.contains("hasStarted: session.hasStarted, language: language"))
    let commandStart = try XCTUnwrap(app.range(of: "if let target = FunboxCommandCatalog.target(for: item.id)"))
    let command = String(app[commandStart.lowerBound...])
    let branch = try XCTUnwrap(command.range(of: "case .polyglot:"))
    let mutation = try XCTUnwrap(command.range(of: "activeChallengeID = nil", range: branch.upperBound..<command.endIndex))
    XCTAssertTrue(command[branch.upperBound..<mutation.lowerBound].contains("acceptsPolyglotAddition"))
    let languageStart = try XCTUnwrap(app.range(of: "private func selectLanguage(_ requested: TypingLanguage)"))
    let languageEnd = try XCTUnwrap(app.range(of: "private func acceptsFunboxConfiguration", range: languageStart.upperBound..<app.endIndex))
    let languageBody = String(app[languageStart.lowerBound..<languageEnd.lowerBound])
    XCTAssertTrue(languageBody.contains("acceptsPolyglotAddition"))
    XCTAssertFalse(command[branch.upperBound..<command.index(branch.upperBound, offsetBy: 1000)].contains(
      "settings.testModifiers = TestModifierPolicy.modifiersCompatibleWithPolyglot"))
  }
}
