import AppKit
import Darwin
import Foundation
import SwiftUI
import XCTest
@testable import Typebar

@MainActor
final class CustomBackgroundImageLoaderTests: XCTestCase {
  private func imageData() throws -> Data {
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
    bitmap.setColor(.red, atX: 0, y: 0); bitmap.setColor(.blue, atX: 1, y: 0)
    return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
  }
  private func settle() async { for _ in 0..<40 { await Task.yield() } }

  func testPresentLocalDataWinsAndOriginalBytesRemainAvailable() async throws {
    let data = try imageData()
    let store = TypebarLocalBackgroundStore.inMemory()
    try store.save(data)
    XCTAssertEqual(try store.encodedData(), data)
    var requests = 0
    let loader = CustomBackgroundImageLoader { _, _ in requests += 1; return data }
    await loader.load(remoteURL: "https://example.invalid/remote.png", local: { try store.encodedData() })
    XCTAssertEqual(requests, 0); XCTAssertEqual(loader.state, .ready)
    XCTAssertEqual(loader.encodedData, data); XCTAssertNotNil(loader.image)
    loader.clear()
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.image); XCTAssertNil(loader.encodedData)
  }

  func testCorruptOrUnreadableLocalNeverFallsThroughToRemote() async throws {
    var requests = 0
    let loader = CustomBackgroundImageLoader { _, _ in requests += 1; return try self.imageData() }
    for data in [Data(), Data("invalid".utf8)] {
      await loader.load(remoteURL: "https://example.invalid/remote.png", local: { data })
      XCTAssertEqual(loader.state, .failed); XCTAssertNotNil(loader.error)
      XCTAssertNil(loader.image); XCTAssertNil(loader.encodedData)
    }
    await loader.load(remoteURL: "https://example.invalid/remote.png", local: { throw CocoaError(.fileReadNoPermission) })
    XCTAssertEqual(loader.state, .failed); XCTAssertEqual(requests, 0)
  }

  func testAbsentLocalDownloadsOnceWhileEmptyAddressClearsWithoutRequest() async throws {
    let data = try imageData()
    var addresses: [URL] = []
    let loader = CustomBackgroundImageLoader { url, _ in addresses.append(url); return data }
    await loader.load(remoteURL: "https://example.invalid/image.png", local: { nil })
    XCTAssertEqual(addresses.map(\.absoluteString), ["https://example.invalid/image.png"])
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(loader.encodedData, data)
    await loader.load(remoteURL: "", local: { nil })
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.image)
    XCTAssertEqual(addresses.count, 1)
  }

  func testOldSuccessAndFailureCannotPublishOverReplacementOrClear() async throws {
    let data = try imageData()
    var pending: [CheckedContinuation<Data, Error>] = []
    let loader = CustomBackgroundImageLoader { _, _ in
      try await withCheckedThrowingContinuation { pending.append($0) }
    }
    let old = Task { await loader.load(remoteURL: "https://example.invalid/old.png", local: { nil }) }
    await settle()
    guard pending.count == 1 else { old.cancel(); return XCTFail("No suspended download") }
    await loader.load(remoteURL: "", local: { data })
    pending.removeFirst().resume(returning: Data("old corrupt response".utf8)); await old.value
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(loader.encodedData, data)
    let stale = Task { await loader.load(remoteURL: "https://example.invalid/old.png", local: { nil }) }
    await settle()
    guard pending.count == 1 else { stale.cancel(); return XCTFail("No suspended download") }
    loader.clear()
    pending.removeFirst().resume(throwing: CocoaError(.fileReadUnknown)); await stale.value
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.error)
  }

  func testCancelledLoadCannotPublishEvenIfDownloaderIgnoresCancellation() async throws {
    let data = try imageData()
    var pending: CheckedContinuation<Data, Error>?
    let loader = CustomBackgroundImageLoader { _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
    let task = Task { await loader.load(remoteURL: "https://example.invalid/image.png", local: { nil }) }
    await settle()
    guard let continuation = pending else { task.cancel(); return XCTFail("No wait") }
    task.cancel(); continuation.resume(returning: data); await task.value
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.image); XCTAssertNil(loader.error)
  }

  func testLocalAndInjectedRemoteLimitsAndStoreIsolation() async throws {
    let data = try imageData()
    let first = TypebarLocalBackgroundStore.inMemory(), second = TypebarLocalBackgroundStore.inMemory()
    try first.save(data)
    XCTAssertNil(try second.encodedData())
    XCTAssertThrowsError(try first.encodedData(maximumBytes: data.count - 1))
    XCTAssertThrowsError(try first.encodedData(maximumBytes: 0))
    let loader = CustomBackgroundImageLoader { _, _ in data }
    await loader.load(remoteURL: "https://example.invalid/image.png", maximumBytes: data.count - 1, local: { nil })
    XCTAssertEqual(loader.state, .failed); XCTAssertNil(loader.image)
    await loader.load(remoteURL: "", maximumBytes: data.count - 1, local: { data })
    XCTAssertEqual(loader.state, .failed)
    XCTAssertEqual(try first.encodedData(), data)
  }

  func testDiskSnapshotsAreBoundedAndRejectLinksDirectoriesAndFIFO() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-load-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TypebarLocalBackgroundStore(directoryURL: root)
    XCTAssertNil(try store.encodedData())
    let data = try imageData()
    try store.save(data)
    XCTAssertEqual(try store.encodedData(maximumBytes: data.count), data)
    XCTAssertThrowsError(try store.encodedData(maximumBytes: data.count - 1))
    let snapshot = try store.encodedData()
    try store.remove(); XCTAssertEqual(snapshot, data)
    let path = root.appendingPathComponent("local-practice-background")
    let target = root.appendingPathComponent("owned-target")
    try data.write(to: target)
    try FileManager.default.createSymbolicLink(at: path, withDestinationURL: target)
    XCTAssertThrowsError(try store.encodedData())
    XCTAssertEqual(try Data(contentsOf: target), data)
    try FileManager.default.removeItem(at: path)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
    XCTAssertThrowsError(try store.encodedData())
    try FileManager.default.removeItem(at: path)
    XCTAssertEqual(mkfifo(path.path, 0o600), 0)
    // Keep the fixture open so a future regression cannot hang the whole suite at open().
    let keeper = Darwin.open(path.path, O_RDWR | O_NONBLOCK)
    guard keeper >= 0 else { return XCTFail("Could not open owned FIFO fixture") }
    defer { Darwin.close(keeper) }
    XCTAssertThrowsError(try store.encodedData(), "A FIFO must fail without blocking for a writer")
  }

  func testPublishedContainerDoesNotAliasCallerMutableData() async throws {
    let data = try imageData()
    let mutable = NSMutableData(data: data)
    let loader = CustomBackgroundImageLoader()
    await loader.load(remoteURL: "", local: { Data(referencing: mutable) })
    mutable.length = 0
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(loader.encodedData, data)
    XCTAssertNotNil(loader.image)
  }

  func testLocalCallbackClearRetiresItsOwnOldLoad() async throws {
    let data = try imageData()
    let loader = CustomBackgroundImageLoader()
    await loader.load(remoteURL: "", local: { loader.clear(); return data })
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.image)
  }

  func testActualHiddenSwiftUIHostReusesSourceTaskAndClearsOnRemoval() async throws {
    let data = try imageData(), store = TypebarLocalBackgroundStore.inMemory()
    var requests = 0
    let loader = CustomBackgroundImageLoader { _, _ in requests += 1; return data }
    func root(fit: CustomBackgroundFit = .cover, revision: Int = 0,
      filter: CustomBackgroundFilter = .init(), backgroundStore: TypebarLocalBackgroundStore? = nil) -> AnyView {
      AnyView(CustomPracticeBackground(fallbackStyle: .solid,
        theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light),
        reduceMotion: true, remoteURL: "https://example.invalid/image.png", fit: fit, filter: filter,
        localImageRevision: revision, localBackgroundStore: backgroundStore ?? store, loader: loader)
        .frame(width: 80, height: 40))
    }
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: root())
    window.contentView = host
    defer { window.contentView = nil; window.close(); loader.clear() }
    host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where loader.state != .ready { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(loader.state, .ready); XCTAssertEqual(requests, 1)
    XCTAssertFalse(window.isVisible)
    host.rootView = root(fit: .contain); host.layoutSubtreeIfNeeded(); await settle()
    XCTAssertEqual(requests, 1, "A fit change must not reload the image")
    host.rootView = root(fit: .contain, filter: .init(brightness: 0.5)); host.layoutSubtreeIfNeeded(); await settle()
    XCTAssertEqual(requests, 1, "A filter change must not reload the image")
    host.rootView = root(fit: .contain, revision: 1); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where requests != 2 { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 2)
    host.rootView = root(fit: .contain, revision: 1, backgroundStore: .inMemory()); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where requests != 3 { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(requests, 3, "A new local store is a new source even with the same revision")
    host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where loader.state != .empty { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(loader.state, .empty); XCTAssertNil(loader.encodedData)
    XCTAssertFalse(window.isVisible)
  }
}
