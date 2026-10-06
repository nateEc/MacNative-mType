import Foundation
import XCTest
@testable import Typebar

final class AccountTagPaceTests: XCTestCase {
  private let firstID = UUID(), secondID = UUID()
  private func best(speed: Double = 60.49, mode: String = "time", parameter: Int = 15,
    difficulty: String = "normal", punctuation: Bool = false, numbers: Bool = false,
    lazy: Bool = false, language: String = "english") -> [String: Any] {
    var value: [String: Any] = ["id": UUID().uuidString, "mode": mode,
      "mode2": ["custom", "zen"].contains(mode) ? mode : String(parameter),
      "language": language, "wpm": Int(speed.rounded()), "preciseWpm": speed,
      "rawWpm": 200, "preciseRawWpm": 200.0, "accuracy": 98, "consistency": 80,
      "finishedAt": 100, "acceptedAtMilliseconds": 1_800_000_000_875,
      "personalBestOrigin": "accepted", "personalBestConfiguration": ["version": 1,
        "difficulty": difficulty, "punctuation": punctuation, "numbers": numbers, "lazyMode": lazy]]
    if mode == "time" { value["durationSeconds"] = parameter }
    if mode == "words" { value["wordLimit"] = parameter }
    return value
  }
  private func tag(_ id: UUID, bests: [[String: Any]], name: String = "desk") -> [String: Any] {
    ["id": id.uuidString, "name": name, "personalBestLedgerVersion": 1, "personalBests": bests]
  }
  private func list(_ tags: [[String: Any]]) throws -> RemoteAccountTagList {
    try JSONDecoder().decode(RemoteAccountTagList.self,
      from: JSONSerialization.data(withJSONObject: ["version": 1, "tags": tags]))
  }
  func testAccountTagPaceModeHasDistinctWireIdentityInsteadOfChangingLocalMode() throws {
    let mode = try XCTUnwrap(PaceGuideMode(rawValue: "accountTagPersonalBest"))
    XCTAssertNotEqual(mode, .activeTagPersonalBest)
    let settings = AppSettingsSnapshot(paceGuideMode: mode)
    XCTAssertEqual(try JSONDecoder().decode(AppSettingsSnapshot.self, from: JSONEncoder().encode(settings)).paceGuideMode, mode)
    let archive = TypebarArchive(version: 1, exportedAt: .now, settings: settings, results: [], presets: [])
    XCTAssertEqual(archive.version, 30)
    let document = TypebarSettingsDocument(version: 1, settings: settings, configuration: .timed(seconds: 15),
      layoutFluidLayouts: [], testParameterMemory: .defaults)
    XCTAssertEqual(document.version, 5)
  }
  func testMalformedPBDirectoryFailsBeforeItsSpeedCanReachPace() throws {
    let valid = best()
    XCTAssertEqual(try list([tag(firstID, bests: [valid])]).tags.count, 1)
    for (key, value): (String, Any) in [("mode2", "30"), ("rawWpm", 1),
      ("rawWpm", NSNull()), ("consistency", 150), ("accuracy", -1),
      ("acceptedAtMilliseconds", -1), ("mode", "unknown")] {
      var invalid = valid; invalid[key] = value
      XCTAssertThrowsError(try list([tag(firstID, bests: [invalid])]), key)
    }
  }

  private func target(_ configuration: TestConfiguration = .timed(seconds: 15),
    tags: [RemoteAccountTag]?, selected: [UUID]) throws -> Double? {
    let mode = try XCTUnwrap(PaceGuideMode(rawValue: "accountTagPersonalBest"))
    let unrelated = PaceGuideSample(configuration: configuration, outcome: .completed,
      finishedAt: .now, wpm: 400, tags: ["desk"])
    return PaceGuidePolicy.targetWpm(mode: mode, customWpm: 300, configuration: configuration,
      samples: [unrelated], activeTags: ["desk"], accountTags: tags, selectedAccountTagIDs: selected)
  }
  func testStableIdentitySelectsHighestFractionalPBNotSameNameOrLocalText() throws {
    let directory = try list([tag(firstID, bests: [best(speed: 60.41)]),
      tag(secondID, bests: [best(speed: 60.49)])]).tags
    XCTAssertEqual(try target(tags: directory, selected: [firstID]), 60.41)
    XCTAssertEqual(try target(tags: directory, selected: [firstID, secondID]), 60.49)
    XCTAssertNil(try target(tags: directory, selected: []))
    XCTAssertNil(try target(tags: nil, selected: [firstID]))
    XCTAssertNil(try target(tags: [], selected: [firstID]))
    XCTAssertNil(try target(tags: directory, selected: [UUID()]))
    XCTAssertNil(try target(tags: directory, selected: [firstID, firstID]))
    let renamed = try list([tag(firstID, bests: [best(speed: 60.41)], name: "renamed")]).tags
    XCTAssertEqual(try target(tags: renamed, selected: [firstID]), 60.41)
  }
  func testEveryGroupingControlMustMatchButCurrentFunboxDoesNotHideExistingPB() throws {
    let directory = try list([tag(firstID, bests: [best()])]).tags
    var config = TestConfiguration.timed(seconds: 15)
    XCTAssertEqual(try target(config.with(modifiers: [.binaryStream]), tags: directory, selected: [firstID]), 60.49)
    for changed in [TestConfiguration.timed(seconds: 30), .words(15),
      .init(mode: .time, duration: 15, wordLimit: nil, difficulty: .normal, rules: .init(), language: .spanish),
      .init(mode: .time, duration: 15, wordLimit: nil, difficulty: .expert, rules: .init()),
      config.with(modifiers: [.lazyLatin])] {
      XCTAssertNil(try target(changed, tags: directory, selected: [firstID]))
    }
    config.contentOptions.includePunctuation = true
    XCTAssertNil(try target(config, tags: directory, selected: [firstID]))
    config.contentOptions.includePunctuation = false; config.contentOptions.includeNumbers = true
    XCTAssertNil(try target(config, tags: directory, selected: [firstID]))
  }
  func testCustomAndZenUseFixedMode2AndUnknownOptionsOrZeroDoNotBecomeDefaults() throws {
    for mode in [TestMode.custom, .zen] {
      let directory = try list([tag(firstID, bests: [best(mode: mode.rawValue)])]).tags
      for limit in [10, 200] {
        XCTAssertEqual(try target(.init(mode: mode, duration: 30, wordLimit: limit, difficulty: .normal, rules: .init()),
          tags: directory, selected: [firstID]), 60.49)
      }
    }
    var unknown = best(); unknown.removeValue(forKey: "personalBestConfiguration")
    let directory = try list([tag(firstID, bests: [unknown])]).tags
    XCTAssertNil(try target(tags: directory, selected: [firstID]))
    XCTAssertNil(try target(tags: list([tag(firstID, bests: [best(speed: 0)])]).tags, selected: [firstID]))
    XCTAssertNil(try target(.init(mode: .quote, duration: nil, wordLimit: nil, difficulty: .normal, rules: .init()),
      tags: directory, selected: [firstID]))
  }
  @MainActor func testDirectoryFencePreventsOldReadAndAccountRoundTripFromRevivingPace() throws {
    let suite = "TypebarTests.account-pace-fence.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    XCTAssertTrue(account.updateEndpoint("https://owned.invalid"))
    let user = RemoteAccountUser(id: UUID(), email: "owned@example.invalid", displayName: "owned", totalExperience: 0)
    account.currentUser = user
    let older = try account.beginAccountTagDirectoryRead(), newest = try account.beginAccountTagDirectoryRead()
    let before = try list([tag(firstID, bests: [best(speed: 60.41)])])
    let after = try list([tag(firstID, bests: [best(speed: 60.49)])])
    try account.applyAccountTagDirectory(after, read: newest)
    try account.setAccountTagPostingSelection([firstID])
    XCTAssertThrowsError(try account.applyAccountTagDirectory(before, read: older))
    XCTAssertEqual(try target(tags: account.accountTags, selected: account.accountTagPostingSelection()), 60.49)
    account.currentUser = nil
    XCTAssertFalse(account.hasAccountTagDirectory); XCTAssertTrue(account.accountTags.isEmpty)
    account.currentUser = user
    XCTAssertFalse(account.hasAccountTagDirectory)
    XCTAssertThrowsError(try account.applyAccountTagDirectory(after, read: newest))
    let current = try account.beginAccountTagDirectoryRead()
    try account.applyAccountTagDirectory(before, read: current)
    account.invalidateAccountTagDirectory()
    XCTAssertThrowsError(try account.applyAccountTagDirectory(after, read: current))
    XCTAssertFalse(account.hasAccountTagDirectory)
  }
  @MainActor func testDirectoryRefreshPrunesDeletedIDsAndNewServerNeverInheritsPace() throws {
    let suite = "TypebarTests.account-pace-owner.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    XCTAssertTrue(account.updateEndpoint("https://owned.invalid"))
    let user = RemoteAccountUser(id: UUID(), email: "owned@example.invalid", displayName: "owned", totalExperience: 0)
    account.currentUser = user
    try account.applyAccountTagDirectory(list([tag(firstID, bests: [best()]), tag(secondID, bests: [])]),
      read: account.beginAccountTagDirectoryRead())
    try account.setAccountTagPostingSelection([firstID, secondID])
    try account.applyAccountTagDirectory(list([tag(secondID, bests: [])]), read: account.beginAccountTagDirectoryRead())
    XCTAssertEqual(try account.accountTagPostingSelection(), [secondID])
    XCTAssertNil(try target(tags: account.accountTags, selected: account.accountTagPostingSelection()))
    XCTAssertTrue(account.updateEndpoint("https://elsewhere.invalid")); account.currentUser = user
    XCTAssertFalse(account.hasAccountTagDirectory); XCTAssertEqual(try account.accountTagPostingSelection(), [])
    XCTAssertTrue(account.updateEndpoint("https://owned.invalid")); account.currentUser = user
    XCTAssertFalse(account.hasAccountTagDirectory)
  }
  @MainActor func testNewPaceForkPreservesBothOldGenerationsAndStaysForkedAfterChangingMode() throws {
    let suite = "TypebarTests.account-pace-storage.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let v1 = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 34, paceGuideCustomWpm: 95))
    let v2 = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 36, paceGuideCustomWpm: 60.25))
    defaults.set(v1, forKey: "appSettings.v1"); defaults.set(v2, forKey: "appSettings.v2")
    let settings = AppSettings(defaults: defaults)
    XCTAssertEqual(settings.fontSize, 36)
    let mode = try XCTUnwrap(PaceGuideMode(rawValue: "accountTagPersonalBest"))
    settings.apply(.init(fontSize: 38, paceGuideMode: mode))
    XCTAssertEqual(defaults.data(forKey: "appSettings.v1"), v1)
    XCTAssertEqual(defaults.data(forKey: "appSettings.v2"), v2)
    XCTAssertEqual(AppSettings(defaults: defaults).paceGuideMode, mode)
    settings.paceGuideMode = .personalBest
    XCTAssertNotNil(defaults.data(forKey: "appSettings.v3"))
    defaults.set(v1, forKey: "appSettings.v2")
    XCTAssertEqual(AppSettings(defaults: defaults).fontSize, 38)
    let bad = Data("broken".utf8); defaults.set(bad, forKey: "appSettings.v3")
    XCTAssertEqual(AppSettings(defaults: defaults).paceGuideMode, .off)
    XCTAssertEqual(defaults.data(forKey: "appSettings.v3"), bad)
  }
  func testNewModeCannotMasqueradeAsOldArchiveOrDeletedPresetOrSettingsJSON() throws {
    let mode = try XCTUnwrap(PaceGuideMode(rawValue: "accountTagPersonalBest"))
    let snapshot = AppSettingsSnapshot(paceGuideMode: mode), id = UUID()
    let preset = NamedPreset(id: id, name: "owned", definition: .init(configuration: .timed(seconds: 15), settingsSnapshot: snapshot))
    let promoted = TypebarArchive(version: 1, exportedAt: .now, settings: .init(), results: [],
      presets: [preset], deletedPresetIDs: [id])
    XCTAssertEqual(promoted.version, 30); XCTAssertEqual(promoted.deletedPresetIDs, [id]); XCTAssertTrue(promoted.presets.isEmpty)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    for original in [TypebarArchive(exportedAt: .now, settings: snapshot, results: [], presets: []),
      TypebarArchive(exportedAt: .now, settings: .init(), results: [], presets: [preset])] {
      var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
      root["version"] = 29; root["deletedPresetIDs"] = [id.uuidString]
      XCTAssertThrowsError(try TypebarDataTransfer.importArchive(from: JSONSerialization.data(withJSONObject: root)))
    }
    let json = try SettingsJSONCommandCodec.export(settings: snapshot, configuration: .timed(seconds: 15),
      layoutFluidLayouts: [], testParameterMemory: .defaults)
    XCTAssertEqual(try SettingsJSONCommandCodec.decode(json).settings.paceGuideMode, mode)
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    root["version"] = 4
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    XCTAssertThrowsError(try decoder.decode(TypebarSettingsDocument.self, from: JSONSerialization.data(withJSONObject: root)))
    XCTAssertThrowsError(try SettingsJSONCommandCodec.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
  }
  func testNativeGetterAgainstActualPinnedTagPBAndPaceInitFunctions() throws {
    guard let reference = ProcessInfo.processInfo.environment["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Readiness supplies the pinned reference")
    }
    let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appendingPathComponent("Scripts/check-source-account-tag-pace.mjs")
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", script.path, reference, "--emit-fixtures"]
    process.standardOutput = output; process.standardError = errors
    try process.run()
    let bytes = output.fileHandleForReading.readDataToEndOfFile()
    let error = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0, String(decoding: error, as: UTF8.self))
    struct Fixture: Decodable {
      let mode: TestMode; let parameter: Int; let difficulty: Difficulty; let language: TypingLanguage
      let punctuation: Bool; let numbers: Bool; let lazyMode: Bool
      let selectedIDs: [UUID]; let expected: Double?
    }
    struct Document: Decodable {
      let referenceCommit: String; let directory: RemoteAccountTagList; let fixtures: [Fixture]
    }
    let document = try JSONDecoder().decode(Document.self, from: bytes)
    XCTAssertEqual(document.referenceCommit, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(document.fixtures.count, 1680)
    for value in document.fixtures {
      let config = TestConfiguration(mode: value.mode,
        duration: value.mode == .time ? Double(value.parameter) : nil,
        wordLimit: value.mode == .words ? value.parameter : nil, difficulty: value.difficulty,
        rules: .init(), language: value.language, modifiers: value.lazyMode ? [.lazyLatin] : [],
        contentOptions: .init(includePunctuation: value.punctuation, includeNumbers: value.numbers))
      XCTAssertEqual(try target(config, tags: document.directory.tags, selected: value.selectedIDs), value.expected)
    }
  }
  @MainActor func testCancelledRefreshCannotConsumeTheLatestDirectoryReadGeneration() async throws {
    let suite = "TypebarTests.account-pace-cancel.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let account = AccountSession(defaults: defaults)
    account.currentUser = .init(id: UUID(), email: "owned@example.invalid", displayName: "owned", totalExperience: 0)
    let read = try account.beginAccountTagDirectoryRead(), directory = try list([tag(firstID, bests: [best()])])
    try account.applyAccountTagDirectory(directory, read: read)
    let task = Task { @MainActor in try await account.reloadAccountTags() }
    task.cancel()
    do { try await task.value; XCTFail("A cancelled request must not read credentials or the network") }
    catch is CancellationError { }
    let quiet = Task { @MainActor in await account.refreshAccountTagsForPractice() }
    quiet.cancel(); await quiet.value
    XCTAssertTrue(account.hasAccountTagDirectory)
    XCTAssertNoThrow(try account.applyAccountTagDirectory(directory, read: read),
      "Neither cancelled path may advance the live read generation")
  }
}
