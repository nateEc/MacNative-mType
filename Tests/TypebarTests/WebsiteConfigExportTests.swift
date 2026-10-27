import XCTest
@testable import Typebar

@MainActor final class WebsiteConfigExportTests: XCTestCase {
  func testBothSourceSnapshotsSurviveFullImportsAndEverySingleDefaultSetter() throws {
    let fixtures = try WebsiteConfigExportSourceOracle.load()
    XCTAssertEqual(fixtures.count, 216)
    let order = try WebsiteConfigNativeProfile.defaultDocument().orderedKeys
    let schema = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs)
    for fixture in fixtures where !fixture.failure {
      let defaults = try XCTUnwrap(WebsiteConfigJSONReader.read(fixture.initialJSON).importFields)
      func prepare(_ json: String) throws -> WebsiteConfigNativeDraft {
        try .init(prepared: WebsiteConfigImportPreparation.prepare(json, defaults: defaults, orderedKeys: order,
          schema: schema, context: .init()), pointsPerRem: 16)
      }
      var draft = try prepare(fixture.initialJSON)
      for step in fixture.steps {
        if step.kind == "failed-full" {
          XCTAssertThrowsError(try prepare(step.json))
          continue
        }
        if step.kind == "full" { draft = try prepare(step.json) }
        else {
          let key = try XCTUnwrap(step.key), value = try WebsiteConfigJSONReader.read(step.json)
          let projection = try WebsiteConfigRuntimeProjector.edit(current: draft.projection.runtime,
            key: key, value: value, defaults: defaults, schema: schema, context: .init(), testActive: step.active)
          if projection.rejectedKeys.isEmpty {
            var next = try WebsiteConfigNativeDraft(edit: .init(key: key, previousRuntime: draft.projection.runtime,
              projection: projection, previousStore: draft.settingsStoreValues), pointsPerRem: 16)
            next.lazyMemory = draft.lazyMemory
            draft = next
          }
        }
        draft = try WebsiteConfigLazyModeLifecycle.applyingEvents(draft, pointsPerRem: 16)
      }
      for (surface, expectedJSON) in [(WebsiteConfigExport.Surface.command, fixture.commandJSON), (.settings, fixture.settingsJSON)] {
        let expected = try XCTUnwrap(WebsiteConfigJSONReader.read(expectedJSON).importFields)
        let json = try WebsiteConfigExport.json(draft, surface: surface)
        let actual = try XCTUnwrap(WebsiteConfigJSONReader.read(json).importFields)
        XCTAssertEqual(actual.keys.sorted(), expected.keys.sorted())
        for key in expected.keys { XCTAssertEqual(actual[key], expected[key], "\(fixture.label)/\(surface)/\(key)") }
        XCTAssertTrue(json.utf8.elementsEqual(expectedJSON.utf8),
          "Source JSON text: \(fixture.label)/\(surface)")
      }
    }
  }

  func testProductionEditAndFunboxSelectionPreserveUnrelatedSettingsStoreDifferences() throws {
    let draft = try WebsiteConfigNativeProfile.prepareDraft(
      #"{"keymapSize":1.4000000000000001,"paceCaret":"pb","randomTheme":"custom","tapeMode":"letter","showAllLines":true}"#,
      pointsPerRem: 16, context: .init())
    let edited = try WebsiteConfigNativeProfile.editDraft(draft, key: "words", value: .number(17),
      pointsPerRem: 16, context: .init())
    let selected = try WebsiteConfigFunboxMemory.selecting(.array([]), from: edited,
      pointsPerRem: 16, context: .init(), testActive: false).draft
    for candidate in [edited, selected] {
      for key in ["keymapSize", "paceCaret", "randomTheme", "showAllLines"] {
        XCTAssertEqual(candidate.settingsStoreValues[key], draft.settingsStoreValues[key], key)
        XCTAssertEqual(candidate.projection.runtime[key], draft.projection.runtime[key], key)
      }
      XCTAssertEqual(candidate.settingsStoreValues["words"], .number(17))
    }
  }
}
