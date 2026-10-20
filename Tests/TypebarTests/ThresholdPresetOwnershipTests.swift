import XCTest
@testable import Typebar

final class ThresholdPresetOwnershipTests: XCTestCase {
  private func preset(memory: Double, mode: MinimumWordBurstMode) throws -> SavedTestPreset {
    var raw = PracticeThresholdConfiguration()
    try raw.apply(.minimumWpm(mode: .off, customValue: memory))
    try raw.apply(.minimumAccuracy(mode: .custom, customValue: 0))
    try raw.apply(.minimumWordBurst(mode: mode, customValue: 0))
    let source = PracticeThresholdSource(configuration: raw)
    var configuration = TestConfiguration.words(17)
    configuration.rules = source.applying(to: configuration.rules)
    return .init(configuration: configuration,
      settingsSnapshot: source.applying(to: AppSettingsSnapshot(fontSize: 31)))
  }

  private func assertThresholds(_ actual: SavedTestPreset, equal expected: SavedTestPreset,
    file: StaticString = #filePath, line: UInt = #line) throws {
    let rules = actual.configuration.rules
    XCTAssertEqual(rules.thresholdSource, expected.configuration.rules.thresholdSource, file: file, line: line)
    XCTAssertEqual(rules.minimumWpm, expected.configuration.rules.minimumWpm, file: file, line: line)
    XCTAssertEqual(rules.minimumWordBurstWpm, expected.configuration.rules.minimumWordBurstWpm, file: file, line: line)
    XCTAssertEqual(rules.minimumWordBurstMode, expected.configuration.rules.minimumWordBurstMode, file: file, line: line)
    let snapshot = try XCTUnwrap(actual.settingsSnapshot, file: file, line: line)
    XCTAssertEqual(snapshot.thresholdSource, expected.settingsSnapshot?.thresholdSource, file: file, line: line)
    XCTAssertEqual(snapshot.minimumWpm, expected.settingsSnapshot?.minimumWpm, file: file, line: line)
    if let source = rules.thresholdSource { XCTAssertTrue(source.matches(rules), file: file, line: line) }
    if let source = snapshot.thresholdSource { XCTAssertTrue(source.matches(snapshot), file: file, line: line) }
  }

  func testBehaviorOwnsCompleteSourceEvenWhenEffectiveValuesAreEqual() throws {
    let current = try preset(memory: 31, mode: .fixed)
    let incoming = try preset(memory: 73, mode: .flex)
    for groups: Set<PresetSettingGroup> in [[.behavior], [.behavior, .appearance], Set(PresetSettingGroup.allCases)] {
      let result = PresetApplicationPolicy.applying(current: current, preset: incoming.with(settingGroups: groups))
      try assertThresholds(result, equal: incoming)
    }
  }

  func testLegacyBehaviorClearsSourceInsteadOfRetainingConflictingMemory() throws {
    let current = try preset(memory: 31, mode: .flex)
    var legacy = SavedTestPreset(configuration: .words(25), settingsSnapshot: .init())
    legacy.configuration.rules.minimumWpm = 45
    legacy.settingsSnapshot?.minimumWpm = 45
    let result = PresetApplicationPolicy.applying(current: current, preset: legacy.with(settingGroups: [.behavior]))
    try assertThresholds(result, equal: legacy)
  }

  func testUnselectedBehaviorPreservesCurrentSourceForEveryOtherGroup() throws {
    let current = try preset(memory: 31, mode: .fixed)
    let incoming = try preset(memory: 73, mode: .flex)
    for group in PresetSettingGroup.allCases where group != .behavior {
      let result = PresetApplicationPolicy.applying(current: current, preset: incoming.with(settingGroups: [group]))
      try assertThresholds(result, equal: current)
    }
    try assertThresholds(PresetApplicationPolicy.applying(current: current,
      preset: incoming.with(settingGroups: [])), equal: current)
  }

  func testFullPresetRetainsRawModeAndMemoryWithoutInference() throws {
    let current = try preset(memory: 31, mode: .fixed)
    let incoming = try preset(memory: 73, mode: .flex)
    XCTAssertEqual(PresetApplicationPolicy.applying(current: current, preset: incoming), incoming)
  }

  func testBehaviorWithoutGlobalSnapshotUsesItsOwnRulesNotCurrentThresholds() throws {
    let current = try preset(memory: 31, mode: .fixed)
    var incoming = try preset(memory: 73, mode: .flex)
    let expected = incoming
    incoming.settingsSnapshot = nil
    let result = PresetApplicationPolicy.applying(current: current,
      preset: incoming.with(settingGroups: [.behavior]))
    try assertThresholds(result, equal: expected)
    XCTAssertEqual(result.settingsSnapshot?.fontSize, current.settingsSnapshot?.fontSize)

    var legacy = SavedTestPreset(configuration: .words(25))
    legacy.configuration.rules.minimumWpm = 45
    let applied = PresetApplicationPolicy.applying(current: current,
      preset: legacy.with(settingGroups: [.behavior]))
    XCTAssertNil(applied.settingsSnapshot?.thresholdSource)
    XCTAssertEqual(applied.settingsSnapshot?.minimumWpm, 45)
  }

  func testMissingCurrentSnapshotDoesNotImportUnselectedThresholds() throws {
    var current = try preset(memory: 31, mode: .fixed)
    let expected = current
    current.settingsSnapshot = nil
    var incoming = try preset(memory: 73, mode: .flex)
    incoming.settingsSnapshot?.fontSize = 42
    let result = PresetApplicationPolicy.applying(current: current,
      preset: incoming.with(settingGroups: [.appearance]))
    try assertThresholds(result, equal: expected)
    XCTAssertEqual(result.settingsSnapshot?.fontSize, 42)

    let legacyCurrent = SavedTestPreset(configuration: .words(25))
    let legacyApplied = PresetApplicationPolicy.applying(current: legacyCurrent,
      preset: incoming.with(settingGroups: [.appearance]))
    XCTAssertNil(legacyApplied.settingsSnapshot?.thresholdSource)
    XCTAssertEqual(legacyApplied.settingsSnapshot?.minimumWpm, 0)
  }
}
