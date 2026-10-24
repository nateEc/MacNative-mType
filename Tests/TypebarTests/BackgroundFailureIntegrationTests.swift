import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class BackgroundFailureIntegrationTests: XCTestCase {
  private func settle() async { for _ in 0..<40 { await Task.yield() } }
  private func data() throws -> Data {
    let image = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data([255, 0, 0, 255]) as CFData)!,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination)); return data as Data
  }

  func testLocalRemoteAndQuotaFailuresPostSanitizedNotices() async throws {
    let center = LocalNoticeCenter()
    let secret = NSError(domain: NSURLErrorDomain, code: -1003,
      userInfo: [NSLocalizedDescriptionKey: "https://private.invalid/?token=secret /private/user/photo"])
    let loader = CustomBackgroundImageLoader { _, _ in throw secret }
    defer { loader.clear(); center.clearAll() }
    await loader.load(remoteURL: "https://private.invalid/image.png?token=secret", local: { nil },
      onFailure: center.backgroundFailureSink())
    await settle()
    XCTAssertEqual(center.history.map(\.message), [BackgroundFailureFeedback.Kind.remote.message])
    await loader.load(remoteURL: "https://private.invalid/image.png", local: { throw secret },
      onFailure: center.backgroundFailureSink())
    await settle()
    await loader.load(remoteURL: "", maximumBytes: 1, local: { Data([1, 2]) },
      onFailure: center.backgroundFailureSink())
    await settle()
    let expected: [BackgroundFailureFeedback.Kind] = [.remote, .local, .resourceLimit]
    XCTAssertEqual(center.history.map(\.message), expected.map(\.message))
    XCTAssertTrue(center.history.allSatisfy { !$0.message.contains("secret") && !$0.message.contains("/private") && $0.details == nil })
    XCTAssertTrue(center.active.allSatisfy { $0.durationMilliseconds == 5000 && $0.entry.level == .notice })
  }

  func testCancelledAndSupersededFailuresNeverReachNoticeHistory() async throws {
    let center = LocalNoticeCenter(), valid = try data()
    var pending: CheckedContinuation<Data, Error>?
    let loader = CustomBackgroundImageLoader { _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
    defer { loader.clear(); center.clearAll() }
    let old = Task { await loader.load(remoteURL: "https://example.invalid/old.png", local: { nil },
      onFailure: center.backgroundFailureSink()) }
    await settle()
    guard let first = pending else { old.cancel(); return XCTFail("No suspended old request") }
    await loader.load(remoteURL: "", local: { valid }, onFailure: center.backgroundFailureSink())
    first.resume(throwing: URLError(.badServerResponse)); await old.value; await settle()
    XCTAssertTrue(center.history.isEmpty); XCTAssertEqual(loader.state, .ready)
    pending = nil
    let cancelled = Task { await loader.load(remoteURL: "https://example.invalid/cancelled.png", local: { nil },
      onFailure: center.backgroundFailureSink()) }
    await settle()
    guard let second = pending else { cancelled.cancel(); return XCTFail("No suspended cancellation") }
    cancelled.cancel(); second.resume(throwing: URLError(.cancelled)); await cancelled.value; await settle()
    XCTAssertTrue(center.history.isEmpty); XCTAssertEqual(loader.state, .empty)
    await loader.load(remoteURL: "", local: { Data() }, onFailure: center.backgroundFailureSink())
    loader.clear(); await settle()
    XCTAssertTrue(center.history.isEmpty, "Removing a failed image before queued delivery must retire the notice")
  }

  func testSurfaceStopRecoveryAndRepeatedLayoutDoNotPostStaleOrDuplicateFailures() async throws {
    let center = LocalNoticeCenter(), loader = CustomBackgroundImageLoader(), valid = try data()
    defer { center.clearAll(); loader.clear() }
    await loader.load(remoteURL: "", local: { valid }, onFailure: center.backgroundFailureSink())
    let image = try XCTUnwrap(loader.nativeImage)
    let view = WebsiteConfigBackgroundSurfaceView(limits: .init(pixels: 1))
    defer { view.stop() }
    let filter = WebsiteConfigNativePagePreferences.BackgroundFilter(blurRem: 0, brightness: 1, saturation: 1, opacity: 1)
    func configure() {
      view.configure(image: image, identity: loader.imageIdentity, fit: .max, filter: filter, feedback: loader.feedback)
    }
    view.setFrameSize(CGSize(width: 2, height: 2)); configure(); view.stop()
    await settle(); XCTAssertTrue(center.history.isEmpty)
    // Same image ID after stop must use a new surface lifetime, not the retired validator.
    configure(); view.setFrameSize(CGSize(width: 1, height: 1))
    await settle(); XCTAssertTrue(center.history.isEmpty, "Recovered before delivery")
    view.setFrameSize(CGSize(width: 2, height: 2)); await settle()
    XCTAssertEqual(center.history.map(\.message), [BackgroundFailureFeedback.Kind.render.message])
    for size in 3...20 { view.setFrameSize(CGSize(width: size, height: size)); view.layoutSubtreeIfNeeded() }
    await settle(); XCTAssertEqual(center.history.count, 1)
  }

  func testActualHiddenProductionHostPostsOnceAndExplicitNewLoadCanNotifyAgain() async throws {
    let center = LocalNoticeCenter(), store = TypebarLocalBackgroundStore.inMemory()
    var requests = 0
    let loader = CustomBackgroundImageLoader { _, _ in requests += 1; throw URLError(.cannotFindHost) }
    func root(revision: Int = 0, fit: CustomBackgroundFit = .cover) -> AnyView {
      AnyView(CustomPracticeBackground(fallbackStyle: .solid,
        theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light),
        reduceMotion: true, remoteURL: "https://example.invalid/image.png", fit: fit, filter: .init(),
        localImageRevision: revision, localBackgroundStore: store, loader: loader,
        onFailure: center.backgroundFailureSink()).frame(width: 80, height: 40))
    }
    let host = NSHostingView(rootView: root())
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close(); loader.clear(); center.clearAll() }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where center.history.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 1); XCTAssertEqual(center.history.count, 1)
    host.rootView = root(fit: .contain); host.layoutSubtreeIfNeeded(); await settle()
    XCTAssertEqual(requests, 1); XCTAssertEqual(center.history.count, 1)
    host.rootView = root(revision: 1); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where center.history.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 2); XCTAssertEqual(center.history.count, 2)
    XCTAssertFalse(window.isVisible)
  }

  func testActualRepresentableRenderFailureReachesExistingNoticeStack() async throws {
    let center = LocalNoticeCenter(), store = TypebarLocalBackgroundStore.inMemory(), loader = CustomBackgroundImageLoader()
    try store.save(data())
    let background = CustomPracticeBackground(fallbackStyle: .solid,
      theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light),
      reduceMotion: true, remoteURL: "", fit: .max, filter: .init(blur: 20), localImageRevision: 0,
      localBackgroundStore: store, loader: loader, onFailure: center.backgroundFailureSink())
    let host = NSHostingView(rootView: AnyView(background.overlay(alignment: .topTrailing) {
      LocalNoticeStack(center: center, focused: false)
    }.frame(width: 80, height: 40)))
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close(); loader.clear(); center.clearAll() }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where center.history.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(loader.state, .ready, "The failure must come from rendering, not loading")
    XCTAssertEqual(center.history.map(\.message), [BackgroundFailureFeedback.Kind.render.message])
    for _ in 0..<10 { host.layoutSubtreeIfNeeded(); await settle() }
    XCTAssertEqual(center.history.count, 1)
    XCTAssertFalse(window.isVisible)
  }
}
