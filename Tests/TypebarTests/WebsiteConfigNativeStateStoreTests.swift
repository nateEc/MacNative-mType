import XCTest
@testable import Typebar

final class WebsiteConfigNativeStateStoreTests: XCTestCase {
  @MainActor
  private func state() throws -> [String: WebsiteConfigValue] {
    try WebsiteConfigNativeProfile.prepare(#"{"customBackground":"https://example.com/\udfff.png","customBackgroundFilter":[-0,1e400,-1e400,2],"autoSwitchTheme":true,"customTheme":true,"favThemes":["dracula","dracula"],"quoteLength":[0,0,1],"funbox":["rot13","rot13"]}"#,
      context: .init()).projection.runtime
  }

  @MainActor
  private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.website-state.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults)
  }

  @MainActor
  func testSeparateKeyAndUpdatesLeaveEveryLegacyByteAlone() throws {
    try withDefaults { defaults in
      let opaque = Data("Owned opaque legacy state".utf8)
      let oldKeys = ["appSettings.v1", "appSettings.v2", "appSettings.v3", "appSettings.v4", "customTextState.v1"]
      for key in oldKeys { defaults.set(opaque, forKey: key) }
      let store = WebsiteConfigNativeStateStore(defaults: defaults)
      XCTAssertEqual(store.read(), .missing)
      XCTAssertNil(defaults.object(forKey: WebsiteConfigNativeStateStore.storageKey))
      var expected = try state()
      XCTAssertTrue(store.save(expected))
      XCTAssertEqual(store.read(), .available(expected))
      expected["theme"] = .string("dracula")
      XCTAssertTrue(store.save(expected))
      XCTAssertEqual(WebsiteConfigNativeStateStore(defaults: defaults).read(), .available(expected))
      for key in oldKeys { XCTAssertEqual(defaults.data(forKey: key), opaque) }
      let saved = defaults.data(forKey: WebsiteConfigNativeStateStore.storageKey)
      expected["numbers"] = .null
      XCTAssertFalse(store.save(expected))
      XCTAssertEqual(defaults.data(forKey: WebsiteConfigNativeStateStore.storageKey), saved)
    }
  }

  @MainActor
  func testOpaqueCorruptOrFutureBytesAreNeverOverwritten() throws {
    try withDefaults { defaults in
      let expected = try state()
      let valid = try WebsiteConfigNativeStateCodec.encode(expected)
      guard case .array(var future) = try WebsiteConfigJSONReader.read(String(decoding: valid, as: UTF8.self)) else {
        return XCTFail("Missing native envelope")
      }
      future[1] = .number(2)
      let cases: [Any] = ["wrong type", 17, Data(), Data("{".utf8), Data(WebsiteConfigJSONWriter.write(.array(future)).utf8)]
      for object in cases {
        defaults.set(object, forKey: WebsiteConfigNativeStateStore.storageKey)
        let store = WebsiteConfigNativeStateStore(defaults: defaults)
        XCTAssertEqual(store.read(), .unavailable)
        XCTAssertFalse(store.save(expected))
        XCTAssertEqual(defaults.object(forKey: WebsiteConfigNativeStateStore.storageKey) as? NSObject, object as? NSObject)
      }
    }
  }

  @MainActor
  func testIndependentProcessesRetainNativeStateWithoutLegacyRewrite() throws {
    let environment = ProcessInfo.processInfo.environment
    let stageKey = "TYPEBAR_WEBSITE_STATE_CHILD_STAGE", suiteKey = "TYPEBAR_WEBSITE_STATE_CHILD_SUITE"
    let legacy = Data("Owned legacy bytes".utf8)
    if let stage = environment[stageKey] {
      let suite = try XCTUnwrap(environment[suiteKey])
      guard suite.hasPrefix("typebar.website-state-process.") else { return XCTFail("Not an isolated suite") }
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      let store = WebsiteConfigNativeStateStore(defaults: defaults)
      let expected = try state()
      if stage == "write" {
        defaults.set(legacy, forKey: "appSettings.v4")
        XCTAssertTrue(store.save(expected))
      } else {
        XCTAssertEqual(stage, "read")
        XCTAssertEqual(store.read(), .available(expected))
        let bytes = try XCTUnwrap(defaults.data(forKey: WebsiteConfigNativeStateStore.storageKey))
        let restored = try WebsiteConfigNativeStateCodec.decode(bytes)
        XCTAssertEqual(try WebsiteConfigNativeStateCodec.encode(restored), bytes)
        try WebsiteConfigNativeStateCodecTests.assertRoundTrip(restored)
        XCTAssertEqual(defaults.data(forKey: "appSettings.v4"), legacy)
        defaults.set(true, forKey: "qa.website-state-read")
      }
      XCTAssertTrue(defaults.synchronize())
      return
    }
    let suite = "typebar.website-state-process.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    for stage in ["write", "read"] {
      let process = Process(), pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
      process.arguments = ["xctest", "-XCTest", "TypebarTests.WebsiteConfigNativeStateStoreTests/testIndependentProcessesRetainNativeStateWithoutLegacyRewrite",
        Bundle(for: Self.self).bundleURL.path]
      let allowed = ["PATH", "DEVELOPER_DIR", "SDKROOT", "DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH"]
      process.environment = environment.filter { allowed.contains($0.key) }
      process.environment?[stageKey] = stage; process.environment?[suiteKey] = suite
      process.environment?["TYPEBAR_QA_IN_MEMORY_STORE"] = "1"
      process.standardOutput = pipe; process.standardError = pipe
      try process.run()
      let deadline = Date().addingTimeInterval(30)
      while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
      if process.isRunning { process.terminate(); XCTFail("Isolated native state child timed out: \(stage)") }
      process.waitUntilExit()
      let diagnostics = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").filter { $0.contains("error:") || $0.contains("failed") }.joined(separator: "\n")
      XCTAssertEqual(process.terminationStatus, 0, diagnostics)
    }
    let witness = try XCTUnwrap(UserDefaults(suiteName: suite))
    XCTAssertTrue(witness.synchronize())
    XCTAssertTrue(witness.bool(forKey: "qa.website-state-read"))
    XCTAssertEqual(witness.data(forKey: "appSettings.v4"), legacy)
  }
}
