import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigPublishedBackgroundTests: XCTestCase {
  @MainActor private final class Fixture {
    let directory: URL
    let owner = UUID()
    let router = PreferenceConfigurationSaveRouter()
    let register: WebsiteConfigFileRegister
    let coordinator: WebsiteConfigCommitCoordinator
    init(pointsPerRem: Double = 16) throws {
      directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-published-background-\(UUID())")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      register = .init(directory: directory)
      router.register(owner: owner, save: { XCTFail("No legacy setting replay") })
      let epoch = UUID()
      coordinator = .init(router: router, register: register,
        environment: { .init(revision: epoch, context: .init(), pointsPerRem: pointsPerRem) })
    }
    func close() { router.remove(owner: owner); try? FileManager.default.removeItem(at: directory) }
    func publish(_ json: String = "{}", local: WebsiteConfigBackgroundResource.Local = .absent,
      remote: WebsiteConfigBackgroundResource.Remote? = nil, prepare: Bool = true) throws -> WebsiteConfigCommitCoordinator.Publication {
      let ticket = try coordinator.prepare(json)
      let outcome: WebsiteConfigCommitCoordinator.Outcome
      if prepare { outcome = try coordinator.commit(coordinator.prepareBackground(for: ticket, local: local, remote: remote)) }
      else { outcome = try coordinator.commit(ticket) }
      guard case .committed(let publication) = outcome else { throw Failure.notCommitted }
      return publication
    }
  }
  private enum Failure: Error { case notCommitted }
  private let theme = ResolvedTheme(background: .white, panel: .white, accent: .blue, colorScheme: .light)
  private func image(animated: Bool = false) throws -> Data {
    let data = NSMutableData()
    let output = try XCTUnwrap(CGImageDestinationCreateWithData(data, (animated ? UTType.gif : UTType.png).identifier as CFString,
      animated ? 2 : 1, nil))
    if animated { CGImageDestinationSetProperties(output,
      [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary) }
    for pixel: [UInt8] in animated ? [[64, 32, 16, 255], [0, 0, 255, 255]] : [[64, 32, 16, 255]] {
      let source = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(pixel) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
      CGImageDestinationAddImage(output, source, animated ? [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFUnclampedDelayTime: 0.12]] as CFDictionary : nil)
    }
    XCTAssertTrue(CGImageDestinationFinalize(output)); return data as Data
  }
  private func view(_ publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws -> AnyView {
    AnyView(try WebsiteConfigPublishedBackground(publication: publication, owner: owner,
      fallbackStyle: .solid, theme: theme, reduceMotion: true, onFailure: onFailure))
  }
  private func find(_ root: NSView) -> WebsiteConfigPublishedBackgroundView? {
    if let found = root as? WebsiteConfigPublishedBackgroundView { return found }
    return root.subviews.lazy.compactMap { self.find($0) }.first
  }
  private func mounted(_ host: NSHostingView<AnyView>) async throws -> WebsiteConfigPublishedBackgroundView {
    for _ in 0..<200 {
      host.layoutSubtreeIfNeeded()
      if let found = find(host), found.bounds.width > 0 { return found }
      try await Task.sleep(for: .milliseconds(5))
    }
    return try XCTUnwrap(find(host))
  }
  private func window(_ host: NSView) -> NSWindow {
    let result = NSWindow(contentRect: .init(x: 0, y: 0, width: 4, height: 2),
      styleMask: .borderless, backing: .buffered, defer: false)
    result.isReleasedWhenClosed = false; result.colorSpace = .sRGB; result.contentView = host
    return result
  }
  private func firstPixel(_ image: CGImage?) throws -> [UInt8] {
    let image = try XCTUnwrap(image)
    var pixel = [UInt8](repeating: 0, count: 4)
    try pixel.withUnsafeMutableBytes { bytes in
      let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: .init(x: 0, y: 0, width: 1, height: 1))
    }
    return pixel
  }

  func testCommittedPixelsUseRawFilterAndKeepPreparedFrameOwnership() async throws {
    let f = try Fixture(pointsPerRem: 24); defer { f.close() }
    let publication = try f.publish(#"{"customBackgroundSize":"max","customBackgroundFilter":[0,3,1,1]}"#, local: .data(image()))
    XCTAssertEqual(publication.pointsPerRem, 24)
    let host = NSHostingView(rootView: try view(publication, owner: f.owner)), window = window(host)
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    let consumer = try await mounted(host)
    XCTAssertEqual(try firstPixel(consumer.surface.renderedImage), [192, 96, 48, 255], "The old filter clamps brightness to two")
    guard case .ready(let image) = publication.background?.state else { return XCTFail("Missing prepared frame") }
    XCTAssertTrue(consumer.surface.player.currentSample?.frame.image === image.frames[0].image,
      "The consumer must use the prepared frame, not decode its bytes again")
    XCTAssertNil(consumer.hitTest(.zero)); XCTAssertFalse(window.isVisible)
    XCTAssertEqual(try f.register.read().state, .available(publication.draft.projection.runtime))
  }

  func testConsumerRejectsForeignOwnerAndPureValuePublication() throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try f.publish(local: .data(image()))
    XCTAssertThrowsError(try view(ready, owner: UUID())) { error in
      guard case WebsiteConfigPublishedBackgroundError.wrongOwner = error else { return XCTFail("Wrong rejection") }
    }
    let unprepared = try f.publish(prepare: false)
    XCTAssertThrowsError(try view(unprepared, owner: f.owner)) { error in
      guard case WebsiteConfigPublishedBackgroundError.unprepared = error else { return XCTFail("Missing admission hidden as no image") }
    }
  }

  private func pixels(_ image: CGImage?) throws -> [UInt8] {
    let image = try XCTUnwrap(image)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { storage in
      let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }

  func testConsumerUsesCommittedRemRatherThanSurfaceDefault() async throws {
    let f = try Fixture(pointsPerRem: 24); defer { f.close() }
    let publication = try f.publish(#"{"customBackgroundSize":"max","customBackgroundFilter":[-0.02,1,1,1]}"#,
      local: .data(image()))
    let host = NSHostingView(rootView: try view(publication, owner: f.owner)), window = window(host)
    window.setContentSize(.init(width: 20, height: 20))
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    let consumer = try await mounted(host)
    guard case .ready(let image) = publication.background?.state else { return XCTFail("Missing image") }
    let control = WebsiteConfigBackgroundSurfaceView()
    consumer.addSubview(control)
    defer { control.stop(); control.removeFromSuperview() }
    control.setFrameSize(consumer.surface.bounds.size)
    control.configure(image: image, identity: UUID(), fit: publication.draft.pagePreferences.backgroundFit,
      filter: publication.draft.pagePreferences.backgroundFilter, pointsPerRem: 24)
    XCTAssertTrue(control.window === consumer.window)
    XCTAssertEqual(control.renderedScale, consumer.surface.renderedScale)
    XCTAssertEqual(control.renderedImage?.width, consumer.surface.renderedImage?.width)
    XCTAssertEqual(control.renderedImage?.height, consumer.surface.renderedImage?.height)
    XCTAssertEqual(try pixels(consumer.surface.renderedImage), try pixels(control.renderedImage))
    control.configure(image: image, identity: UUID(), fit: publication.draft.pagePreferences.backgroundFit,
      filter: publication.draft.pagePreferences.backgroundFilter, pointsPerRem: 16)
    XCTAssertNotEqual(try pixels(consumer.surface.renderedImage), try pixels(control.renderedImage),
      "The sample must distinguish the captured root scale from the old default")
  }

  func testUnmountCancelsQueuedFailureAndNewMountCanReport() async throws {
    let f = try Fixture(); defer { f.close() }
    let publication = try f.publish(#"{"customBackground":"https://example.invalid/owned.png"}"#,
      remote: .failed(address: .string("https://example.invalid/owned.png")))
    let consumer = WebsiteConfigPublishedBackgroundView()
    var notices: [BackgroundFailureFeedback.Kind] = []
    let resource = try XCTUnwrap(publication.background)
    consumer.configure(publication: publication, resource: resource, onFailure: { notices.append($0) })
    consumer.stop()
    for _ in 0..<20 { await Task.yield() }
    XCTAssertTrue(notices.isEmpty)
    consumer.configure(publication: publication, resource: resource, onFailure: { notices.append($0) })
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(notices, [.remote])
    consumer.stop()
  }

  func testFailureAndNoneReplaceOldPixelsWithoutLoadingAndOnlyReportOnce() async throws {
    let f = try Fixture(); defer { f.close() }
    let ready = try f.publish(local: .data(image()))
    let host = NSHostingView(rootView: try view(ready, owner: f.owner)), window = window(host)
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    let initial = try await mounted(host)
    XCTAssertNotNil(initial.surface.renderedImage)
    let address = WebsiteConfigValue.string("https://example.invalid/private.png?secret=not-for-notice")
    let failed = try f.publish(#"{"customBackground":"https://example.invalid/private.png?secret=not-for-notice"}"#,
      remote: .failed(address: address, reason: .resourceLimit))
    var notices: [BackgroundFailureFeedback.Kind] = []
    host.rootView = try view(failed, owner: f.owner, onFailure: { notices.append($0) })
    let consumer = try await mounted(host)
    for _ in 0..<20 { await Task.yield() }
    XCTAssertNil(consumer.surface.renderedImage); XCTAssertEqual(consumer.surface.player.state, .stopped)
    XCTAssertEqual(notices, [.resourceLimit])
    host.rootView = try view(failed, owner: f.owner, onFailure: { notices.append($0) })
    _ = try await mounted(host)
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(notices, [.resourceLimit], "An ordinary view update is not another application")
    host.rootView = try view(f.publish(), owner: f.owner, onFailure: { notices.append($0) })
    let empty = try await mounted(host)
    XCTAssertNil(empty.surface.renderedImage); XCTAssertEqual(notices, [.resourceLimit])
  }

  func testIdenticalReapplicationGetsNewLifetimeAndUnmountStopsAnimation() async throws {
    let f = try Fixture(); defer { f.close() }
    let data = try image(animated: true)
    let first = try f.publish(local: .data(data))
    let second = try f.publish(local: .data(data))
    XCTAssertNotEqual(first.applicationID, second.applicationID)
    XCTAssertEqual(first.draft.projection.runtime, second.draft.projection.runtime)
    let host = NSHostingView(rootView: try view(first, owner: f.owner)), window = window(host)
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close() }
    var consumer = try await mounted(host)
    for _ in 0..<200 {
      if consumer.surface.player.currentSample?.frameIndex == 1 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    XCTAssertEqual(consumer.surface.player.currentSample?.frameIndex, 1)
    host.rootView = try view(first, owner: f.owner)
    consumer = try await mounted(host)
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    XCTAssertEqual(consumer.surface.player.currentSample?.frameIndex, 1, "A view update must not replay the same publication")
    host.rootView = try view(second, owner: f.owner)
    consumer = try await mounted(host)
    XCTAssertEqual(consumer.surface.player.currentSample?.frameIndex, 0)
    host.rootView = AnyView(EmptyView())
    for _ in 0..<20 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    XCTAssertEqual(consumer.surface.player.state, .stopped); XCTAssertNil(consumer.surface.renderedImage)
    XCTAssertFalse(window.isVisible)
  }
}
