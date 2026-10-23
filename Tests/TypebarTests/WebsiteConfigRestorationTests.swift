import XCTest
@testable import Typebar

final class WebsiteConfigRestorationTests: XCTestCase {
  @MainActor
  func testActualColdStorageReadMigrationCacheAndApplication() throws {
    let env = ProcessInfo.processInfo.environment
    guard let reference = env["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? env["TYPEBAR_REFERENCE_ROOT"] else {
      throw XCTSkip("Requires pinned reference")
    }
    guard env["TYPEBAR_WEBSITE_CONFIG_ZOD_ROOT"] != nil else { return XCTFail("Requires pinned Zod") }
    struct Catalogs: Decodable { let languages: Set<String>, themes: Set<String>, layouts: Set<String>, fonts: Set<String>, funboxes: Set<String> }
    struct Fixture: Decodable {
      let json: String?, flags: WebsiteConfigRuntimeContext, loaded: [String: WebsiteConfigValue]
      let writes: [String], disk: String?, requested: [String: WebsiteConfigValue], runtime: [String: WebsiteConfigValue]
      let rejectedKeys: [String], events: [WebsiteConfigApplicationEvent], pendingSync: [String: WebsiteConfigValue]
    }
    struct Output: Decodable { let defaults: [String: WebsiteConfigValue], catalogs: Catalogs, orderedKeys: [String], schemaOrderedKeys: [String], fixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", "--experimental-vm-modules", root.appendingPathComponent("Scripts/check-source-config-schema.mjs").path,
      reference, "--cold-storage"]
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let output = try JSONDecoder().decode(Output.self, from: data)
    XCTAssertEqual(output.fixtures.count, 230)
    XCTAssertEqual(WebsiteConfigRestoration.storageOrderedKeys, output.schemaOrderedKeys)
    let catalogs = WebsiteConfigCatalogs(languages: output.catalogs.languages, themes: output.catalogs.themes,
      layouts: output.catalogs.layouts, fonts: output.catalogs.fonts, funboxes: output.catalogs.funboxes)
    func text(_ key: String) throws -> String {
      guard case .string(let text) = output.defaults[key] else { throw WebsiteConfigSchemaError.invalidDefaults }; return text
    }
    guard case .array(let colors) = output.defaults["customThemeColors"] else { return XCTFail("Missing QA palette") }
    let document = try WebsiteConfigDefaultDocument(appearance: .init(theme: text("theme"), lightTheme: text("themeLight"),
      darkTheme: text("themeDark"), fontFamily: text("fontFamily"), customThemeColors: colors.map {
        guard case .string(let text) = $0 else { throw WebsiteConfigSchemaError.invalidDefaults }; return text
      }), catalogs: catalogs)
    XCTAssertEqual(document.orderedKeys, output.orderedKeys)
    func numberBits(_ actual: WebsiteConfigValue, _ expected: WebsiteConfigValue) {
      switch (actual, expected) {
      case (.number(let a), .number(let b)): XCTAssertEqual(a.bitPattern, b.bitPattern)
      case (.array(let a), .array(let b)): for (a, b) in zip(a, b) { numberBits(a, b) }
      default: break
      }
    }
    for (index, fixture) in output.fixtures.enumerated() {
      let result = try WebsiteConfigRestoration.prepareWebsiteStorage(fixture.json, defaultDocument: document,
        schema: .init(catalogs: catalogs), context: fixture.flags)
      XCTAssertEqual(result.loaded, fixture.loaded.mapValues(restore), "loaded \(index)")
      XCTAssertEqual(result.projection.requested, fixture.requested.mapValues(restore), "requested \(index)")
      XCTAssertEqual(result.projection.runtime, fixture.runtime.mapValues(restore), "runtime \(index)")
      for (key, value) in fixture.loaded { numberBits(try XCTUnwrap(result.loaded[key]), restore(value)) }
      for (key, value) in fixture.runtime { numberBits(try XCTUnwrap(result.projection.runtime[key]), restore(value)) }
      XCTAssertEqual(result.projection.rejectedKeys, fixture.rejectedKeys, "rejections \(index)")
      XCTAssertEqual(result.projection.events, fixture.events.map { event in
        var event = event; event.previousValue = event.previousValue.map(restore); event.newValue = event.newValue.map(restore); return event
      }, "events \(index)")
      let plan = try XCTUnwrap(result.websiteStorage)
      XCTAssertEqual(plan.pendingSync, fixture.pendingSync.mapValues(restore), "pending sync \(index)")
      XCTAssertEqual(plan.writes.count, fixture.writes.count, "writes \(index)")
      for (actual, expected) in zip(plan.writes, fixture.writes) {
        XCTAssertEqual(try WebsiteConfigJSONReader.read(actual), try WebsiteConfigJSONReader.read(expected), "write value \(index)")
      }
      if let actual = plan.after, let expected = fixture.disk {
        XCTAssertEqual(try WebsiteConfigJSONReader.read(actual), try WebsiteConfigJSONReader.read(expected), "disk \(index)")
        if plan.writes.isEmpty { XCTAssertEqual(actual, fixture.json, "Unchanged raw storage \(index)") }
      } else { XCTAssertEqual(plan.after, fixture.disk) }
    }
    print("Pinned cold storage/lifecycle fixtures: \(output.fixtures.count)")
  }

  private func restore(_ value: WebsiteConfigValue) -> WebsiteConfigValue {
    switch value {
    case .object(let fields):
      if case .array(let raw) = fields["$probeUTF16"] {
        return .string(units: raw.compactMap { if case .number(let number) = $0 { return UInt16(number) }; return nil })
      }
      if case .string(let number) = fields["$probeNumber"] {
        return .number(number == "Infinity" ? .infinity : number == "-Infinity" ? -.infinity : number == "-0" ? -0.0 : .nan)
      }
      return .object(fields.mapValues(restore))
    case .array(let values): return .array(values.map(restore))
    default: return value
    }
  }

  @MainActor
  func testStrictFullSchemaAndThrowingNumericCoercionDifferFromImport() throws {
    let document = try WebsiteConfigNativeProfile.defaultDocument()
    var withUnknown = document.values
    withUnknown["future"] = .number(123)
    let json = WebsiteConfigJSONWriter.write(.object(withUnknown))
    let restored = try WebsiteConfigNativeProfile.prepareWebsiteRestoration(json, context: .init())
    XCTAssertEqual(restored.websiteStorage?.disposition, .migrated)
    XCTAssertEqual(restored.websiteStorage?.writes.count, 1)
    for key in ["fontSize", "tapeMargin", "maxLineWidth"] {
      for value: WebsiteConfigValue in [.object(["toString": .number(0)]), .array([.object(["toString": .null])])] {
        let bad = WebsiteConfigJSONWriter.write(.object([key: value]))
        XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepare(bad, context: .init())) {
          XCTAssertEqual($0 as? WebsiteConfigSchemaError, .cannotCoerce)
        }
        let fallback = try WebsiteConfigNativeProfile.prepareWebsiteRestoration(bad, context: .init())
        XCTAssertEqual(fallback.websiteStorage?.disposition, .fallback)
        XCTAssertEqual(fallback.websiteStorage?.writes.count, 2)
        XCTAssertEqual(fallback.loaded, document.values)
      }
    }
    var nonASCII = document.values
    nonASCII["未知"] = .bool(true)
    let other = try WebsiteConfigNativeProfile.prepareWebsiteRestoration(WebsiteConfigJSONWriter.write(.object(nonASCII)), context: .init())
    XCTAssertEqual(other.websiteStorage?.disposition, .migrated)
  }

  @MainActor
  func testNativeRestoreRetainsOriginalBytesAndDoesNotForgeImportEvidence() throws {
    let suite = "typebar.restore.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let initial = try WebsiteConfigNativeProfile.prepare(#"{"paceCaret":"tagPb","randomTheme":"custom","customBackgroundFilter":[-0,1e400,1,1],"funbox":["rot13","rot13"],"quoteLength":[0,0,1]}"#,
      context: .init(authenticated: true, customThemeCount: 1)).projection.runtime
    let store = WebsiteConfigNativeStateStore(defaults: defaults)
    XCTAssertTrue(store.save(initial))
    let before = defaults.data(forKey: WebsiteConfigNativeStateStore.storageKey)
    guard case .prepared(let restored) = try WebsiteConfigNativeProfile.prepareNativeRestoration(store.read(), context: .init()) else {
      return XCTFail("Missing restored candidate")
    }
    XCTAssertEqual(restored.origin, .nativeState)
    XCTAssertNil(restored.websiteStorage)
    XCTAssertEqual(restored.loaded, initial)
    XCTAssertTrue(restored.projection.rejectedKeys.contains("randomTheme"))
    XCTAssertTrue(restored.projection.rejectedKeys.contains("paceCaret"))
    XCTAssertEqual(restored.projection.runtime["randomTheme"], .string("off"))
    XCTAssertEqual(restored.projection.runtime["paceCaret"], .string("custom"))
    let draft = try WebsiteConfigNativeDraft(restoration: restored, pointsPerRem: 16)
    XCTAssertNil(draft.prepared)
    guard case .restored = draft.origin else { return XCTFail("Forged import origin") }
    XCTAssertEqual(draft.generators.requestedModifiers, [.rot13, .rot13])
    XCTAssertEqual(draft.quoteSelection.groups, [0, 0, 1])
    XCTAssertEqual(draft.pagePreferences.backgroundFilter.blurRem.sign, .minus)
    XCTAssertEqual(draft.pagePreferences.backgroundFilter.brightness, .infinity)
    XCTAssertEqual(defaults.data(forKey: WebsiteConfigNativeStateStore.storageKey), before)
  }

  @MainActor
  func testMissingUnavailableUnrepresentableAndResourceBoundsDoNotRepairNativeState() throws {
    guard case .missing = try WebsiteConfigNativeProfile.prepareNativeRestoration(.missing, context: .init()) else { return XCTFail("Missing state defaulted") }
    guard case .unavailable = try WebsiteConfigNativeProfile.prepareNativeRestoration(.unavailable, context: .init()) else { return XCTFail("Opaque state defaulted") }
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareNativeRestoration(.available([:]), context: .init()))
    let initial = try WebsiteConfigNativeProfile.prepare(#"{"fontSize":1e400}"#, context: .init()).projection.runtime
    guard case .prepared(let result) = try WebsiteConfigNativeProfile.prepareNativeRestoration(.available(initial), context: .init()) else { return XCTFail("Lost native source") }
    XCTAssertEqual(result.loaded["fontSize"], .number(.infinity))
    XCTAssertThrowsError(try WebsiteConfigNativeDraft(restoration: result, pointsPerRem: 16))
    let missing = try WebsiteConfigNativeProfile.prepareWebsiteRestoration(nil, context: .init())
    XCTAssertEqual(missing.websiteStorage?.disposition, .missing)
    XCTAssertEqual(missing.websiteStorage?.writes.count, 1)
    XCTAssertTrue(missing.websiteStorage?.writes[0].hasPrefix("{\"punctuation\":") == true)
    let corrupt = try WebsiteConfigNativeProfile.prepareWebsiteRestoration("{", context: .init())
    XCTAssertEqual(corrupt.websiteStorage?.disposition, .fallback)
    XCTAssertEqual(corrupt.websiteStorage?.writes.count, 2)
    XCTAssertTrue(corrupt.websiteStorage?.writes[0].hasPrefix("{\"theme\":") == true)
    XCTAssertTrue(corrupt.websiteStorage?.writes[1].hasPrefix("{\"punctuation\":") == true)
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareWebsiteRestoration(String(repeating: " ", count: WebsiteConfigRestoration.maximumStorageBytes + 1), context: .init()))
    let deep = "{\"future\":" + String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130) + "}"
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareWebsiteRestoration(deep, context: .init()))
  }

  @MainActor
  func testColdLegacyAliasIsMigratedRatherThanPartialImportStripped() throws {
    let json = #"{"quickTab":true}"#
    let document = try WebsiteConfigNativeProfile.defaultDocument()
    let restored = try WebsiteConfigRestoration.prepareWebsiteStorage(json, defaultDocument: document,
      schema: .init(catalogs: WebsiteConfigNativeProfile.catalogs), context: .init())
    XCTAssertEqual(restored.loaded.count, 94)
    XCTAssertEqual(restored.projection.runtime["quickRestart"], .string("tab"))
    XCTAssertEqual(try WebsiteConfigNativeProfile.prepare(json, context: .init()).projection.runtime["quickRestart"], .string("off"))
    XCTAssertEqual(restored.websiteStorage?.disposition, .migrated)
    let draft = try WebsiteConfigNativeDraft(restoration: restored, pointsPerRem: 16)
    XCTAssertNil(draft.prepared)
    XCTAssertEqual(draft.behavior.quickRestartKey, .tab)
  }
}
