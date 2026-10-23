import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundOrientationTests: XCTestCase {
  private let palette: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
    [255, 255, 0, 255], [255, 0, 255, 255], [0, 255, 255, 255]]
  // Independent top-to-bottom pixel oracle for a 3-column, 2-row encoded image.
  private let order: [[Int]] = [[0, 1, 2, 3, 4, 5], [2, 1, 0, 5, 4, 3],
    [5, 4, 3, 2, 1, 0], [3, 4, 5, 0, 1, 2], [0, 3, 1, 4, 2, 5],
    [3, 0, 4, 1, 5, 2], [5, 2, 4, 1, 3, 0], [2, 5, 1, 4, 0, 3]]
  private func image(space: CGColorSpace? = nil) throws -> CGImage {
    try XCTUnwrap(CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
      space: space ?? CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(palette.flatMap { $0 }) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
  }
  private func context(width: Int, height: Int, space: CGColorSpace? = nil) throws -> CGContext {
    let result = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: space ?? CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    result.clear(.init(x: 0, y: 0, width: width, height: height))
    result.interpolationQuality = .none; result.setShouldAntialias(false)
    return result
  }
  private func bytes(_ context: CGContext) throws -> [UInt8] {
    Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self),
      count: context.bytesPerRow * context.height))
  }

  func testAllEightOrientationsAgainstIndependentUniquePixelOracle() throws {
    let source = try image()
    for value in UInt32(1)...8 {
      let orientation = try XCTUnwrap(CGImagePropertyOrientation(rawValue: value))
      let width = value <= 4 ? 3 : 2, height = value <= 4 ? 2 : 3
      let canvas = try context(width: width, height: height)
      try WebsiteConfigBackgroundObjectFit.draw(source, in: .init(x: 0, y: 0, width: width, height: height),
        fit: .max, orientation: orientation, context: canvas)
      XCTAssertEqual(try bytes(canvas), order[Int(value) - 1].flatMap { palette[$0] }, "Orientation \(value)")
    }
    XCTAssertEqual(source.width, 3); XCTAssertEqual(source.height, 2)
  }

  func testOrientationIsAppliedBeforeContainDeterminesAspectRatio() throws {
    let canvas = try context(width: 6, height: 6)
    try WebsiteConfigBackgroundObjectFit.draw(image(), in: .init(x: 0, y: 0, width: 6, height: 6),
      fit: .contain, orientation: .right, context: canvas)
    let expectedRows = [[3, 0], [3, 0], [4, 1], [4, 1], [5, 2], [5, 2]]
    var expected: [UInt8] = []
    for row in expectedRows {
      expected.append(contentsOf: [UInt8](repeating: 0, count: 4))
      for column in [row[0], row[0], row[1], row[1]] { expected.append(contentsOf: palette[column]) }
      expected.append(contentsOf: [UInt8](repeating: 0, count: 4))
    }
    XCTAssertEqual(try bytes(canvas), expected, "Rotated natural size is 2×3, not 3×2")
  }

  func testFrameMetadataIsLocalAndMalformedValuesDoNotInventMirroring() throws {
    let source = try image()
    for raw in 1...8 {
      let frame = WebsiteConfigBackgroundResource.Frame(image: source,
        properties: [kCGImagePropertyOrientation: raw] as CFDictionary)
      XCTAssertEqual(frame.orientation.rawValue, UInt32(raw))
    }
    let invalid: [Any] = [0, 9, -1, 2.5, Double.infinity, Double.nan, "6", NSNull()]
    for value in invalid {
      let frame = WebsiteConfigBackgroundResource.Frame(image: source,
        properties: [kCGImagePropertyOrientation: value] as CFDictionary)
      XCTAssertEqual(frame.orientation, .up)
    }
    XCTAssertEqual(WebsiteConfigBackgroundResource.Frame(image: source, properties: [:] as CFDictionary).orientation, .up)
  }

  func testActualJPEGPreparationFeedsOrientedDrawingWithoutReencodingOrMetadataMutation() throws {
    let data = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
    // Do not infer [CFString: Double]: ImageIO requires an integer orientation tag.
    let options: [CFString: Any] = [kCGImagePropertyOrientation: NSNumber(value: Int32(6)),
      kCGImageDestinationLossyCompressionQuality: NSNumber(value: 1.0)]
    CGImageDestinationAddImage(destination, try image(), options as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let original = data as Data
    let preferences = try WebsiteConfigNativePagePreferences(runtime: WebsiteConfigNativeProfile.defaultDocument().values)
    let resource = try WebsiteConfigBackgroundResource.prepare(preferences: preferences, local: .data(original))
    guard case .ready(let prepared) = resource.state else { return XCTFail("Expected real decoded JPEG") }
    let frame = try XCTUnwrap(prepared.frames.first)
    XCTAssertEqual(frame.orientation, .right)
    XCTAssertEqual(frame.image.width, 3); XCTAssertEqual(frame.image.height, 2)
    // Compare to the actual decoded colors, not an assumption of lossless JPEG.
    let raw = try context(width: 3, height: 2)
    raw.draw(frame.image, in: .init(x: 0, y: 0, width: 3, height: 2))
    let rawBytes = try bytes(raw)
    let decodedColors = (0..<6).map { Array(rawBytes[($0 * 4)..<($0 * 4 + 4)]) }
    let output = try context(width: 2, height: 3)
    try WebsiteConfigBackgroundObjectFit.draw(frame, in: .init(x: 0, y: 0, width: 2, height: 3),
      fit: .max, context: output)
    XCTAssertEqual(try bytes(output), order[5].flatMap { decodedColors[$0] })
    XCTAssertEqual(prepared.encodedData, original)
    XCTAssertEqual((frame.properties as NSDictionary)[kCGImagePropertyOrientation] as? NSNumber, 6)
  }

  func testOrientedDrawingPreservesBackingScaleClipAndCurrentPath() throws {
    let canvas = try context(width: 4, height: 6)
    canvas.scaleBy(x: 2, y: 2)
    canvas.clip(to: .init(x: 0, y: 0, width: 2, height: 3))
    canvas.move(to: .init(x: 0.25, y: 0.5)); canvas.addLine(to: .init(x: 1.5, y: 2.5))
    let path = canvas.path, ctm = canvas.ctm, clip = canvas.boundingBoxOfClipPath
    try WebsiteConfigBackgroundObjectFit.draw(image(), in: .init(x: 0, y: 0, width: 2, height: 3),
      fit: .max, orientation: .rightMirrored, context: canvas)
    XCTAssertEqual(canvas.path, path); XCTAssertEqual(canvas.ctm, ctm)
    XCTAssertEqual(canvas.boundingBoxOfClipPath, clip)
    let rows = [[5, 2], [5, 2], [4, 1], [4, 1], [3, 0], [3, 0]]
    XCTAssertEqual(try bytes(canvas), rows.flatMap { palette[$0[0]] + palette[$0[0]] + palette[$0[1]] + palette[$0[1]] })
  }

  func testOrientationUsesCallerP3SpaceWithoutAnIntermediateSRGBBitmap() throws {
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let canvas = try context(width: 3, height: 2, space: p3)
    try WebsiteConfigBackgroundObjectFit.draw(image(space: p3), in: .init(x: 0, y: 0, width: 3, height: 2),
      fit: .max, orientation: .downMirrored, context: canvas)
    XCTAssertEqual(try bytes(canvas), order[3].flatMap { palette[$0] })
    XCTAssertEqual(canvas.makeImage()?.colorSpace?.name, p3.name)
  }
}
