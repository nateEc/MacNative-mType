import AppKit
import Observation
import XCTest
@testable import Typebar

@MainActor final class WebsiteFontCommandTests: XCTestCase {
  @MainActor private final class Fixture {
    let suite = "typebar.font-command.\(UUID())"
    let defaults: UserDefaults, settings: AppSettings, account: AccountSession, page: PracticePageSessionStore
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let workflow: WebsiteConfigImportWorkflow
    var register: WebsiteConfigFileRegister { .init(directory: directory) }
    init() throws {
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let settings = AppSettings(defaults: defaults, localBackgroundStore: .inMemory())
      let account = AccountSession(defaults: defaults), page = PracticePageSessionStore()
      self.defaults = defaults; self.settings = settings; self.account = account; self.page = page
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      settings.preferenceConfigurationSaves.register(owner: page.owner, save: {})
      page.attach(to: settings.preferenceConfigurationSaves)
      let workflow = WebsiteConfigImportWorkflow(page: page, settings: settings, account: account,
        directory: directory, readWindow: { .published(owner: page.owner,
          revision: page.state.session.automaticInputAttemptID, scope: page.state.practice?.scope ?? .init()) })
      self.workflow = workflow
      settings.preferenceConfigurationSaves.register(owner: page.owner,
        fontFamilyName: { page.state.presentation?.publication.draft.keyboardTypography.fontFamily ?? settings.installedPracticeFontName },
        fontPointSize: { page.state.presentation?.publication.draft.keyboardTypography.fontSize },
        fontEdit: { edit in
          guard page.ownsConfigurationSelection else { return nil }
          guard let id = page.state.presentation?.publication.applicationID else { return false }
          do { try workflow.runFontCommand(edit, replacing: id); return true } catch { return false }
        }, save: {})
    }
    func publish(noQuit: Bool = false) async throws {
      try await workflow.apply(json: noQuit
        ? #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2,"funbox":["no_quit"]}"#
        : #"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2}"#, systemIsDark: false)
    }
    func close() {
      workflow.stop(); page.detach(); settings.preferenceConfigurationSaves.remove(owner: page.owner)
      defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory)
    }
  }

  func testCurrentFontControlDoesNotPretendToUpdateThePublishedFont() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let before = f.settings.snapshot, generation = f.page.state.session.generationState
    XCTAssertTrue(FontFamilyCommandApplication.apply(.systemDesign(.serif), to: f.settings))
    XCTAssertEqual(f.settings.snapshot, before, "A website-owned control must not mutate the native fallback")
    XCTAssertEqual(f.page.state.presentation?.publication.draft.keyboardTypography.fontFamily,
      NativeSystemPracticeFont.identifier(for: .serif))
    XCTAssertEqual(f.page.state.presentation?.publication.font?.primary.font.fontName,
      PracticeFont.serif.nsFont(size: 32, resolver: .init(localFont: { _ in nil })).fontName)
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.settings.preferenceFontFamilyName, NativeSystemPracticeFont.identifier(for: .serif))
    XCTAssertEqual(PracticeFontPreferences(settings: f.settings).design.wrappedValue, .serif)
    XCTAssertEqual(PracticeFontPreferences(settings: f.settings).familyName, "", "System design identifiers are not unavailable installed families")
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Missing saved font") }
    XCTAssertEqual(saved["fontFamily"], .string(NativeSystemPracticeFont.identifier(for: .serif)))
  }

  func testFractionalSizeDuringNoQuitKeepsInputAttemptControllerThemeAndOtherFields() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish(noQuit: true)
    var active = f.page.state; active.session.insertBatch(String(active.session.nextExpectedCharacter!)); f.page.replace(active)
    let generation = f.page.state.session.generationState, ledger = f.page.state.priorAttemptLedger
    let original = try XCTUnwrap(f.page.state.presentation), controller = f.page.restartController
    let preferences = f.settings.snapshot
    var accepted: [Bool] = []
    let binding = PracticeFontPreferences(settings: f.settings, onResult: { accepted.append($0) })
    binding.size.wrappedValue = 37.5
    XCTAssertEqual(accepted, [true]); XCTAssertEqual(binding.size.wrappedValue, 37.5)
    let after = try XCTUnwrap(f.page.state.presentation)
    XCTAssertEqual(after.publication.font?.primary.font.pointSize, 37.5)
    XCTAssertEqual(after.appearance, original.appearance)
    for (key, value) in original.publication.draft.projection.runtime where key != "fontSize" {
      XCTAssertEqual(after.publication.draft.projection.runtime[key], value, key)
    }
    XCTAssertEqual(f.page.state.session.generationState, generation)
    XCTAssertEqual(f.page.state.priorAttemptLedger, ledger); XCTAssertTrue(f.page.restartController === controller)
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertEqual(after.publication.draft.projection.events.map(\.key), ["fontSize"])
    guard case .available(let saved) = try f.register.read().state else { return XCTFail("Missing size") }
    XCTAssertEqual(saved["fontSize"], .number(37.5 / 16))
  }

  func testCustomNameKeepsUnavailableFamilyAndPreparedFallbackWithoutChangingNativeName() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let preferences = f.settings.snapshot
    XCTAssertTrue(FontFamilyNameCommandPolicy.apply("  Typebar Absent Font  ", to: f.settings))
    let publication = try XCTUnwrap(f.page.state.presentation?.publication)
    XCTAssertEqual(publication.draft.keyboardTypography.fontFamily, "Typebar_Absent_Font")
    XCTAssertFalse(publication.font?.faces.contains { $0.candidate == .family("Typebar_Absent_Font") } ?? true)
    XCTAssertNotNil(publication.font?.renderingFont)
    XCTAssertEqual(f.settings.snapshot, preferences)
    XCTAssertFalse(FontFamilyCommandApplication.apply(.installedName("not installed"), to: f.settings, isFontAvailable: { _ in false }))
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, publication.applicationID)
  }

  func testInvalidSizeAndForeignDiskDoNotFallBackToNativeWrites() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let id = try XCTUnwrap(f.page.state.presentation?.publication.applicationID)
    let prefs = f.settings.snapshot, disk = try f.register.read()
    let binding = PracticeFontPreferences(settings: f.settings)
    for value in [Double.nan, .infinity, 0, -1] { binding.size.wrappedValue = value }
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertEqual(try f.register.read().revision, disk.revision)
    guard case .available(var foreign) = disk.state else { return XCTFail("Missing saved profile") }
    foreign["words"] = .number(9)
    guard case .committed = try f.register.commit(runtime: foreign, lazyMemory: disk.lazyMemory,
      replacing: XCTUnwrap(disk.revision)) else { return XCTFail("Foreign save failed") }
    let foreignRevision = try f.register.read().revision
    XCTAssertFalse(FontFamilyCommandApplication.apply(.knownIdentifier("Georgia"), to: f.settings))
    XCTAssertEqual(f.page.state.presentation?.publication.applicationID, id)
    XCTAssertEqual(f.settings.snapshot, prefs); XCTAssertEqual(try f.register.read().revision, foreignRevision)
  }

  func testRouterUsesActiveOwnerAndRejectsReentrancyWithoutLegacyFallthrough() throws {
    let f = try Fixture(); defer { f.close() }
    let router = f.settings.preferenceConfigurationSaves, second = UUID()
    var firstCalls = 0, secondCalls = 0
    router.register(owner: f.page.owner, fontEdit: { _ in firstCalls += 1; return true }, save: {})
    router.register(owner: second, fontEdit: { edit in
      secondCalls += 1
      XCTAssertEqual(router.applyFontEdit(edit), false)
      return false
    }, save: {})
    router.activate(owner: second)
    let prefs = f.settings.snapshot
    XCTAssertFalse(FontFamilyCommandApplication.apply(.systemDesign(.serif), to: f.settings))
    XCTAssertEqual(firstCalls, 0); XCTAssertEqual(secondCalls, 1); XCTAssertEqual(f.settings.snapshot, prefs)
    router.remove(owner: second)
    XCTAssertTrue(FontFamilyCommandApplication.apply(.systemDesign(.serif), to: f.settings))
    XCTAssertEqual(firstCalls, 1); XCTAssertEqual(f.settings.snapshot, prefs)
  }

  func testPreparedLocalFaceSurvivesFamilyAndSizeChangesWithoutRegistrationOrRestart() async throws {
    let f = try Fixture(); defer { f.close() }
    let epoch = UUID(), data = OwnedTestFontFixture.make(postScriptName: "TypebarOwnedLiveFont")
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
      register: f.register, environment: { .init(revision: epoch, context: .init(), pointsPerRem: 20) })
    let seed = try coordinator.prepare(#"{"mode":"words","words":5,"fontFamily":"Courier","fontSize":2}"#)
    let resources = try coordinator.prepareResources(for: seed, localFont: .data(data), localBackground: .absent)
    let ready = try await coordinator.preparePractice(for: resources, scope: .init())
    guard case .committed = try coordinator.commit(ready, to: f.page, systemIsDark: false) else { return XCTFail("Seed failed") }
    let generation = f.page.state.session.generationState
    for (key, value) in [("fontFamily", WebsiteConfigValue.string("Georgia")), ("fontSize", .number(1.875))] {
      let edit = try coordinator.prepareEdit(key: key, value: value, for: f.page)
      let font = try coordinator.prepareLiveFont(edit, local: .data(data))
      guard case .committed(let p) = try coordinator.commitLiveFont(font, for: f.page) else { return XCTFail("Font not committed") }
      XCTAssertEqual(p.font?.primary.candidate, .local); XCTAssertEqual(p.font?.ownedLocalData, data)
      XCTAssertEqual(p.font?.primary.font.fontName, "TypebarOwnedLiveFont")
      XCTAssertEqual(p.font?.primary.font.pointSize, key == "fontSize" ? 37.5 : 40)
      XCTAssertEqual(f.page.state.session.generationState, generation)
      guard case .stale = try coordinator.commitLiveFont(font, for: f.page) else { return XCTFail("Consumed resource was replayed") }
    }
    XCTAssertNil(NSFont(name: "TypebarOwnedLiveFont", size: 12))
  }

  func testLiveFontAdmissionRefusesOtherFieldsAndRetiredWindowBeforeSaving() async throws {
    let f = try Fixture(); defer { f.close() }; let epoch = UUID()
    let coordinator = WebsiteConfigCommitCoordinator(router: f.settings.preferenceConfigurationSaves,
      register: f.register, environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    let seed = try coordinator.prepare(#"{"mode":"words","words":5}"#)
    let resources = try coordinator.prepareResources(for: seed, localFont: .absent, localBackground: .absent)
    let ready = try await coordinator.preparePractice(for: resources, scope: .init())
    guard case .committed = try coordinator.commit(ready, to: f.page, systemIsDark: false) else { return XCTFail("Seed failed") }
    let disk = try f.register.read().revision, generation = f.page.state.session.generationState
    let invalid = try coordinator.prepareEdit(key: "words", value: .number(9), for: f.page)
    XCTAssertThrowsError(try coordinator.prepareLiveFont(invalid, local: .absent))
    let edit = try coordinator.prepareEdit(key: "fontFamily", value: .string("Courier"), for: f.page)
    let font = try coordinator.prepareLiveFont(edit, local: .absent)
    let second = UUID(); f.settings.preferenceConfigurationSaves.register(owner: second, save: {})
    f.settings.preferenceConfigurationSaves.activate(owner: second)
    defer { f.settings.preferenceConfigurationSaves.remove(owner: second) }
    guard case .stale = try coordinator.commitLiveFont(font, for: f.page) else { return XCTFail("Retired owner changed font") }
    XCTAssertEqual(try f.register.read().revision, disk)
    XCTAssertEqual(f.page.state.session.generationState, generation)
  }

  func testFontActionDuringOwnerRegistrationDoesNotFallThroughToNativePreferences() throws {
    @MainActor final class Delivery { var results: [Bool] = [] }
    let f = try Fixture(); defer { f.close() }; let delivery = Delivery()
    let router = f.settings.preferenceConfigurationSaves, settings = f.settings
    let preferences = settings.snapshot
    withObservationTracking { _ = router.fontPointSize } onChange: {
      MainActor.assumeIsolated {
        delivery.results.append(FontFamilyCommandApplication.apply(.systemDesign(.serif), to: settings))
      }
    }
    router.register(owner: f.page.owner, fontPointSize: { 32 }, fontEdit: { _ in true }, save: {})
    XCTAssertEqual(delivery.results, [false])
    XCTAssertEqual(settings.snapshot, preferences)
  }

  func testNumericBindingKeepsFractionsOutsideTheConvenienceSliderRange() async throws {
    let f = try Fixture(); defer { f.close() }; try await f.publish()
    let preferences = f.settings.snapshot
    let binding = PracticeFontPreferences(settings: f.settings)
    for size in [1.25, 18.0625, 96.5] {
      binding.size.wrappedValue = size
      XCTAssertEqual(binding.size.wrappedValue, size)
      XCTAssertEqual(f.page.state.presentation?.publication.font?.primary.font.pointSize, CGFloat(size))
      guard case .available(let saved) = try f.register.read().state else { return XCTFail("Missing size") }
      XCTAssertEqual(saved["fontSize"], .number(size / 16))
    }
    XCTAssertEqual(f.settings.snapshot, preferences)
  }

  func testRemovingWindowReleasesFontProviderAndActionAndOrdinaryDeliveryRejectsNestedFontEdits() throws {
    final class Lifetime {}
    let f = try Fixture(); defer { f.close() }; let router = f.settings.preferenceConfigurationSaves
    let preferences = f.settings.snapshot
    var nested: Bool?
    var lifetime: Lifetime? = Lifetime(); weak var retained = lifetime
    router.register(owner: f.page.owner, fontPointSize: { [captured = lifetime!] in
      _ = captured; return 32
    }, fontEdit: { [captured = lifetime!] _ in _ = captured; return true }, save: {
      nested = FontFamilyCommandApplication.apply(.systemDesign(.serif), to: f.settings)
    })
    lifetime = nil; XCTAssertNotNil(retained)
    XCTAssertTrue(router.deliver()); XCTAssertEqual(nested, false)
    XCTAssertEqual(f.settings.snapshot, preferences)
    router.remove(owner: f.page.owner)
    XCTAssertNil(retained); XCTAssertNil(router.fontPointSize)
    XCTAssertNil(router.applyFontEdit(.size(32)))
  }
}
