import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundResourceTests: XCTestCase {
  private let address = WebsiteConfigValue.string("https://example.invalid/background.png")

  private func preferences(_ address: WebsiteConfigValue? = nil) throws -> WebsiteConfigNativePagePreferences {
    var runtime = try WebsiteConfigNativeProfile.defaultDocument().values
    runtime["customBackground"] = address ?? self.address
    return try .init(runtime: runtime)
  }
  private func image(_ color: [UInt8], width: Int = 2) throws -> CGImage {
    let data = Data(Array(repeating: color, count: width).flatMap { $0 })
    return try XCTUnwrap(CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
  private func encoded(animated: Bool = false) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,
      (animated ? UTType.gif.identifier : UTType.png.identifier) as CFString, animated ? 2 : 1, nil))
    if animated {
      CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFLoopCount: 3]] as CFDictionary)
    }
    CGImageDestinationAddImage(destination, try image([255, 0, 0, 255]),
      animated ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.12]] as CFDictionary : nil)
    if animated {
      CGImageDestinationAddImage(destination, try image([0, 0, 255, 255]),
        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.34]] as CFDictionary)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
  private func ready(_ resource: WebsiteConfigBackgroundResource) throws -> WebsiteConfigBackgroundResource.Image {
    guard case .ready(let image) = resource.state else { XCTFail("Expected decoded image"); throw Failure.notReady }
    return image
  }
  private enum Failure: Error { case notReady, notCommitted }
  private func pixels(_ image: CGImage) throws -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
  }

  func testActualPNGDecodesIntoOwnedPixelsAndExactOriginalBytes() throws {
    var data = try encoded()
    let original = data
    let resource = try WebsiteConfigBackgroundResource.prepare(preferences: preferences(), local: .absent,
      remote: .received(address: address, data: data))
    XCTAssertEqual(resource.source, .remote(address))
    let decoded = try ready(resource)
    data.resetBytes(in: data.indices)
    XCTAssertEqual(decoded.encodedData, original)
    XCTAssertEqual(decoded.type, UTType.png.identifier)
    XCTAssertEqual(decoded.frames.count, 1)
    XCTAssertEqual(try pixels(decoded.frames[0].image), [255, 0, 0, 255, 255, 0, 0, 255])
    let external = NSMutableData(data: original)
    let copied = try ready(WebsiteConfigBackgroundResource.prepare(preferences: preferences(),
      local: .data(Data(referencing: external))))
    external.length = 0
    XCTAssertEqual(copied.encodedData, original, "Do not retain caller-mutable encoded storage")
    XCTAssertEqual(try pixels(copied.frames[0].image), [255, 0, 0, 255, 255, 0, 0, 255])
  }

  func testGIFKeepsBothFramesTimingLoopMetadataAndEncodedContainer() throws {
    let data = try encoded(animated: true)
    let resource = try WebsiteConfigBackgroundResource.prepare(preferences: preferences(), local: .data(data))
    XCTAssertEqual(resource.source, .local)
    let decoded = try ready(resource)
    XCTAssertEqual(decoded.encodedData, data)
    XCTAssertEqual(decoded.frames.count, 2, "Never flatten animation to a first-frame success")
    XCTAssertEqual(try pixels(decoded.frames[0].image), [255, 0, 0, 255, 255, 0, 0, 255])
    XCTAssertEqual(try pixels(decoded.frames[1].image), [0, 0, 255, 255, 0, 0, 255, 255])
    let gif = (decoded.properties as NSDictionary?)?[kCGImagePropertyGIFDictionary] as? NSDictionary
    XCTAssertEqual((gif?[kCGImagePropertyGIFLoopCount] as? NSNumber)?.intValue, 3)
    for (index, duration) in [0.12, 0.34].enumerated() {
      let metadata = decoded.frames[index].properties as NSDictionary
      let properties = metadata[kCGImagePropertyGIFDictionary] as? NSDictionary
      XCTAssertEqual(try XCTUnwrap(properties?[kCGImagePropertyGIFDelayTime] as? NSNumber).doubleValue,
        duration, accuracy: 0.001)
    }
  }

  func testLocalUndefinedEmptyAndFailedLocalNeverBorrowRemoteBytes() throws {
    let prefs = try preferences()
    let empty = try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .empty,
      remote: .received(address: .string("wrong"), data: Data()))
    guard case .none = empty.state else { return XCTFail("Empty local must suppress remote") }
    XCTAssertNil(empty.source)
    let invalid = try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .data(Data()),
      remote: .received(address: address, data: encoded()))
    XCTAssertEqual(invalid.source, .local)
    guard case .failed(.undecodable) = invalid.state else { return XCTFail("Invalid local must not fall back") }
    XCTAssertThrowsError(try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .absent)) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundResourceError, .remoteNotProvided)
    }
    let none = try WebsiteConfigBackgroundResource.prepare(preferences: preferences(.string("")), local: .absent)
    guard case .none = none.state else { return XCTFail("Empty remote must not require transport") }
  }

  func testRemoteAssociationTransportAndInvalidPayloadAreExplicit() throws {
    let prefs = try preferences()
    XCTAssertThrowsError(try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .absent,
      remote: .received(address: .string("https://example.invalid/other.png"), data: encoded()))) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundResourceError, .wrongRemoteAddress)
    }
    for (input, expected) in [(WebsiteConfigBackgroundResource.Remote.failed(address: address),
      WebsiteConfigBackgroundResource.Failure.transport), (.received(address: address, data: Data("not an image".utf8)), .undecodable)] {
      let value = try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .absent, remote: input)
      XCTAssertEqual(value.source, .remote(address))
      guard case .failed(let failure) = value.state else { return XCTFail("Failure was disguised as image readiness") }
      XCTAssertEqual(failure, expected)
    }
    let data = try encoded()
    let truncated = try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .data(Data(data.prefix(8))))
    guard case .failed(.undecodable) = truncated.state else { return XCTFail("Incomplete header passed image admission") }
    let composed = WebsiteConfigValue.string("https://example.invalid/\u{e9}.png")
    let decomposed = WebsiteConfigValue.string("https://example.invalid/e\u{301}.png")
    XCTAssertThrowsError(try WebsiteConfigBackgroundResource.prepare(preferences: preferences(composed), local: .absent,
      remote: .received(address: decomposed, data: data))) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundResourceError, .wrongRemoteAddress)
    }
    let raw = WebsiteConfigValue.stringCodeUnits(Array("https://example.invalid/".utf16)
      + [0xD800] + Array(".png".utf16))
    XCTAssertEqual(try ready(WebsiteConfigBackgroundResource.prepare(preferences: preferences(raw), local: .absent,
      remote: .received(address: raw, data: data))).frames.count, 1,
      "Response association preserves the request's raw units; it is not a URL safety check")
  }

  func testByteFrameAndAggregatePixelBudgetsRejectWithoutFlattening() throws {
    let data = try encoded(animated: true), prefs = try preferences()
    for limits in [WebsiteConfigBackgroundResource.Limits(encodedBytes: data.count - 1),
      .init(pixels: 3), .init(decodedBytes: 1), .init(frames: 1)] {
      let value = try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .data(data), limits: limits)
      guard case .failed(.resourceLimit) = value.state else { return XCTFail("Resource budget not enforced") }
    }
    XCTAssertEqual(try ready(WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .data(data),
      limits: .init(encodedBytes: data.count, pixels: 4, frames: 2))).frames.count, 2)
    XCTAssertThrowsError(try WebsiteConfigBackgroundResource.prepare(preferences: prefs, local: .data(data),
      limits: .init(pixels: 0))) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundResourceError, .invalidLimits)
    }
  }

  func testBackgroundResultPublishesWithItsConfigurationAndFailedImageDoesNotEraseIntent() throws {
    try withCoordinator { coordinator, register, owner, _ in
      let first = try coordinator.prepare(#"{"customBackground":"https://example.invalid/background.png","time":41}"#)
      let background = try coordinator.prepareBackground(for: first, local: .absent,
        remote: .received(address: address, data: encoded()))
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(try register.read().state, .missing)
      guard case .committed(let publication) = try coordinator.commit(background) else { throw Failure.notCommitted }
      XCTAssertEqual(try ready(XCTUnwrap(publication.background)).frames.count, 1)
      XCTAssertEqual(try register.read().state, .available(publication.draft.projection.runtime))
      let failure = try coordinator.prepare(#"{"customBackground":"https://example.invalid/background.png","time":43}"#)
      let failed = try coordinator.prepareBackground(for: failure, local: .absent, remote: .failed(address: address))
      guard case .committed(let next) = try coordinator.commit(failed) else { throw Failure.notCommitted }
      guard case .failed(.transport) = next.background?.state else { return XCTFail("Must publish explicit failed-image state") }
      XCTAssertEqual(next.draft.projection.runtime["customBackground"], address)
      XCTAssertEqual(next.draft.projection.runtime["time"], .number(43))
    }
  }

  func testPreparedBackgroundCannotCrossOwnerRequestOrDiskChanges() throws {
    try withCoordinator { coordinator, register, owner, router in
      let first = try coordinator.prepare(#"{"time":41}"#)
      let background = try coordinator.prepareBackground(for: first, local: .data(encoded()))
      let other = UUID()
      router.register(owner: other, save: {})
      router.activate(owner: other)
      router.activate(owner: owner)
      guard case .stale = try coordinator.commit(background) else { return XCTFail("Owner ABA admitted resources") }
      XCTAssertEqual(try register.read().state, .missing)
      let fresh = try coordinator.prepare(#"{"time":43}"#)
      let resource = try coordinator.prepareBackground(for: fresh, local: .data(encoded()))
      let external = try WebsiteConfigNativeProfile.prepareDraft(#"{"time":45}"#, pointsPerRem: 16, context: .init())
      _ = try register.commit(external, replacing: XCTUnwrap(register.read().revision))
      guard case .conflict = try coordinator.commit(resource) else { return XCTFail("Resources bypassed disk CAS") }
      XCTAssertNil(coordinator.publication(for: owner))
      XCTAssertEqual(try register.read().state, .available(external.projection.runtime))
      let older = try coordinator.prepare(#"{"time":47}"#)
      let olderImage = try coordinator.prepareBackground(for: older, local: .data(encoded()))
      _ = try coordinator.prepare(#"{"time":49}"#)
      guard case .stale = try coordinator.commit(olderImage) else { return XCTFail("Resources bypassed latest intent") }
    }
  }

  func testNewBackgroundAttemptEvenWhenIncompleteSupersedesOlderResources() throws {
    try withCoordinator { coordinator, register, owner, _ in
      let configuration = try coordinator.prepare(#"{"customBackground":"https://example.invalid/background.png"}"#)
      let old = try coordinator.prepareBackground(for: configuration, local: .data(encoded()))
      XCTAssertThrowsError(try coordinator.prepareBackground(for: configuration, local: .absent)) {
        XCTAssertEqual($0 as? WebsiteConfigBackgroundResourceError, .remoteNotProvided)
      }
      guard case .stale = try coordinator.commit(old) else { return XCTFail("Older image survived newer failed attempt") }
      XCTAssertFalse(coordinator.cancel(old))
      XCTAssertEqual(try register.read().state, .missing)
      let next = try coordinator.prepareBackground(for: configuration, local: .empty)
      XCTAssertFalse(coordinator.cancel(old), "Old resource cancellation must not retire the configuration")
      guard case .committed(let publication) = try coordinator.commit(next) else { throw Failure.notCommitted }
      guard case .some(.none) = publication.background?.state else { return XCTFail("Explicit no-image differs from unprepared nil") }
      XCTAssertNotNil(coordinator.publication(for: owner)?.background)
      let another = try coordinator.prepare(#"{"time":43}"#)
      let cancelled = try coordinator.prepareBackground(for: another, local: .empty)
      XCTAssertTrue(coordinator.cancel(cancelled))
      guard case .stale = try coordinator.commit(cancelled) else { return XCTFail("Cancelled background committed") }
    }
  }

  private func withCoordinator(_ body: (WebsiteConfigCommitCoordinator, WebsiteConfigFileRegister, UUID,
    PreferenceConfigurationSaveRouter) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("typebar-background-resource-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = PreferenceConfigurationSaveRouter(), owner = UUID(), epoch = UUID()
    router.register(owner: owner, save: { XCTFail("No legacy resource event replay") })
    let register = WebsiteConfigFileRegister(directory: directory)
    let coordinator = WebsiteConfigCommitCoordinator(router: router, register: register,
      environment: { .init(revision: epoch, context: .init(), pointsPerRem: 16) })
    try body(coordinator, register, owner, router)
  }
}
