import AppKit
import CoreText
import Foundation
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigFontResourceTests: XCTestCase {
  private func typography(family: String = "Courier", size: Double = 28) throws -> WebsiteConfigNativeKeyboardTypography {
    var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    runtime["fontFamily"] = .string(family)
    runtime["fontSize"] = .number(size / 16)
    return try .init(runtime: runtime, pointsPerRem: 16)
  }
  private func advance(_ font: NSFont) throws -> Double {
    var character: UniChar = 120, glyph: CGGlyph = 0
    XCTAssertTrue(CTFontGetGlyphsForCharacters(font as CTFont, &character, &glyph, 1))
    var value = CGSize.zero
    CTFontGetAdvancesForGlyphs(font as CTFont, .horizontal, &glyph, &value, 1)
    return value.width
  }
  private func uniqueName() -> String { "TypebarQA" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
  private func registered(_ name: String) -> Bool {
    (CTFontManagerCopyAvailablePostScriptNames() as? [String])?.contains(name) == true
  }

  func testOwnTTFProducesActualMetricsWithoutGlobalRegistration() throws {
    let name = uniqueName(), data = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900)
    XCTAssertFalse(registered(name))
    let resource = try WebsiteConfigFontResource.prepare(typography: typography(), language: .english, local: .data(data))
    XCTAssertEqual(resource.primary.candidate, .local)
    XCTAssertEqual(resource.primary.font.fontName, name)
    XCTAssertEqual(resource.primary.font.pointSize, 28)
    XCTAssertEqual(try advance(resource.primary.font), 25.2, accuracy: 0.001)
    XCTAssertEqual(resource.ownedLocalData, data)
    XCTAssertNil(resource.localFailure)
    XCTAssertFalse(registered(name), "A prepared face must not enter global name matching")
  }

  func testSameNameDataFontsKeepDifferentAdvancesAcrossSizesAndOwnedBytes() throws {
    let name = uniqueName()
    let original = OwnedTestFontFixture.make(postScriptName: name)
    let wide = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900)
    let storage = NSMutableData(data: wide)
    var retained: [WebsiteConfigFontResource] = []
    for size in [8.0, 15, 28, 72, 144] {
      let first = try WebsiteConfigFontResource.prepare(typography: typography(size: size), language: .lao, local: .data(original))
      let second = try WebsiteConfigFontResource.prepare(typography: typography(size: size), language: .lao,
        local: .data(Data(referencing: storage)))
      XCTAssertEqual(first.primary.font.fontName, name)
      XCTAssertEqual(second.primary.font.fontName, name)
      XCTAssertEqual(try advance(first.primary.font), size * 0.6, accuracy: 0.001)
      XCTAssertEqual(try advance(second.primary.font), size * 0.9, accuracy: 0.001)
      retained.append(second)
    }
    storage.length = 0
    for item in retained {
      XCTAssertEqual(item.ownedLocalData, wide)
      XCTAssertEqual(try advance(item.primary.font), item.primary.font.pointSize * 0.9, accuracy: 0.001)
    }
    XCTAssertFalse(registered(name))
  }

  func testDataFaceDoesNotBorrowOrReplaceAnAlreadyInstalledSameNameFont() throws {
    let visible = try XCTUnwrap(CTFontManagerCopyAvailablePostScriptNames() as? [String])
    let name = try XCTUnwrap(["Menlo-Regular", "ArialMT", "Georgia"].first(where: visible.contains))
    let settings = try typography(family: name)
    let installed = try WebsiteConfigFontResource.prepare(typography: settings, language: .english, local: .absent)
    XCTAssertEqual(installed.primary.candidate, .family(name))
    XCTAssertEqual(installed.primary.font.fontName, name)
    let originalAdvance = try advance(installed.primary.font)
    XCTAssertTrue(registered(name))
    let own = OwnedTestFontFixture.make(postScriptName: name, advanceWidth: 900)
    let prepared = try WebsiteConfigFontResource.prepare(typography: settings, language: .english, local: .data(own))
    XCTAssertEqual(prepared.primary.candidate, .local)
    XCTAssertEqual(prepared.primary.font.fontName, name)
    XCTAssertEqual(try advance(prepared.primary.font), 25.2, accuracy: 0.001,
      "A matching PostScript name is not evidence that the data face was used")
    let global = try WebsiteConfigFontResource.prepare(typography: settings, language: .english, local: .absent)
    XCTAssertEqual(try advance(global.primary.font), originalAdvance, accuracy: 0.001,
      "The owned face must not replace name matching for the installed font")
    XCTAssertEqual(try advance(prepared.primary.font), 25.2, accuracy: 0.001)
  }

  func testOriginalOTFAndBothWebFontContainersResolveWithoutRegistration() throws {
    for format in ["otf", "woff", "woff-zlib", "woff2-cff", "woff2-ttf"] {
      let name = uniqueName()
      let data: Data
      switch format {
      case "otf": data = OwnedTestFontFixture.makeOTF(postScriptName: name)
      case "woff": data = OwnedTestFontFixture.makeWOFF(postScriptName: name)
      case "woff-zlib": data = OwnedTestFontFixture.makeWOFF(postScriptName: name, compressed: true)
      case "woff2-cff": data = OwnedTestFontFixture.makeWOFF2(postScriptName: name)
      default: data = OwnedTestFontFixture.makeWOFF2(postScriptName: name, cff: false)
      }
      let resource = try WebsiteConfigFontResource.prepare(typography: typography(), language: .english, local: .data(data))
      XCTAssertEqual(resource.primary.candidate, .local, format)
      XCTAssertEqual(resource.primary.font.fontName, name, format)
      XCTAssertEqual(try advance(resource.primary.font), 16.8, accuracy: 0.001, format)
      XCTAssertNil(resource.localFailure, format)
      XCTAssertFalse(registered(name), format)
    }
  }

  func testLocalFailureSkipsConfiguredFaceAndRetainsLanguageFallbackIntent() throws {
    let settings = try typography()
    let absent = try WebsiteConfigFontResource.prepare(typography: settings, language: .lao, local: .absent)
    XCTAssertEqual(absent.primary.candidate, .family("Courier"))
    XCTAssertNil(absent.localFailure)
    for bytes in [Data(), Data("not a font".utf8)] {
      let failed = try WebsiteConfigFontResource.prepare(typography: settings, language: .lao, local: .data(bytes))
      XCTAssertEqual(failed.localFailure, .undecodable)
      XCTAssertEqual(failed.candidates, [.local, .family("Noto_Sans_Lao"), .family("Roboto_Mono"), .family("Vazirharf"), .monospace])
      XCTAssertFalse(failed.faces.contains { $0.candidate == .family("Courier") },
        "An invalid LOCALCUSTOM does not put the configured family back into source CSS")
      XCTAssertNil(failed.ownedLocalData)
      XCTAssertEqual(failed.faces.last?.candidate, .monospace)
    }
  }

  func testByteBudgetAndMissingFamilyAreExplicitNotFakeNameMatches() throws {
    let missing = "TypebarMissing" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20)
    let settings = try typography(family: missing)
    let absent = try WebsiteConfigFontResource.prepare(typography: settings, language: .english, local: .absent)
    XCTAssertFalse(absent.faces.contains { $0.candidate == .family(missing) })
    XCTAssertNil(absent.localFailure)
    XCTAssertEqual(absent.faces.last?.candidate, .monospace)
    let bytes = OwnedTestFontFixture.make(postScriptName: uniqueName())
    let refused = try WebsiteConfigFontResource.prepare(typography: settings, language: .english,
      local: .data(bytes), maximumBytes: bytes.count - 1)
    XCTAssertEqual(refused.localFailure, .resourceLimit)
    XCTAssertNil(refused.ownedLocalData)
    let accepted = try WebsiteConfigFontResource.prepare(typography: settings, language: .english,
      local: .data(bytes), maximumBytes: bytes.count)
    XCTAssertEqual(accepted.primary.candidate, .local)
    XCTAssertThrowsError(try WebsiteConfigFontResource.prepare(typography: settings, language: .english,
      local: .absent, maximumBytes: 0)) {
      XCTAssertEqual($0 as? WebsiteConfigFontResourceError, .invalidLimit)
    }
  }

  func testFallbackOrderKeepsDuplicatesAndBothPreferredLanguageFacts() {
    XCTAssertEqual(WebsiteConfigFontResource.candidates(family: "Roboto_Mono", language: .english, hasLocal: false),
      [.family("Roboto_Mono"), .family("Roboto_Mono"), .family("Vazirharf"), .monospace])
    XCTAssertEqual(WebsiteConfigFontResource.candidates(family: "Courier", language: .sindhi, hasLocal: true),
      [.local, .family("Noto_Naskh_Arabic"), .family("Roboto_Mono"), .family("Vazirharf"), .monospace])
  }

  func testFontAndBackgroundPublishTogetherWithoutSerializingFontData() throws {
    try withCoordinator { coordinator, register, _, owner in
      let data = OwnedTestFontFixture.make(postScriptName: uniqueName(), advanceWidth: 900)
      let configuration = try coordinator.prepare(#"{"fontFamily":"Courier","fontSize":1.75,"time":41}"#)
      let resources = try coordinator.prepareResources(for: configuration, localFont: .data(data), localBackground: .empty)
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(try register.read().state, .missing)
      guard case .committed(let published) = try coordinator.commit(resources) else { return XCTFail("No joint publication") }
      let font = try XCTUnwrap(published.font)
      XCTAssertEqual(font.primary.candidate, .local)
      XCTAssertEqual(try advance(font.primary.font), 25.2, accuracy: 0.001)
      guard case .some(.none) = published.background?.state else { return XCTFail("Explicit empty background lost") }
      XCTAssertEqual(try register.read().state, .available(published.draft.projection.runtime))
      XCTAssertEqual(published.draft.projection.runtime["fontFamily"], .string("Courier"))
      let next = try coordinator.prepare(#"{"fontFamily":"Courier","time":43}"#)
      let failed = try coordinator.prepareResources(for: next, localFont: .data(Data()), localBackground: .empty)
      guard case .committed(let failure) = try coordinator.commit(failed) else { return XCTFail("Font failure erased intent") }
      XCTAssertEqual(failure.font?.localFailure, .undecodable)
      XCTAssertEqual(failure.draft.projection.runtime["fontFamily"], .string("Courier"))
      XCTAssertFalse(try XCTUnwrap(failure.font).faces.contains { $0.candidate == .family("Courier") })
    }
  }

  func testBackgroundOnlyAndJointAttemptsShareLatestResourceIntent() throws {
    try withCoordinator { coordinator, register, _, owner in
      let configuration = try coordinator.prepare(#"{"time":41}"#)
      let first = try coordinator.prepareResources(for: configuration, localFont: .absent, localBackground: .empty)
      let imageOnly = try coordinator.prepareBackground(for: configuration, local: .empty)
      guard case .stale = try coordinator.commit(first) else { return XCTFail("Old joint result survived new background") }
      XCTAssertFalse(coordinator.cancel(first))
      let newer = try coordinator.prepareResources(for: configuration, localFont: .absent, localBackground: .empty)
      XCTAssertFalse(coordinator.cancel(imageOnly))
      XCTAssertThrowsError(try coordinator.prepareResources(for: configuration, localFont: .absent,
        localBackground: .empty, maximumFontBytes: 0)) {
        XCTAssertEqual($0 as? WebsiteConfigFontResourceError, .invalidLimit)
      }
      guard case .stale = try coordinator.commit(newer) else { return XCTFail("Failed latest attempt kept old joint ticket") }
      XCTAssertEqual(try register.read().state, .missing)
      let cancelled = try coordinator.prepareResources(for: configuration, localFont: .absent, localBackground: .empty)
      XCTAssertTrue(coordinator.cancel(cancelled))
      guard case .stale = try coordinator.commit(cancelled) else { return XCTFail("Cancelled joint result committed") }
      XCTAssertNil(coordinator.publication(for: owner))
    }
  }

  func testJointResourceTicketsStillRequireOwnerAndDiskRevision() throws {
    try withCoordinator { coordinator, register, router, owner in
      let first = try coordinator.prepare(#"{"time":41}"#)
      let resources = try coordinator.prepareResources(for: first, localFont: .absent, localBackground: .empty)
      let other = UUID()
      router.register(owner: other, save: {})
      router.activate(owner: other)
      router.activate(owner: owner)
      guard case .stale = try coordinator.commit(resources) else { return XCTFail("Owner ABA admitted joint resources") }
      let fresh = try coordinator.prepare(#"{"time":43}"#)
      let freshResources = try coordinator.prepareResources(for: fresh, localFont: .absent, localBackground: .empty)
      let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":45}"#, pointsPerRem: 16, context: .init())
      _ = try register.commit(external, replacing: XCTUnwrap(register.read().revision))
      guard case .conflict = try coordinator.commit(freshResources) else { return XCTFail("Joint resources bypassed CAS") }
      XCTAssertEqual(try register.read().state, .available(external.projection.runtime))
      XCTAssertNil(coordinator.publication(for: owner))
    }
  }

  private func withCoordinator(_ body: (WebsiteConfigCommitCoordinator, WebsiteConfigFileRegister,
    PreferenceConfigurationSaveRouter, UUID) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-font-resource-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
    router.register(owner: owner, save: { XCTFail("No legacy font activation callback") })
    let register = WebsiteConfigFileRegister(directory: directory)
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    try body(coordinator, register, router, owner)
  }
}
