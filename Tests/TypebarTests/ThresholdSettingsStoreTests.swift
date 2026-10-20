import XCTest
@testable import Typebar

final class ThresholdSettingsStoreTests: XCTestCase {
  private func snapshot() throws -> AppSettingsSnapshot {
    var value = PracticeThresholdConfiguration()
    try value.apply(.minimumWpm(mode: .off, customValue: 31))
    try value.apply(.minimumAccuracy(mode: .custom, customValue: 0))
    try value.apply(.minimumWordBurst(mode: .flex, customValue: 0))
    return PracticeThresholdSource(configuration: value).applying(to:
      AppSettingsSnapshot(fontSize: 34, paceGuideMode: .accountTagPersonalBest, paceGuideCustomWpm: 350.25))
  }

  private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.threshold-store.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  private func object(_ snapshot: AppSettingsSnapshot) throws -> [String: Any] {
    let encoder = JSONEncoder()
    encoder.userInfo[PracticeThresholdSource.codingCapability] = true
    return try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(snapshot)) as? [String: Any])
  }

  func testMissingNewGenerationDoesNotReadOrRewriteLegacyKeys() throws {
    try withDefaults { defaults in
      let legacy = try JSONEncoder().encode(AppSettingsSnapshot(fontSize: 23))
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] { defaults.set(legacy, forKey: key) }
      let store = ThresholdSettingsStore(defaults: defaults)
      XCTAssertEqual(store.read(), .missing)
      XCTAssertNil(defaults.object(forKey: ThresholdSettingsStore.storageKey))
      let expected = try snapshot()
      XCTAssertTrue(store.save(expected))
      XCTAssertEqual(store.read(), .available(expected))
      for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
        XCTAssertEqual(defaults.data(forKey: key), legacy)
      }
      let newBytes = defaults.data(forKey: ThresholdSettingsStore.storageKey)
      defaults.set(Data("owned later legacy write".utf8), forKey: "appSettings.v3")
      XCTAssertEqual(store.read(), .available(expected))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), newBytes)
    }
  }

  func testValidUpdatesRetainSixSourceFieldsAndUnrelatedSettings() throws {
    try withDefaults { defaults in
      let store = ThresholdSettingsStore(defaults: defaults)
      let first = try snapshot()
      XCTAssertTrue(store.save(first))
      var raw = try XCTUnwrap(first.thresholdSource?.configuration)
      try raw.apply(.minimumWpm(mode: .custom, customValue: 22.5))
      var updated = PracticeThresholdSource(configuration: raw).applying(to: first)
      updated.fontSize = 36
      XCTAssertTrue(store.save(updated))
      XCTAssertEqual(ThresholdSettingsStore(defaults: defaults).read(), .available(updated))
      XCTAssertEqual(updated.thresholdSource?.configuration.minimumWordBurstMode, .flex)
      XCTAssertEqual(updated.thresholdSource?.configuration.minimumWordBurstCustomValue, 0)
      XCTAssertEqual(updated.paceGuideMode, .accountTagPersonalBest)
      XCTAssertEqual(updated.paceGuideCustomWpm, 350.25)
    }
  }

  func testUnreadableOrFutureStateIsPresentAndNeverOverwritten() throws {
    try withDefaults { defaults in
      let expected = try snapshot()
      let body = try object(expected)
      var futureSource = body
      var capsule = try XCTUnwrap(body["thresholdSource"] as? [String: Any])
      capsule["version"] = 2
      futureSource["thresholdSource"] = capsule
      var conflict = body
      conflict["minimumWpm"] = 99
      let values: [Any] = ["wrong type", Data(), Data("{".utf8),
        try JSONSerialization.data(withJSONObject: ["version": 5, "settings": body]),
        try JSONSerialization.data(withJSONObject: ["version": 3, "settings": body]),
        try JSONSerialization.data(withJSONObject: ["version": 4, "settings": futureSource]),
        try JSONSerialization.data(withJSONObject: ["version": 4, "settings": conflict]),
        try JSONSerialization.data(withJSONObject: ["version": 4, "settings": NSNull()])]
      for value in values {
        defaults.set(value, forKey: ThresholdSettingsStore.storageKey)
        let store = ThresholdSettingsStore(defaults: defaults)
        XCTAssertEqual(store.read(), .unavailable)
        XCTAssertFalse(store.save(expected))
        if let bytes = value as? Data { XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), bytes) }
        else { XCTAssertEqual(defaults.string(forKey: ThresholdSettingsStore.storageKey), "wrong type") }
      }
    }
  }

  func testMissingSourceAndNoncanonicalWritesCannotReplaceAValidProfile() throws {
    try withDefaults { defaults in
      let store = ThresholdSettingsStore(defaults: defaults)
      let valid = try snapshot()
      XCTAssertTrue(store.save(valid))
      let before = defaults.data(forKey: ThresholdSettingsStore.storageKey)
      XCTAssertFalse(store.save(.init()))
      var invalid = valid
      invalid.minimumWpm = 40
      XCTAssertFalse(store.save(invalid))
      invalid = valid
      invalid.paceGuideCustomWpm = -1
      XCTAssertFalse(store.save(invalid))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), before)
      let missingSource = try object(.init())
      let unreadable = try JSONSerialization.data(withJSONObject: ["version": 4, "settings": missingSource])
      defaults.set(unreadable, forKey: ThresholdSettingsStore.storageKey)
      XCTAssertEqual(store.read(), .unavailable)
      XCTAssertFalse(store.save(valid))
      XCTAssertEqual(defaults.data(forKey: ThresholdSettingsStore.storageKey), unreadable)
    }
  }

  func testIndependentProcessesRetainSourceState() throws {
    let environment = ProcessInfo.processInfo.environment
    let stageKey = "TYPEBAR_THRESHOLD_STORE_CHILD_STAGE"
    let suiteKey = "TYPEBAR_THRESHOLD_STORE_CHILD_SUITE"
    if let stage = environment[stageKey] {
      let suite = try XCTUnwrap(environment[suiteKey])
      XCTAssertTrue(suite.hasPrefix("typebar.threshold-process."))
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let store = ThresholdSettingsStore(defaults: defaults)
      let expected = try snapshot()
      let legacyEncoder = JSONEncoder()
      legacyEncoder.outputFormatting = .sortedKeys
      let legacy = try legacyEncoder.encode(AppSettingsSnapshot(fontSize: 23))
      if stage == "write" {
        for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] { defaults.set(legacy, forKey: key) }
        XCTAssertTrue(store.save(expected))
        XCTAssertTrue(defaults.synchronize())
      } else {
        XCTAssertEqual(stage, "read")
        XCTAssertEqual(store.read(), .available(expected))
        for key in ["appSettings.v1", "appSettings.v2", "appSettings.v3"] {
          XCTAssertEqual(defaults.data(forKey: key), legacy)
        }
        defaults.set(true, forKey: "qa.threshold-profile-read")
        XCTAssertTrue(defaults.synchronize())
      }
      return
    }
    let suite = "typebar.threshold-process.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    for stage in ["write", "read"] {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = ["xctest", "-XCTest",
        "TypebarTests.ThresholdSettingsStoreTests/testIndependentProcessesRetainSourceState",
        Bundle(for: Self.self).bundleURL.path]
      let allowed = ["PATH", "DEVELOPER_DIR", "SDKROOT", "DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH"]
      process.environment = environment.filter { allowed.contains($0.key) }
      process.environment?[stageKey] = stage
      process.environment?[suiteKey] = suite
      process.environment?["TYPEBAR_QA_IN_MEMORY_STORE"] = "1"
      let output = Pipe()
      process.standardOutput = output
      process.standardError = output
      try process.run()
      let deadline = Date().addingTimeInterval(30)
      while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { process.terminate(); XCTFail("Threshold profile child timed out: \(stage)") }
      process.waitUntilExit()
      let diagnostics = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").filter { $0.contains("error:") || $0.contains("failed") }.joined(separator: "\n")
      XCTAssertEqual(process.terminationStatus, 0, diagnostics)
      let witness = try XCTUnwrap(UserDefaults(suiteName: suite))
      XCTAssertTrue(witness.synchronize())
      XCTAssertEqual(ThresholdSettingsStore(defaults: witness).read(), .available(try snapshot()))
      if stage == "read" { XCTAssertTrue(witness.bool(forKey: "qa.threshold-profile-read")) }
    }
  }
}
