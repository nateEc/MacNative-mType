import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PublicProfilePersonalBestRenderingTests: XCTestCase {
  private func profile(empty: Bool = false, maximum: Bool = false, legacy: Bool = false) throws -> RemotePublicProfile {
    var rows: [[String: Any]] = empty ? [] : [("time", [15, 30, 60, 120]), ("words", [10, 25, 50, 100])].flatMap { mode, parameters in
      parameters.map { parameter in
        ["id": UUID().uuidString, "mode": mode, "mode2": String(parameter),
          mode == "time" ? "durationSeconds" : "wordLimit": parameter,
          "language": "english", "wpm": maximum ? 420 : 60,
          "preciseWpm": maximum ? 420.0 : 60.49, "rawWpm": maximum ? 420 : 120,
          "preciseRawWpm": maximum ? 420.0 : 120.0,
          "accuracy": 99, "preciseAccuracy": 98.75, "consistency": 80.25,
          "finishedAt": 100, "acceptedAtMilliseconds": 1_800_000_000_875,
          "personalBestOrigin": "accepted", "personalBestConfiguration": ["version": 1,
            "difficulty": "expert", "punctuation": true, "numbers": false, "lazyMode": true]]
      }
    }
    var root: [String: Any] = ["id": UUID().uuidString, "displayName": "Owned render profile",
      "joinedAt": 0, "completedResultCount": 0, "bestWPM": 0, "personalBests": [],
      "personalBestLedgerVersion": 1, "personalBestHistoryComplete": true, "personalBestSnapshots": rows]
    if legacy {
      for index in rows.indices {
        for key in ["mode2", "rawWpm", "preciseRawWpm", "personalBestConfiguration", "acceptedAtMilliseconds", "personalBestOrigin"] { rows[index].removeValue(forKey: key) }
      }
      rows[0].removeValue(forKey: "durationSeconds")
      rows[0]["language"] = "owned long language label for layout only"
      for key in ["personalBestLedgerVersion", "personalBestHistoryComplete", "personalBestSnapshots"] { root.removeValue(forKey: key) }
      root["personalBests"] = rows
    }
    return try JSONDecoder().decode(RemotePublicProfile.self, from: JSONSerialization.data(withJSONObject: root))
  }

  private func settle(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    view.layoutSubtreeIfNeeded()
  }

  private func withSettings(_ body: (AppSettings) throws -> Void) throws {
    let suite = "TypebarTests.profile-render.\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}))
    try body(settings)
  }
  private func withMount(_ body: (NSWindow, NSHostingView<AnyView>) throws -> Void) throws {
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 420, height: 900),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try body(window, host)
  }
  private func root(_ content: some View, width: CGFloat = 420, padding: CGFloat = 32, dark: Bool = false) -> AnyView {
    AnyView(content.padding(padding).frame(width: width, alignment: .topLeading)
      .fixedSize(horizontal: false, vertical: true)
      .environment(\.colorScheme, dark ? .dark : .light)
      .background(Color(nsColor: .windowBackgroundColor)))
  }
  private func snapshot(_ host: NSHostingView<AnyView>, window: NSWindow, name: String, width: CGFloat = 420, dark: Bool = false) throws -> Data {
    settle(host)
    let fit = host.fittingSize
    XCTAssertEqual(fit.width, width, accuracy: 1)
    XCTAssertGreaterThan(fit.height, 20); XCTAssertLessThan(fit.height, 3000)
    window.setContentSize(.init(width: width, height: ceil(fit.height)))
    settle(host)
    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    XCTAssertFalse(window.isVisible)
    XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, Int(width))
    let background = try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)?.usingColorSpace(.deviceRGB))
    XCTAssertEqual(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), dark ? .darkAqua : .aqua,
      "AppKit appearance must match the SwiftUI color scheme")
    let backgroundBrightness = (background.redComponent + background.greenComponent + background.blueComponent) / 3
    if dark { XCTAssertLessThan(backgroundBrightness, 0.3) }
    else { XCTAssertGreaterThan(backgroundBrightness, 0.7) }
    var ink = 0, samples = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
      for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
        samples += 1
        if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
          max(abs(pixel.redComponent - background.redComponent), abs(pixel.greenComponent - background.greenComponent),
            abs(pixel.blueComponent - background.blueComponent)) > 0.06 { ink += 1 }
      }
    }
    XCTAssertGreaterThan(Double(ink) / Double(max(1, samples)), 0.001, "Must draw actual content, not only a solid background")
    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    print("PROFILE RENDER \(name) size=\(host.bounds.size) ink=\(ink)/\(samples)")
    if let directory = ProcessInfo.processInfo.environment["TYPEBAR_PROFILE_PB_QA_IMAGE_DIRECTORY"] {
      try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
    }
    return png
  }

  func testMountedProductionSummaryRendersInOneNeverVisibleWindow() throws {
    try withSettings { settings in try withMount { window, host in
      for (name, empty, maximum, dark) in [("normal-light", false, false, false),
        ("maximum-wph-dark", false, true, true), ("empty-light", true, false, false)] {
        settings.typingSpeedUnit = maximum ? .wph : .wpm
        settings.alwaysShowDecimalPlaces = maximum
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(PublicProfilePersonalBestsView(profile: try profile(empty: empty, maximum: maximum), settings: settings), dark: dark)
        _ = try snapshot(host, window: window, name: name, dark: dark)
        XCTAssertGreaterThan(host.bounds.height, 500)
      }
    } }
  }

  func testSameMountedSummaryObservesUnitChangesWhilePrimaryValuesStayInteger() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      let profile = try profile(), encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      let before = try encoder.encode(profile)
      host.rootView = root(PublicProfilePersonalBestsView(profile: profile, settings: settings))
      let original = try snapshot(host, window: window, name: "live-wpm")
      settings.alwaysShowDecimalPlaces = true
      XCTAssertEqual(try snapshot(host, window: window, name: "live-wpm-decimals"), original)
      settings.typingSpeedUnit = .cpm
      XCTAssertNotEqual(try snapshot(host, window: window, name: "live-cpm"), original)
      settings.typingSpeedUnit = .wpm
      XCTAssertEqual(try snapshot(host, window: window, name: "live-restored"), original)
      XCTAssertEqual(try encoder.encode(profile), before)
    } }
  }

  func testSameMountedProductionDetailsObserveDecimalsAndUnitWithoutRebuildingTheView() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      let best = try XCTUnwrap(try profile().displayPersonalBests.first)
      host.rootView = root(PublicProfilePersonalBestDetails(best: best, settings: settings))
      let original = try snapshot(host, window: window, name: "detail-wpm")
      settings.alwaysShowDecimalPlaces = true
      XCTAssertNotEqual(try snapshot(host, window: window, name: "detail-decimals"), original)
      settings.typingSpeedUnit = .cps
      XCTAssertNotEqual(try snapshot(host, window: window, name: "detail-cps"), original)
      settings.typingSpeedUnit = .wpm; settings.alwaysShowDecimalPlaces = false
      XCTAssertEqual(try snapshot(host, window: window, name: "detail-restored"), original)
    } }
  }

  func testProductionDetailsRenderAtNarrowCardWidthWithMaximumAndUnknownLegacyFields() throws {
    try withSettings { settings in try withMount { window, host in
      settings.typingSpeedUnit = .wph; settings.alwaysShowDecimalPlaces = true
      for (name, legacy, dark) in [("narrow-maximum-dark", false, true), ("narrow-legacy-light", true, false)] {
        let best = try XCTUnwrap(try profile(maximum: !legacy, legacy: legacy).displayPersonalBests.first)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.rootView = root(VStack(alignment: .leading) {
          Text(best.configurationLabel).font(.subheadline.weight(.medium))
          PublicProfilePersonalBestDetails(best: best, settings: settings)
        }, width: 168, padding: 12, dark: dark)
        _ = try snapshot(host, window: window, name: name, width: 168, dark: dark)
        XCTAssertGreaterThan(host.bounds.height, 80)
      }
    } }
  }
}
