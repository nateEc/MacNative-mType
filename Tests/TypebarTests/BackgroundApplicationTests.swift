import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class BackgroundApplicationTests: XCTestCase {
  private let address = "https://example.invalid/same.png"
  func testNativeSettingsSlidersKeepLegacyBoundsAndImmediatePersistence() throws {
    try withSettings { settings, _ in
      settings.customBackgroundURL = address
      let model = BackgroundSettingsPreferences(settings: settings)
      XCTAssertNil(model.source); XCTAssertEqual(model.target, .native)
      XCTAssertEqual(model.range(0), 0...20); XCTAssertEqual(model.range(2), 0...3)
      XCTAssertEqual(model.step(0), 0.5); XCTAssertEqual(model.step(2), 0.05)
      let identity = settings.customBackgroundApplicationID
      XCTAssertTrue(model.input(component: 0, value: 8.5)); XCTAssertTrue(model.commit(component: 0, value: 8.5))
      XCTAssertEqual(settings.customBackgroundFilter.blur, 8.5)
      XCTAssertEqual(settings.customBackgroundApplicationID, identity)
      XCTAssertTrue(CustomBackgroundCommandEditorPolicy.apply("", kind: .remoteURL, to: settings))
      XCTAssertEqual(settings.customBackgroundURL, ""); XCTAssertFalse(model.filtersVisible)
    }
  }
  private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) rethrows {
    let suite = "typebar.background-application.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory())
    try body(settings, defaults)
  }
  private func settle() async { for _ in 0..<40 { await Task.yield() } }

  func testRepeatedURLAssignmentsAndABAAreDistinctApplications() {
    withSettings { settings, _ in
      let initial = settings.customBackgroundApplicationID
      let selection = settings.activeTestSelectionGeneration, wrapper = settings.practiceWrapperRevision
      settings.customBackgroundURL = address
      let first = settings.customBackgroundApplicationID, snapshot = settings.snapshot
      XCTAssertNotEqual(first, initial)
      settings.customBackgroundURL = address
      let repeated = settings.customBackgroundApplicationID
      XCTAssertNotEqual(repeated, first); XCTAssertEqual(settings.snapshot, snapshot)
      settings.customBackgroundURL = ""
      let removed = settings.customBackgroundApplicationID
      settings.customBackgroundURL = address
      XCTAssertNotEqual(settings.customBackgroundApplicationID, removed)
      XCTAssertNotEqual(settings.customBackgroundApplicationID, repeated)
      XCTAssertEqual(settings.activeTestSelectionGeneration, selection)
      XCTAssertEqual(settings.practiceWrapperRevision, wrapper)
    }
  }

  func testCommandConfirmationAdvancesBeforeSaveButRejectedInputDoesNot() {
    withSettings { settings, _ in
      settings.customBackgroundURL = address
      let first = settings.customBackgroundApplicationID
      var saves = 0
      XCTAssertTrue(CustomBackgroundCommandEditorPolicy.apply(address, kind: .remoteURL, to: settings,
        onConfigurationSave: {
          saves += 1; XCTAssertNotEqual(settings.customBackgroundApplicationID, first)
        }))
      let confirmed = settings.customBackgroundApplicationID
      XCTAssertFalse(CustomBackgroundCommandEditorPolicy.apply("ftp://example.invalid/image.png", kind: .remoteURL,
        to: settings, onConfigurationSave: { saves += 1 }))
      XCTAssertEqual(settings.customBackgroundApplicationID, confirmed); XCTAssertEqual(saves, 1)
    }
  }

  func testFullSnapshotReappliesOnceWhileRejectedSnapshotCannotAdvance() {
    withSettings { settings, _ in
      settings.customBackgroundURL = address
      let snapshot = settings.snapshot, before = settings.customBackgroundApplicationID
      XCTAssertTrue(settings.apply(snapshot))
      XCTAssertNotEqual(settings.customBackgroundApplicationID, before)
      XCTAssertEqual(settings.snapshot, snapshot)
      let applied = settings.customBackgroundApplicationID
      var rejected = snapshot; rejected.keyboardGuideLayoutSource = .websiteEmulation
      XCTAssertFalse(settings.apply(rejected)); XCTAssertEqual(settings.customBackgroundApplicationID, applied)
      XCTAssertEqual(settings.snapshot, snapshot)
    }
  }

  func testStyleUpdatesAndReadsDoNotCreateNewImageApplications() {
    withSettings { settings, _ in
      settings.customBackgroundURL = address
      let identity = settings.customBackgroundApplicationID
      settings.customBackgroundFit = .contain
      settings.customBackgroundFilter = .init(blur: 0.5, brightness: 1.5)
      settings.practiceBackdrop = .grid
      _ = settings.snapshot; _ = settings.customBackgroundURL
      XCTAssertEqual(settings.customBackgroundApplicationID, identity)
    }
  }

  func testNormalizationStillPublishesTheFinalApplication() {
    withSettings { settings, _ in
      let before = settings.customBackgroundApplicationID
      settings.customBackgroundURL = " \n" + address + "\n "
      XCTAssertEqual(settings.customBackgroundURL, address)
      XCTAssertNotEqual(settings.customBackgroundApplicationID, before)
    }
  }

  func testApplicationIdentityIsNotArchivedAndColdRestoreGetsItsOwnLifetime() throws {
    try withSettings { settings, defaults in
      settings.customBackgroundURL = address
      let snapshot = settings.snapshot, identity = settings.customBackgroundApplicationID
      let encoded = try JSONEncoder().encode(snapshot)
      let text = String(decoding: encoded, as: UTF8.self)
      XCTAssertFalse(text.contains("customBackgroundApplicationID")); XCTAssertFalse(text.contains(identity.uuidString))
      let restored = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
        localBackgroundStore: .inMemory())
      XCTAssertEqual(restored.customBackgroundURL, address)
      XCTAssertNotEqual(restored.customBackgroundApplicationID, identity)
      XCTAssertEqual(restored.snapshot, snapshot)
    }
  }

  func testActualHiddenHostRetriesSameURLButStyleUpdatesDoNotReload() async throws {
    let center = LocalNoticeCenter(), store = TypebarLocalBackgroundStore.inMemory()
    var requests = 0
    let loader = CustomBackgroundImageLoader { _, _ in requests += 1; throw URLError(.cannotFindHost) }
    func root(_ applicationID: UUID, fit: CustomBackgroundFit = .cover) -> AnyView {
      AnyView(CustomPracticeBackground(fallbackStyle: .solid,
        theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light), reduceMotion: true,
        remoteURL: address, fit: fit, filter: .init(), localImageRevision: 0, localBackgroundStore: store,
        loader: loader, onFailure: center.backgroundFailureSink(), applicationID: applicationID)
        .frame(width: 80, height: 40))
    }
    let first = UUID()
    let host = NSHostingView(rootView: root(first))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close(); loader.clear(); center.clearAll() }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where center.history.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 1); XCTAssertEqual(center.history.count, 1)
    let loaded = loader.imageIdentity
    host.rootView = root(first, fit: .contain); host.layoutSubtreeIfNeeded(); await settle()
    XCTAssertEqual(requests, 1); XCTAssertEqual(loader.imageIdentity, loaded)
    host.rootView = root(UUID(), fit: .contain); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where center.history.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 2); XCTAssertEqual(center.history.count, 2)
    XCTAssertNotEqual(loader.imageIdentity, loaded)
    XCTAssertFalse(window.isVisible)
  }

  private struct SettingsBackground: View {
    let settings: AppSettings
    let loader: CustomBackgroundImageLoader
    var body: some View {
      CustomPracticeBackground(fallbackStyle: .solid,
        theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light),
        reduceMotion: true, remoteURL: settings.customBackgroundURL, fit: settings.customBackgroundFit,
        filter: settings.customBackgroundFilter, localImageRevision: settings.localBackgroundRevision,
        localBackgroundStore: settings.localBackgroundStore, loader: loader,
        applicationID: settings.customBackgroundApplicationID).frame(width: 80, height: 40)
    }
  }

  func testActualSettingsObservationReappliesLocalImageWithoutRequestingRemote() async throws {
    let suite = "typebar.background-bound-host.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults, feedbackSound: .init(loadSound: { _ in nil }, beep: {}),
      localBackgroundStore: .inMemory())
    let cgImage = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, cgImage, nil); XCTAssertTrue(CGImageDestinationFinalize(encoder))
    let data = output as Data
    try settings.importLocalBackground(data: data)
    settings.customBackgroundURL = address
    var remoteRequests = 0
    let loader = CustomBackgroundImageLoader { _, _ in remoteRequests += 1; throw URLError(.cannotFindHost) }
    let host = NSHostingView(rootView: AnyView(SettingsBackground(settings: settings, loader: loader)))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close(); loader.clear() }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where loader.state != .ready { try await Task.sleep(for: .milliseconds(10)) }
    let first = loader.imageIdentity, selection = settings.activeTestSelectionGeneration
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(remoteRequests, 0)
    settings.customBackgroundURL = address
    for _ in 0..<100 where loader.imageIdentity == first { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertNotEqual(loader.imageIdentity, first)
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(loader.encodedData, data)
    XCTAssertEqual(remoteRequests, 0); XCTAssertEqual(settings.activeTestSelectionGeneration, selection)
    let reapplied = loader.imageIdentity
    settings.customBackgroundFit = .contain
    host.layoutSubtreeIfNeeded(); await settle()
    XCTAssertEqual(loader.imageIdentity, reapplied)
    XCTAssertEqual(remoteRequests, 0); XCTAssertFalse(window.isVisible)
  }
}
