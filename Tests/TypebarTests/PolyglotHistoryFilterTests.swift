import Foundation
import XCTest
@testable import Typebar

final class PolyglotHistoryFilterTests: XCTestCase {
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  private func filter(_ enabled: Bool) throws -> ResultHistoryFilter {
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ResultHistoryFilter())) as? [String: Any])
    object["modifierFilter"] = ["includesNoModifiers": false, "modifiers": [], "includesPolyglot": enabled]
    return try JSONDecoder().decode(ResultHistoryFilter.self, from: JSONSerialization.data(withJSONObject: object))
  }
  func testExplicitSelectionPromotesArchiveAndRejectsDisguisedOldPayloadBeforeTombstones() throws {
    for enabled in [true, false] {
    let preset = NamedResultFilterPreset(id: UUID(), name: "Polyglot", filter: try filter(enabled), createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    let archive = TypebarArchive(version: 4, exportedAt: .now, settings: .init(), results: [], presets: [], resultFilterPresets: [preset])
    XCTAssertEqual(archive.version, 33)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    let bytes = try encoder.encode(archive)
    XCTAssertEqual(try TypebarDataTransfer.importArchive(from: bytes).resultFilterPresets, [preset])
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    root["version"] = 32; root["deletedResultFilterPresetIDs"] = [preset.id.uuidString]
    XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))
    }
  }
  func testExplicitSelectionUsesVersionTwoAccountDocument() throws {
    let document = try AccountFilterPresetDocument(name: "Polyglot", filter: filter(true), scope: scope)
    XCTAssertEqual(document.version, 2)
    XCTAssertEqual(try document.restored(scope: scope, knownTagIDs: nil), try filter(true))
  }

  func testLegacyDefaultsRemainUnchangedUntilAnExplicitEdit() throws {
    for original in [ResultHistoryModifierFilter(), .init(includesNoModifiers: true, modifiers: []),
      .init(includesNoModifiers: false, modifiers: [.memory])] {
      let decoded = try JSONDecoder().decode(ResultHistoryModifierFilter.self, from: JSONEncoder().encode(original))
      XCTAssertEqual(decoded, original)
      XCTAssertNil(decoded.includesPolyglot)
      XCTAssertEqual(decoded.effectiveIncludesPolyglot, original.isUnfiltered)
      let document = try AccountFilterPresetDocument(name: "Legacy", filter: .init(modifierFilter: decoded), scope: scope)
      XCTAssertEqual(document.version, 1)
    }
    var all = ResultHistoryModifierFilter()
    all.setModifiers([])
    XCTAssertTrue(all.effectiveIncludesPolyglot)
    all.setNoModifiersSelected(false)
    XCTAssertTrue(all.matches([], isPolyglot: true))
    XCTAssertFalse(all.matches([], isPolyglot: false))
    XCTAssertEqual(all.selectionSummary, "Polyglot 多语混排")
    var partial = ResultHistoryModifierFilter(includesNoModifiers: false, modifiers: [.memory])
    partial.setNoModifiersSelected(true)
    XCTAssertFalse(partial.effectiveIncludesPolyglot)
  }

  func testUnknownEvidenceNeverBecomesNoModifiersButKnownCompanionCanMatch() {
    let none = ResultHistoryModifierFilter(includesNoModifiers: true, modifiers: [], includesPolyglot: false)
    XCTAssertFalse(none.matches([], isPolyglot: nil))
    XCTAssertFalse(none.matches([], isPolyglot: true))
    XCTAssertTrue(none.matches([], isPolyglot: false))
    let polyglot = ResultHistoryModifierFilter(includesNoModifiers: false, modifiers: [], includesPolyglot: true)
    XCTAssertFalse(polyglot.matches(nil, isPolyglot: nil))
    XCTAssertTrue(polyglot.matches(nil, isPolyglot: true))
    let companion = ResultHistoryModifierFilter(includesNoModifiers: false, modifiers: [.memory], includesPolyglot: false)
    XCTAssertTrue(companion.matches([.memory], isPolyglot: nil))
    XCTAssertTrue(ResultHistoryModifierFilter().matches(nil, isPolyglot: nil))
    var withoutPolyglot = ResultHistoryModifierFilter(); withoutPolyglot.includesPolyglot = false
    XCTAssertFalse(withoutPolyglot.isUnfiltered)
    XCTAssertFalse(withoutPolyglot.matches([], isPolyglot: true))
  }

  func testCurrentSettingsAndNativeEntryKeepPolyglotSeparateFromLanguageFiltering() {
    var config = TestConfiguration.timed(seconds: 15); config.language = .mixedLanguages
    let filter = ResultHistoryFilter.currentSettings(config)
    XCTAssertTrue(filter.modifierFilter.effectiveIncludesPolyglot)
    XCTAssertFalse(filter.modifierFilter.includesNoModifiers)
    let id = UUID(), other = UUID()
    let entries = [ResultHistoryEntry(id: id, mode: .time, language: .mixedLanguages, tags: [],
      difficulty: .normal, includesPunctuation: false, includesNumbers: false, duration: 15,
      modifiers: [], isPolyglot: true),
      ResultHistoryEntry(id: other, mode: .time, language: .mixedLanguages, tags: [],
      difficulty: .normal, includesPunctuation: false, includesNumbers: false, duration: 15,
      modifiers: [], isPolyglot: nil)]
    XCTAssertEqual(filter.matchingIDs(entries: entries, personalBestIDs: []), [id])
    XCTAssertFalse(ResultHistoryFilter.currentSettings(.timed(seconds: 15)).modifierFilter.effectiveIncludesPolyglot)
  }

  func testExplicitNullNumbersAndMismatchedAccountVersionsFailClosed() throws {
    let document = try AccountFilterPresetDocument(name: "Polyglot", filter: filter(false), scope: scope)
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    let original = try XCTUnwrap(JSONSerialization.jsonObject(with: document.filterData) as? [String: Any])
    for value: Any in [NSNull(), 1, "true"] {
      var object = original
      var modifiers = try XCTUnwrap(object["modifierFilter"] as? [String: Any]); modifiers["includesPolyglot"] = value
      object["modifierFilter"] = modifiers
      let bytes = try JSONSerialization.data(withJSONObject: object)
      XCTAssertThrowsError(try JSONDecoder().decode(ResultHistoryFilter.self, from: bytes))
      wire["filterData"] = bytes.base64EncodedString()
      XCTAssertThrowsError(try JSONDecoder().decode(AccountFilterPresetDocument.self, from: JSONSerialization.data(withJSONObject: wire)))
    }
    wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    wire["version"] = 1
    XCTAssertThrowsError(try JSONDecoder().decode(AccountFilterPresetDocument.self, from: JSONSerialization.data(withJSONObject: wire)))
  }

  func testCapabilityRequiresExactServiceAndBothAvailableMarkers() {
    for version in ["v1", "v2"] { for service in ["typebar", "other"] {
      for base in ["available", "partial"] { for polyglot in ["available", "partial", "planned"] {
        let capability = RemoteServiceCapabilities(apiVersion: version, service: service,
          capabilities: ["accountFilterPresets": base, "accountFilterPolyglot": polyglot])
        XCTAssertEqual(capability.supportsAccountFilterPolyglot,
          version == "v1" && service == "typebar" && base == "available" && polyglot == "available")
      }}
    }}
    XCTAssertFalse(RemoteServiceCapabilities(apiVersion: "v1", service: "typebar",
      capabilities: ["accountFilterPresets": "available"]).supportsAccountFilterPolyglot)
  }
}
