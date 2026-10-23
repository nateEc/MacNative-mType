import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundPlaybackTests: XCTestCase {
  private func cgImage(_ color: [UInt8]) throws -> CGImage {
    try XCTUnwrap(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: .init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(color + color) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
  }
  private func synthetic(type: UTType = .gif, loop: NSNumber? = 2,
    frameProperties: [[CFString: Any]] = [[:], [:]]) throws -> WebsiteConfigBackgroundResource.Image {
    let dictionary = type == .gif ? kCGImagePropertyGIFDictionary
      : type == .png ? kCGImagePropertyPNGDictionary : kCGImagePropertyWebPDictionary
    let loopKey = type == .gif ? kCGImagePropertyGIFLoopCount
      : type == .png ? kCGImagePropertyAPNGLoopCount : kCGImagePropertyWebPLoopCount
    let global: [CFString: Any] = loop.map { [dictionary: [loopKey: $0]] } ?? [dictionary: [:]]
    let red = try cgImage([255, 0, 0, 255])
    return .init(encodedData: Data(), type: type.identifier, properties: global as CFDictionary,
      frames: frameProperties.map { .init(image: red, properties: [dictionary: $0] as CFDictionary) })
  }
  private func prepare(_ data: Data) throws -> WebsiteConfigBackgroundResource.Image {
    let preferences = try WebsiteConfigNativePagePreferences(runtime: WebsiteConfigNativeProfile.defaultDocument().values)
    let resource = try WebsiteConfigBackgroundResource.prepare(preferences: preferences, local: .data(data))
    guard case .ready(let image) = resource.state else { throw FixtureFailure.decode }
    return image
  }
  private enum FixtureFailure: Error { case decode }
  private func encoded(type: UTType, loop: Int? = 2) throws -> Data {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 2, nil))
    let dictionary = type == .gif ? kCGImagePropertyGIFDictionary : kCGImagePropertyPNGDictionary
    let loopKey = type == .gif ? kCGImagePropertyGIFLoopCount : kCGImagePropertyAPNGLoopCount
    let delayKey = type == .gif ? kCGImagePropertyGIFUnclampedDelayTime : kCGImagePropertyAPNGUnclampedDelayTime
    if let loop {
      CGImageDestinationSetProperties(destination, [dictionary: [loopKey: NSNumber(value: loop)]] as CFDictionary)
    }
    for (color, delay) in [([UInt8](arrayLiteral: 255, 0, 0, 255), 0.02), ([0, 0, 255, 255], 0.15)] {
      CGImageDestinationAddImage(destination, try cgImage(color), [dictionary: [delayKey: delay]] as CFDictionary)
    }
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    return data as Data
  }
  private func pixels(_ image: CGImage) throws -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
  }

  func testUnclampedTimingPrecedesClampedAndShortFramesUseBrowserFloor() throws {
    for (type, raw, clamped) in [(UTType.gif, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
      (.png, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
      (.webP, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime)] {
      let playback = try WebsiteConfigBackgroundPlayback(image: synthetic(type: type, frameProperties:
        [[raw: 0.02, clamped: 0.1], [raw: 0.01], [clamped: 0.15], [:]]))
      XCTAssertEqual(playback.durations, [Double(Float(0.02)), 0.1, Double(Float(0.15)), 0.1])
    }
  }

  func testFiniteImageIOLoopCountsAndAbsentCountStopOnLastFrame() throws {
    for type in [UTType.gif, .png, .webP] {
      for count in [nil, NSNumber(value: 1), NSNumber(value: 3)] {
        let playback = try WebsiteConfigBackgroundPlayback(image: synthetic(type: type, loop: count))
        let plays = count?.doubleValue ?? 1
        XCTAssertEqual(playback.totalPlays, plays)
        let end = playback.cycleDuration * plays
        XCTAssertNil(try playback.sample(elapsed: end - 0.001).timeUntilNextFrame,
          "No redundant wakeup after the final frame has already appeared")
        XCTAssertNotNil(try playback.sample(elapsed: end - playback.durations.last! - 0.001).timeUntilNextFrame)
        let final = try playback.sample(elapsed: end)
        XCTAssertEqual(final.frameIndex, 1)
        XCTAssertNil(final.timeUntilNextFrame)
        XCTAssertEqual(try playback.sample(elapsed: Double.greatestFiniteMagnitude).frameIndex, 1)
      }
    }
  }

  func testFrameIntervalsAreHalfOpenAndInfinitePlaybackNeverStops() throws {
    let playback = try WebsiteConfigBackgroundPlayback(image: synthetic(loop: 0,
      frameProperties: [[kCGImagePropertyGIFUnclampedDelayTime: 0.125],
        [kCGImagePropertyGIFUnclampedDelayTime: 0.375]]))
    XCTAssertNil(playback.totalPlays)
    for (elapsed, index, delay) in [(0.0, 0, 0.125), (0.124, 0, 0.001), (0.125, 1, 0.375),
      (0.499, 1, 0.001), (0.5, 0, 0.125), (12.625, 1, 0.375)] {
      let sample = try playback.sample(elapsed: elapsed)
      XCTAssertEqual(sample.frameIndex, index)
      XCTAssertEqual(try XCTUnwrap(sample.timeUntilNextFrame), delay, accuracy: 1e-12)
    }
    let huge = try playback.sample(elapsed: .greatestFiniteMagnitude)
    XCTAssertTrue(try XCTUnwrap(huge.timeUntilNextFrame).isFinite)
    XCTAssertGreaterThan(try XCTUnwrap(huge.timeUntilNextFrame), 0)
  }

  func testInvalidMetadataAndElapsedFailWithoutChangingOwnedImage() throws {
    for value in [-1.0, Double.nan, Double.infinity] {
      XCTAssertThrowsError(try WebsiteConfigBackgroundPlayback(image: synthetic(frameProperties:
        [[kCGImagePropertyGIFUnclampedDelayTime: value], [:]])))
    }
    for loop in [-1.0, 0.5, Double.infinity] {
      XCTAssertThrowsError(try WebsiteConfigBackgroundPlayback(image: synthetic(loop: NSNumber(value: loop))))
    }
    let playback = try WebsiteConfigBackgroundPlayback(image: synthetic())
    for elapsed in [-0.01, Double.nan, Double.infinity, -Double.infinity] {
      XCTAssertThrowsError(try playback.sample(elapsed: elapsed)) {
        XCTAssertEqual($0 as? WebsiteConfigBackgroundPlayback.Failure, .invalidElapsed)
      }
    }
    XCTAssertEqual(try playback.sample(elapsed: 0).frameIndex, 0)
  }

  func testStillAndNonAnimationContainersDoNotCycleAuxiliaryImages() throws {
    let source = try synthetic(type: .gif)
    let still = WebsiteConfigBackgroundResource.Image(encodedData: Data(), type: UTType.png.identifier,
      properties: nil, frames: [source.frames[0]])
    let pages = WebsiteConfigBackgroundResource.Image(encodedData: Data(), type: UTType.tiff.identifier,
      properties: nil, frames: source.frames)
    for image in [still, pages] {
      let playback = try WebsiteConfigBackgroundPlayback(image: image)
      for elapsed in [0, 100, Double.greatestFiniteMagnitude] {
        XCTAssertEqual(try playback.sample(elapsed: elapsed).frameIndex, 0)
        XCTAssertNil(try playback.sample(elapsed: elapsed).timeUntilNextFrame)
      }
    }
    XCTAssertThrowsError(try WebsiteConfigBackgroundPlayback(image:
      .init(encodedData: Data(), type: UTType.gif.identifier, properties: nil, frames: [])))
  }

  func testRealGIFAndAPNGKeepShortDelaysAndProduceTimedViewportPixels() throws {
    for type in [UTType.gif, .png] {
      let data = try encoded(type: type)
      let image = try prepare(data)
      let playback = try WebsiteConfigBackgroundPlayback(image: image)
      XCTAssertEqual(image.frames.count, 2)
      XCTAssertEqual(playback.totalPlays, 2)
      XCTAssertEqual(playback.durations[0], 0.02, accuracy: 1e-7)
      XCTAssertEqual(playback.durations[1], 0.15, accuracy: 1e-7)
      try assertViewport(playback, first: [255, 0, 0, 255], second: [0, 0, 255, 255])
      XCTAssertEqual(playback.image.encodedData, data)
    }
  }

  func testOwnedActualAnimatedWebPUsesDecodedFramesAndNativeViewport() throws {
    // Original 2x1 P6 samples: two pixels (126,33,33), then two (33,33,126).
    // img2webp 1.5.0 -loop 2 -d 20 red.ppm -d 150 blue.ppm -o owned.webp
    // No external image or Monkeytype asset; no encoder dependency at test time.
    let data = try XCTUnwrap(Data(base64Encoded:
      "UklGRogAAABXRUJQVlA4WAoAAAACAAAAAQAAAAAAQU5JTQYAAAD/////AgBBTk1GKgAAAAAAAAAAAAEAAAAAABQAAAJWUDhMEQAAAC8BAAAAB9CQ+jWk/4GI6H8AAEFOTUYqAAAAAAAAAAAAAQAAAAAAlgAAAFZQOEwRAAAALwEAAAAH0JCG1K//gYjofwAA"))
    let playback = try WebsiteConfigBackgroundPlayback(image: prepare(data))
    XCTAssertEqual(playback.image.frames.count, 2)
    XCTAssertEqual(playback.totalPlays, 2)
    XCTAssertEqual(playback.durations[0], 0.02, accuracy: 1e-7)
    XCTAssertEqual(playback.durations[1], 0.15, accuracy: 1e-7)
    try assertViewport(playback, first: [126, 33, 33, 255], second: [33, 33, 126, 255])
    XCTAssertEqual(playback.image.encodedData, data)
  }

  func testOwnIncrementalGIFDisposalAndTransparentCanvasReachTimedViewport() throws {
    // Tiny original GIF writer: clear before every literal keeps LZW codes at three bits.
    // Explicit subrects/disposal avoid an encoder silently replacing them with full frames.
    var bytes = Array("GIF89a".utf8) + [3, 0, 1, 0, 0x81, 0, 0]
    bytes += [0, 0, 0, 255, 0, 0, 0, 0, 255, 0, 255, 0]
    func appendFrame(x: UInt8, indices: [UInt8], disposal: UInt8) {
      bytes += [0x21, 0xf9, 4, (disposal << 2) | 1, 2, 0, 0, 0]
      bytes += [0x2c, x, 0, 0, 0, UInt8(indices.count), 0, 1, 0, 0, 2]
      var codes = indices.flatMap { [UInt8(4), $0] }
      codes.append(5)
      var packed: [UInt8] = []
      var accumulator: UInt32 = 0
      var bits = 0
      for code in codes {
        accumulator |= UInt32(code) << bits
        bits += 3
        while bits >= 8 {
          packed.append(UInt8(accumulator & 255)); accumulator >>= 8; bits -= 8
        }
      }
      if bits > 0 { packed.append(UInt8(accumulator & 255)) }
      bytes += [UInt8(packed.count)] + packed + [0]
    }
    appendFrame(x: 0, indices: [1, 1, 1], disposal: 1)
    appendFrame(x: 1, indices: [2], disposal: 2)
    appendFrame(x: 2, indices: [3], disposal: 1)
    appendFrame(x: 0, indices: [2], disposal: 3)
    appendFrame(x: 1, indices: [3], disposal: 1)
    appendFrame(x: 0, indices: [0, 2], disposal: 1)
    bytes.append(0x3b)
    let data = Data(bytes)
    let playback = try WebsiteConfigBackgroundPlayback(image: prepare(data))
    XCTAssertEqual(playback.image.frames.count, 6)
    let red: [UInt8] = [255, 0, 0, 255], blue: [UInt8] = [0, 0, 255, 255]
    let green: [UInt8] = [0, 255, 0, 255], clear: [UInt8] = [0, 0, 0, 0]
    let expected = [red + red + red, red + blue + red, red + clear + green,
      blue + clear + green, red + green + green, red + blue + green]
    let renderer = WebsiteConfigBackgroundRasterizer(useSoftwareRenderer: true)
    let box = CGRect(x: 0, y: 0, width: 3, height: 1)
    var elapsed = 0.001
    for index in 0..<6 {
      let sample = try playback.sample(elapsed: elapsed)
      XCTAssertEqual(sample.frameIndex, index)
      XCTAssertEqual(try pixels(sample.frame.image), expected[index], "Decoded composited frame \(index)")
      let result = try renderer.renderViewport(frame: sample.frame,
        layout: .init(imageBox: box, transform: .identity, transformedBounds: box),
        fit: .max, filter: .init(), viewport: box.size, pointsPerRem: 16, pixelsPerPoint: 1,
        sampling: .nearest)
      XCTAssertEqual(try pixels(result), expected[index], "Timed viewport frame \(index)")
      elapsed += playback.durations[index]
    }
    XCTAssertNil(try playback.sample(elapsed: elapsed).timeUntilNextFrame)
    XCTAssertEqual(playback.image.encodedData, data)
  }

  private func assertViewport(_ playback: WebsiteConfigBackgroundPlayback, first: [UInt8], second: [UInt8]) throws {
    let renderer = WebsiteConfigBackgroundRasterizer(useSoftwareRenderer: true)
    let box = CGRect(x: 0, y: 0, width: 2, height: 1)
    for (elapsed, color) in [(0.0, first), (0.03, second), (playback.cycleDuration, first),
      (playback.cycleDuration * 2, second)] {
      let sample = try playback.sample(elapsed: elapsed)
      let result = try renderer.renderViewport(frame: sample.frame,
        layout: .init(imageBox: box, transform: .identity, transformedBounds: box),
        fit: .max, filter: .init(), viewport: box.size, pointsPerRem: 16, pixelsPerPoint: 1,
        sampling: .nearest)
      XCTAssertEqual(try pixels(result), color + color)
    }
  }
}
