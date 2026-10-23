import XCTest
@testable import Typebar

final class WebsiteConfigNativeDraftTests: XCTestCase {
  @MainActor
  func testAll94FieldsHaveExactlyOneTypedOwnerAndFinalProjectionIsRetained() throws {
    let keys = WebsiteConfigSchema(catalogs: WebsiteConfigNativeProfile.catalogs).keys
    XCTAssertEqual(keys.count, 94)
    XCTAssertEqual(WebsiteConfigNativeDraft.mappedKeys, keys)
    XCTAssertEqual(WebsiteConfigNativeDraft.fieldGroups.reduce(0) { $0 + $1.count }, 94)
    let json = #"{"randomTheme":"custom","theme":"dracula","customTheme":true,"autoSwitchTheme":true,"funbox":["rot13","rot13"],"quoteLength":[0,0,1],"accountChart":["off","off","on","off"],"ads":"result","future":123}"#
    let prepared = try WebsiteConfigNativeProfile.prepare(json, context: .init())
    let draft = try WebsiteConfigNativeProfile.prepareDraft(json, pointsPerRem: 16, context: .init())
    XCTAssertEqual(draft.prepared.parsed, prepared.parsed)
    XCTAssertEqual(draft.prepared.projection.runtime, prepared.projection.runtime)
    XCTAssertEqual(draft.prepared.projection.events, prepared.projection.events)
    XCTAssertEqual(draft.prepared.projection.rejectedKeys, prepared.projection.rejectedKeys)
    XCTAssertFalse(draft.prepared.parsed.keys.contains("future"))
    XCTAssertTrue(draft.prepared.projection.rejectedKeys.contains("randomTheme"))
    XCTAssertEqual(draft.themes.randomMode, .off)
    XCTAssertEqual(draft.themes.theme, .dracula)
    XCTAssertTrue(draft.themes.customEnabled)
    XCTAssertTrue(draft.themes.followsSystem)
    XCTAssertEqual(draft.quoteSelection.groups, [0, 0, 1])
    XCTAssertEqual(draft.generators.requestedModifiers, [.rot13, .rot13])
    XCTAssertEqual(draft.pagePreferences.advertisingPreference, .result)
    XCTAssertTrue(draft.pagePreferences.accountChart.accuracy)
    XCTAssertFalse(draft.pagePreferences.accountChart.speed)
    XCTAssertNoThrow(try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 14, context: .init()))
  }

  @MainActor
  func testIncompleteOrUnrepresentableDraftFailsWithoutLegacyFallback() throws {
    var prepared = try WebsiteConfigNativeProfile.prepare("{}", context: .init())
    prepared.projection.runtime.removeValue(forKey: "ads")
    XCTAssertThrowsError(try WebsiteConfigNativeDraft(prepared: prepared, pointsPerRem: 16))
    prepared = try WebsiteConfigNativeProfile.prepare("{}", context: .init())
    prepared.projection.runtime["unexpected"] = .bool(true)
    XCTAssertThrowsError(try WebsiteConfigNativeDraft(prepared: prepared, pointsPerRem: 16))
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareDraft(#"{"paceCaretCustomSpeed":1e400}"#, pointsPerRem: 16, context: .init())) {
      XCTAssertEqual($0 as? WebsiteConfigNativeBehaviorError, .unrepresentableField("paceCaretCustomSpeed"))
    }
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareDraft(#"{"words":9007199254740992}"#, pointsPerRem: 16, context: .init())) {
      XCTAssertEqual($0 as? WebsiteConfigNativeTestParametersError, .unrepresentableField("words"))
    }
    XCTAssertThrowsError(try WebsiteConfigNativeProfile.prepareDraft("{}", pointsPerRem: 0, context: .init()))
    let filter = try WebsiteConfigNativeProfile.prepareDraft(#"{"customBackgroundFilter":[-0,1e400,-2,5]}"#, pointsPerRem: 16, context: .init()).pagePreferences.backgroundFilter
    XCTAssertEqual(filter.blurRem.sign, .minus)
    XCTAssertEqual(filter.brightness, .infinity)
    XCTAssertEqual(filter.saturation, -2)
    XCTAssertEqual(filter.opacity, 5)
  }
}
