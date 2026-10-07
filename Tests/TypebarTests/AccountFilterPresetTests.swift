import Foundation
import XCTest
@testable import Typebar

final class AccountFilterPresetTests: XCTestCase {
  private let scope = ResultPublicationScope(endpoint: "https://owned.invalid", userID: UUID())
  func testDisabledMutationStateSurvivesListRoundTripWithoutHidingPresets() throws {
    let doc = try AccountFilterPresetDocument(name: "Study", filter: .init(), scope: scope)
    let preset = RemoteAccountFilterPreset(id: UUID(), document: doc)
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
      RemoteAccountFilterPresetList(version: 1, maximumPresets: 20, presets: [preset]))) as? [String: Any])
    wire["mutationsEnabled"] = false
    let list = try JSONDecoder().decode(RemoteAccountFilterPresetList.self, from: JSONSerialization.data(withJSONObject: wire))
    try list.validate()
    XCTAssertEqual(list.presets, [preset])
    let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])
    XCTAssertEqual(encoded["mutationsEnabled"] as? Bool, false)
  }

  func testInvalidMutationStateNeverDefaultsToEnabled() throws {
    let list = RemoteAccountFilterPresetList(version: 1, maximumPresets: 20, presets: [])
    let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any])
    for value: Any in [NSNull(), 1, "false"] {
      var bad = wire; bad["mutationsEnabled"] = value
      XCTAssertThrowsError(try JSONDecoder().decode(RemoteAccountFilterPresetList.self, from: JSONSerialization.data(withJSONObject: bad)))
    }
  }
  func testLegacyListAllowsMutationsWithoutInventingCapacity() throws {
    let bytes = Data(#"{"version":1,"maximumPresets":0,"presets":[]}"#.utf8)
    let list = try JSONDecoder().decode(RemoteAccountFilterPresetList.self, from: bytes)
    try list.validate(); XCTAssertTrue(list.mutationsEnabled); XCTAssertEqual(list.maximumPresets, 0)
    XCTAssertNoThrow(try list.requireMutationsEnabled())
  }

  @MainActor func testDisabledCacheAllowsApplyButRejectsBothMutationsBeforeSessionStateChanges() async throws {
    let suite = "typebar-disabled-filter-presets-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owner@example.invalid", displayName: "Owner", totalExperience: 0)
    let active = try XCTUnwrap(account.resultPublicationScope)
    let doc = try AccountFilterPresetDocument(name: "Study", filter: .init(personalBestFilter: .only), scope: active)
    let preset = RemoteAccountFilterPreset(id: UUID(), document: doc)
    let read = try account.beginAccountFilterPresetRead()
    try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, mutationsEnabled: false, presets: [preset]), read: read)
    for deleting in [false, true] {
      do {
        if deleting { try await account.deleteAccountFilterPreset(id: preset.id, scope: active) }
        else { try await account.saveAccountFilterPreset(name: "Study", filter: .init(), scope: active) }
        XCTFail("Disabled cache must reject before token lookup or a request")
      } catch { XCTAssertTrue(error.localizedDescription.contains("修改已暂停")) }
      XCTAssertFalse(account.isEditingAccountFilterPresets)
      XCTAssertNotNil(account.accountFilterPresetCache)
      XCTAssertEqual(account.accountFilterPresets, [preset])
      XCTAssertEqual(try account.accountFilterPreset(id: preset.id, scope: active).effectivePersonalBestFilter, .only)
    }
    let refreshed = try account.beginAccountFilterPresetRead()
    try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: refreshed)
    XCTAssertNoThrow(try account.accountFilterPresetCache?.list.requireMutationsEnabled())
    XCTAssertThrowsError(try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, mutationsEnabled: false, presets: [preset]), read: read))
    account.currentUser = nil
    XCTAssertNil(account.accountFilterPresetCache)
  }
  func testSnapshotRoundTripsEveryChoiceAndDoesNotPublishScopeOrResults() throws {
    let selected = UUID(), off = UUID()
    let filter = ResultHistoryFilter(modes: [.time, .quote], languages: [.english],
      tagFilter: .init(isUnrestricted: false, includesNoTags: true, tags: ["desk"]),
      accountTagFilter: .init(scope: scope, knownIDs: [selected, off], selectedIDs: [selected], includesNoTags: false),
      personalBestFilter: .excluded, difficulties: [.expert], dateRange: .lastWeek, punctuation: .included,
      numbers: .noMatches, quoteLengths: [.long, .extended], timeLimits: [.seconds15, .custom], wordLimits: [],
      modifierFilter: .init(includesNoModifiers: false, modifiers: [.backwards]))
    let document = try AccountFilterPresetDocument(name: "  Study   set ", filter: filter, scope: scope)
    let restored = try document.restored(scope: scope, knownTagIDs: [selected, off])
    XCTAssertEqual(restored, filter); XCTAssertEqual(document.name, "Study_set")
    let wire = try JSONEncoder().encode(RemoteAccountFilterPreset(id: UUID(), document: document))
    let decoded = try JSONDecoder().decode(RemoteAccountFilterPreset.self, from: wire)
    XCTAssertEqual(decoded.document, document)
    let text = String(decoding: document.filterData, as: UTF8.self)
    for forbidden in ["scope", "serverID", "userID", "prompt", "replay", "token"] { XCTAssertFalse(text.contains(forbidden)) }
    XCTAssertNil(try JSONSerialization.jsonObject(with: document.filterData) as? [String: String])
  }
  func testDirectoryChangesRetainOffChoicesEnableNewIDsAndPruneDeletedIDs() throws {
    let selected = UUID(), off = UUID(), added = UUID()
    let document = try AccountFilterPresetDocument(name: "Study", filter: .init(accountTagFilter:
      .init(scope: scope, knownIDs: [selected, off], selectedIDs: [selected], includesNoTags: true)), scope: scope)
    let otherDeviceScope = ResultPublicationScope(endpoint: "https://alternate.invalid", userID: scope.userID)
    let restored = try document.restored(scope: otherDeviceScope, knownTagIDs: [off, added])
    XCTAssertEqual(restored.accountTagFilter?.scope, otherDeviceScope)
    XCTAssertEqual(restored.accountTagFilter?.selectedIDs, [added])
    XCTAssertEqual(restored.accountTagFilter?.knownIDs, [off, added])
    XCTAssertEqual(restored.accountTagFilter?.includesNoTags, true)
    XCTAssertThrowsError(try document.restored(scope: scope, knownTagIDs: nil))
    XCTAssertThrowsError(try AccountFilterPresetDocument(name: "Study", filter: .init(accountTagFilter:
      .init(scope: otherDeviceScope, knownIDs: [], selectedIDs: [], includesNoTags: true)), scope: scope))
  }
  func testNamesFollowPinnedSlugRatherThanLocalTagNamePolicy() {
    for name in ["a", "Study_set", "a..b", "a--", "_", "-", "1234567890123456"] { XCTAssertTrue(AccountFilterPresetDocument.isValidName(name), name) }
    for name in ["", ".start", "has space", "中文", "12345678901234567", "bad/slash"] { XCTAssertFalse(AccountFilterPresetDocument.isValidName(name), name) }
  }
  func testMalformedAndUnsupportedDocumentsNeverBecomeAnAllFilter() throws {
    let document = try AccountFilterPresetDocument(name: "Study", filter: .init(), scope: scope)
    let base = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
    let valid = try XCTUnwrap(JSONSerialization.jsonObject(with: document.filterData) as? [String: Any])
    var samples: [[String: Any]] = []
    for (key, value) in [("unknown", true as Any), ("dateRange", "future"), ("personalBestOnly", NSNull()),
      ("modes", ["time", "time"]), ("quoteLengths", ["all"]), ("accountTagFilter", ["scope": "foreign"])] {
      var changed = valid; changed[key] = value; samples.append(changed)
    }
    var missing = valid; missing.removeValue(forKey: "modifierFilter"); samples.append(missing)
    for sample in samples {
      var wire = base; wire["filterData"] = try JSONSerialization.data(withJSONObject: sample).base64EncodedString()
      XCTAssertThrowsError(try JSONDecoder().decode(AccountFilterPresetDocument.self, from: JSONSerialization.data(withJSONObject: wire)))
    }
    for (key, value) in [("version", 2 as Any), ("accountTags", NSNull()), ("filterData", Data(repeating: 65, count: 65_537).base64EncodedString())] {
      var changed = base; changed[key] = value
      XCTAssertThrowsError(try JSONDecoder().decode(AccountFilterPresetDocument.self, from: JSONSerialization.data(withJSONObject: changed)))
    }
  }
  @MainActor func testSessionRejectsReorderedReadsAndClearsCacheAcrossAccountAndEndpointChanges() throws {
    let suite = "typebar-account-filter-presets-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: scope.userID, email: "owner@example.invalid", displayName: "Owner", totalExperience: 0)
    let activeScope = try XCTUnwrap(account.resultPublicationScope)
    let document = try AccountFilterPresetDocument(name: "Study", filter: .init(personalBestFilter: .only), scope: activeScope)
    let preset = RemoteAccountFilterPreset(id: UUID(), document: document)
    let first = try account.beginAccountFilterPresetRead(), latest = try account.beginAccountFilterPresetRead()
    XCTAssertThrowsError(try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: first))
    try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: latest)
    XCTAssertEqual(try account.accountFilterPreset(id: preset.id, scope: activeScope).effectivePersonalBestFilter, .only)
    XCTAssertEqual(account.accountFilterPresets.count, 1)
    account.currentUser = nil
    XCTAssertTrue(account.accountFilterPresets.isEmpty)
    XCTAssertNil(account.accountFilterPresetCache)
    XCTAssertThrowsError(try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: latest))
    XCTAssertThrowsError(try account.accountFilterPreset(id: preset.id, scope: activeScope))
    account.currentUser = .init(id: scope.userID, email: "owner@example.invalid", displayName: "Owner", totalExperience: 0)
    XCTAssertThrowsError(try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: latest), "ABA sign-in cannot resurrect an earlier read")
    let signedInRead = try account.beginAccountFilterPresetRead()
    try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: signedInRead)
    XCTAssertTrue(account.updateEndpoint("https://alternate.invalid"))
    XCTAssertNil(account.accountFilterPresetCache)
    XCTAssertThrowsError(try account.applyAccountFilterPresets(.init(version: 1, maximumPresets: 20, presets: [preset]), read: signedInRead))
  }
  func testExactCapabilitiesAndDuplicateIDsAreChecked() throws {
    let doc = try AccountFilterPresetDocument(name: "Study", filter: .init(), scope: scope)
    let preset = RemoteAccountFilterPreset(id: UUID(), document: doc)
    XCTAssertThrowsError(try RemoteAccountFilterPresetList(version: 1, maximumPresets: 20, presets: [preset, preset]).validate())
    for (version, service, status, expected) in [("v1", "typebar", "available", true), ("v2", "typebar", "available", false),
      ("v1", "other", "available", false), ("v1", "typebar", "partial", false), ("v1", "typebar", "planned", false)] {
      XCTAssertEqual(RemoteServiceCapabilities(apiVersion: version, service: service,
        capabilities: ["accountFilterPresets": status]).supportsAccountFilterPresets, expected)
    }
  }
}
