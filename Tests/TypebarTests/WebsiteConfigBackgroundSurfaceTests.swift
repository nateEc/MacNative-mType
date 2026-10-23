import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundSurfaceTests: XCTestCase {
  private let normal = WebsiteConfigNativePagePreferences.BackgroundFilter(blurRem: 0, brightness: 1, saturation: 1, opacity: 1)
  private func cgImage(_ pixels: [UInt8], width: Int = 1, height: Int = 1) throws -> CGImage {
    try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
  private func image(_ pixels: [UInt8], width: Int = 1, height: Int = 1) throws -> WebsiteConfigBackgroundResource.Image {
    .init(encodedData: Data(), type: UTType.png.identifier, properties: nil,
      frames: [.init(image: try cgImage(pixels, width: width, height: height), properties: [:] as CFDictionary)])
  }
  private func pixels(_ image: CGImage?) throws -> [UInt8] {
    let image = try XCTUnwrap(image)
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }
  private func window(_ view: NSView, size: CGSize) -> NSWindow {
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.colorSpace = .sRGB; window.contentView = view
    return window
  }
  private func settle() async { for _ in 0..<40 { await Task.yield() } }

  func testSurfaceActuallyRendersThreeFitsAndTracksViewportSize() throws {
    let row: [UInt8] = [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255]
    let source = try image(row + row, width: 4, height: 2)
    let view = WebsiteConfigBackgroundSurfaceView()
    defer { view.stop() }
    view.setFrameSize(CGSize(width: 4, height: 4))
    let identity = UUID()
    view.configure(image: source, identity: identity, fit: .contain, filter: normal)
    let bytes = try pixels(view.renderedImage)
    XCTAssertEqual(Array(bytes.prefix(16)), Array(repeating: 0, count: 16))
    XCTAssertEqual(Array(bytes[16..<32]), [255, 0, 0, 255, 255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255])
    for fit in [CustomBackgroundFit.cover, .max] {
      view.configure(image: source, identity: identity, fit: fit, filter: normal)
      XCTAssertTrue(try pixels(view.renderedImage).enumerated().filter { $0.offset % 4 == 3 }.allSatisfy { $0.element == 255 })
    }
    view.setFrameSize(CGSize(width: 7, height: 3)); view.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.renderedImage?.width, 7); XCTAssertEqual(view.renderedImage?.height, 3)
  }

  func testSameImageKeepsInvalidFilterHistoryButNewIdentityStartsFresh() throws {
    let source = try image([64, 32, 16, 255])
    let view = WebsiteConfigBackgroundSurfaceView()
    defer { view.stop() }
    view.setFrameSize(CGSize(width: 1, height: 1))
    let identity = UUID()
    view.configure(image: source, identity: identity, fit: .max,
      filter: .init(blurRem: 0, brightness: 2, saturation: 1, opacity: 1))
    XCTAssertEqual(try pixels(view.renderedImage), [128, 64, 32, 255])
    let invalid = WebsiteConfigNativePagePreferences.BackgroundFilter(blurRem: 0, brightness: -1, saturation: 1, opacity: 1)
    view.configure(image: source, identity: identity, fit: .max, filter: invalid)
    XCTAssertEqual(try pixels(view.renderedImage), [128, 64, 32, 255])
    view.configure(image: source, identity: UUID(), fit: .max, filter: invalid)
    XCTAssertEqual(try pixels(view.renderedImage), [64, 32, 16, 255])
  }

  func testNativeDrawUsesCorrectTopEdgeBackingAndDoesNotStealInput() throws {
    let view = WebsiteConfigBackgroundSurfaceView()
    let window = window(view, size: CGSize(width: 2, height: 2))
    defer { view.stop(); window.contentView = nil; window.close() }
    let source = try image([255, 0, 0, 255, 0, 0, 255, 255], height: 2)
    view.configure(image: source, identity: UUID(), fit: .max, filter: normal)
    view.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.renderedScale, window.backingScaleFactor)
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let output = try pixels(bitmap.cgImage)
    XCTAssertEqual(Array(output.prefix(4)), [255, 0, 0, 255])
    XCTAssertEqual(Array(output.suffix(4)), [0, 0, 255, 255])
    XCTAssertNil(view.hitTest(.zero)); XCTAssertFalse(window.isVisible)
  }

  private final class Clock {
    var time = 0.0
    var pending: [CheckedContinuation<Void, Error>] = []
    func sleep(_ delay: Double) async throws { try await withCheckedThrowingContinuation { pending.append($0) } }
    func drain() { let old = pending; pending = []; for continuation in old { continuation.resume() } }
  }
  func testAnimationStyleChangesDoNotRestartAndReplacementRejectsOldFrames() async throws {
    let clock = Clock(), player = WebsiteConfigBackgroundPlayer(now: { clock.time }, sleep: { try await clock.sleep($0) })
    let view = WebsiteConfigBackgroundSurfaceView(player: player)
    let window = window(view, size: CGSize(width: 1, height: 1))
    defer { view.stop(); clock.drain(); window.contentView = nil; window.close() }
    let red = try image([255, 0, 0, 255]).frames[0], blue = try image([0, 0, 255, 255]).frames[0]
    func timed(_ frame: WebsiteConfigBackgroundResource.Frame) -> WebsiteConfigBackgroundResource.Frame {
      .init(image: frame.image, properties: [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFUnclampedDelayTime: 0.125]] as CFDictionary)
    }
    let animation = WebsiteConfigBackgroundResource.Image(encodedData: Data(), type: UTType.gif.identifier,
      properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary,
      frames: [timed(red), timed(blue)])
    let identity = UUID()
    view.configure(image: animation, identity: identity, fit: .max, filter: normal)
    await settle()
    guard !clock.pending.isEmpty else { return XCTFail("No animation wait") }
    clock.time = 0.13; clock.pending.removeFirst().resume(); await settle()
    XCTAssertEqual(player.currentSample?.frameIndex, 1)
    view.configure(image: animation, identity: identity, fit: .contain, filter: normal)
    XCTAssertEqual(player.currentSample?.frameIndex, 1, "Fit changes must not restart animation")
    view.configure(image: try image([0, 255, 0, 255]), identity: UUID(), fit: .max, filter: normal)
    clock.time = 1; clock.drain(); await settle()
    XCTAssertEqual(player.state, .finished)
    XCTAssertTrue(try pixels(view.renderedImage).enumerated().allSatisfy { [0, 255, 0, 255][$0.offset % 4] == $0.element })
    view.stop(); XCTAssertNil(view.renderedImage); XCTAssertEqual(player.state, .stopped)
  }

  func testRenderQuotaFailureCannotKeepOldPixelsAndResizeCanRecover() throws {
    let view = WebsiteConfigBackgroundSurfaceView(limits: .init(pixels: 1))
    defer { view.stop() }
    view.setFrameSize(CGSize(width: 1, height: 1))
    view.configure(image: try image([255, 0, 0, 255]), identity: UUID(), fit: .max, filter: normal)
    XCTAssertNotNil(view.renderedImage)
    view.setFrameSize(CGSize(width: 2, height: 2))
    XCTAssertNotNil(view.error); XCTAssertNil(view.renderedImage)
    view.setFrameSize(CGSize(width: 1, height: 1)); view.layoutSubtreeIfNeeded()
    XCTAssertNil(view.error); XCTAssertEqual(try pixels(view.renderedImage), [255, 0, 0, 255])
  }

  func testTransparentFrameAndStopErasePreviouslyDrawnPixels() throws {
    let view = WebsiteConfigBackgroundSurfaceView()
    defer { view.stop() }
    view.setFrameSize(CGSize(width: 1, height: 1))
    let red = try image([255, 0, 0, 255]), clear = try image([0, 0, 0, 0])
    var bytes = [UInt8](repeating: 0, count: 4), snapshots: [[UInt8]] = []
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
        bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      NSGraphicsContext.saveGraphicsState()
      defer { NSGraphicsContext.restoreGraphicsState() }
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      view.configure(image: red, identity: UUID(), fit: .max, filter: normal)
      view.draw(view.bounds); snapshots.append(Array(buffer))
      view.configure(image: clear, identity: UUID(), fit: .max, filter: normal)
      view.draw(view.bounds); snapshots.append(Array(buffer))
      view.configure(image: red, identity: UUID(), fit: .max, filter: normal)
      view.draw(view.bounds); view.stop()
      view.draw(view.bounds); snapshots.append(Array(buffer))
    }
    XCTAssertEqual(snapshots[0], [255, 0, 0, 255])
    XCTAssertEqual(snapshots[1], [0, 0, 0, 0], "Transparent frames must erase old pixels")
    XCTAssertEqual(snapshots[2], [0, 0, 0, 0], "Stop must erase old pixels")
  }

  private func encoded(animated: Bool = false) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,
      (animated ? UTType.gif : .png).identifier as CFString, animated ? 2 : 1, nil))
    if animated {
      CGImageDestinationSetProperties(destination,
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    }
    let colors: [[UInt8]] = animated ? [[255, 0, 0, 255], [0, 0, 255, 255]] : [[255, 0, 0, 255]]
    for color in colors {
      CGImageDestinationAddImage(destination, try cgImage(color + color, width: 2),
        animated ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: 0.12]] as CFDictionary : nil)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }

  func testPreparedRasterQuotaCannotFallBackThroughNSImageAndSourceLabelIsExplicit() async throws {
    let data = try encoded()
    let origin = WebsiteConfigBackgroundResource.Source.remote(.string("https://example.invalid/image.png"))
    let resource = try WebsiteConfigBackgroundResource.prepare(loadedData: data, source: origin)
    XCTAssertEqual(resource.source, origin)
    guard case .ready(let image) = resource.state else { return XCTFail("Actual PNG not prepared") }
    XCTAssertEqual(image.encodedData, data)
    XCTAssertThrowsError(try WebsiteConfigBackgroundResource.prepare(loadedData: data, source: .local,
      limits: .init(pixels: 0)))
    let loader = CustomBackgroundImageLoader(resourceLimits: .init(pixels: 1))
    await loader.load(remoteURL: "", local: { data })
    XCTAssertEqual(loader.state, .failed)
    XCTAssertNil(loader.image); XCTAssertNil(loader.nativeImage); XCTAssertNil(loader.encodedData)
    guard case .resourceLimit? = loader.error as? LocalBackgroundError else { return XCTFail("Quota failure was hidden") }
  }

  func testOwnedNativeOnlyPDFRetainsItsExplicitCompatibilityBranch() async throws {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 2, height: 1)
    let consumer = try XCTUnwrap(CGDataConsumer(data: data))
    let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil); context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(box); context.endPDFPage(); context.closePDF()
    let loader = CustomBackgroundImageLoader()
    await loader.load(remoteURL: "", local: { data as Data })
    XCTAssertEqual(loader.state, .ready); XCTAssertNotNil(loader.image)
    XCTAssertNil(loader.nativeImage, "This native-only fixture must exercise the retained old display branch")
    XCTAssertEqual(loader.encodedData, data as Data)
  }

  func testOwnedSVGRemainsDisplayableWithoutChangingOriginalContainer() async throws {
    let data = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"2\" height=\"1\"><rect width=\"2\" height=\"1\" fill=\"#ff0000\"/></svg>".utf8)
    let loader = CustomBackgroundImageLoader()
    await loader.load(remoteURL: "", local: { data })
    XCTAssertEqual(loader.state, .ready)
    XCTAssertTrue(try XCTUnwrap(loader.image).isValid)
    XCTAssertEqual(loader.encodedData, data)
  }

  func testActualProductionSwiftUIHostPlaysDecodedGIFAndDismantlesItsSurface() async throws {
    let data = try encoded(animated: true), store = TypebarLocalBackgroundStore.inMemory()
    try store.save(data)
    let loader = CustomBackgroundImageLoader()
    let root = AnyView(CustomPracticeBackground(fallbackStyle: .solid,
      theme: .init(background: .white, panel: .white, accent: .blue, colorScheme: .light),
      reduceMotion: true, remoteURL: "", fit: .max, filter: .init(), localImageRevision: 0,
      localBackgroundStore: store, loader: loader).frame(width: 20, height: 10))
    let host = NSHostingView(rootView: root)
    let window = window(host, size: CGSize(width: 20, height: 10))
    defer { host.rootView = AnyView(EmptyView()); window.contentView = nil; window.close(); loader.clear() }
    func surface(_ view: NSView) -> WebsiteConfigBackgroundSurfaceView? {
      if let value = view as? WebsiteConfigBackgroundSurfaceView { return value }
      for child in view.subviews { if let value = surface(child) { return value } }
      return nil
    }
    var captured: WebsiteConfigBackgroundSurfaceView?
    for _ in 0..<200 {
      host.layoutSubtreeIfNeeded()
      if let view = surface(host), view.player.currentSample?.frameIndex == 1, view.renderedImage != nil {
        captured = view; break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    let view = try XCTUnwrap(captured)
    XCTAssertEqual(loader.nativeImage?.frames.count, 2)
    XCTAssertEqual(view.bounds.size, CGSize(width: 20, height: 10))
    XCTAssertEqual(view.player.state, .playing)
    XCTAssertTrue(try pixels(view.renderedImage).enumerated().allSatisfy { [0, 0, 255, 255][$0.offset % 4] == $0.element })
    XCTAssertFalse(window.isVisible)
    host.rootView = AnyView(EmptyView()); host.layoutSubtreeIfNeeded()
    for _ in 0..<100 where view.player.state != .stopped { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertEqual(view.player.state, .stopped); XCTAssertNil(view.renderedImage)
    XCTAssertNil(loader.nativeImage); XCTAssertFalse(window.isVisible)
  }
}
