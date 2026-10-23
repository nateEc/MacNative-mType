import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundViewportRasterTests: XCTestCase {
  private let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
    [255, 255, 0, 255], [255, 0, 255, 255], [0, 255, 255, 255]]
  private let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
  private func frame(_ bytes: [UInt8], width: Int, height: Int, orientation: Int = 1,
    space: CGColorSpace? = nil) throws -> WebsiteConfigBackgroundResource.Frame {
    let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: space ?? srgb,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    return .init(image: image, properties: [kCGImagePropertyOrientation: orientation] as CFDictionary)
  }
  private func pixels(_ image: CGImage) throws -> [UInt8] {
    var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try result.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: image.colorSpace ?? srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
    }
    return result
  }
  private func layout(_ box: CGRect, transform: CGAffineTransform = .identity) -> WebsiteConfigBackgroundGeometry.Layout {
    .init(imageBox: box, transform: transform, transformedBounds: box.applying(transform))
  }
  private func blur(_ amount: Double) -> WebsiteConfigBackgroundFilter {
    var filter = WebsiteConfigBackgroundFilter()
    _ = filter.apply(.init(blurRem: amount, brightness: 1, saturation: 1, opacity: 1))
    return filter
  }

  func testThreeFitModesProduceActualViewportPixels() throws {
    let row = Array(colors.prefix(4)).flatMap { $0 }
    let source = try frame(row + row, width: 4, height: 2)
    let renderer = WebsiteConfigBackgroundRasterizer()
    let empty = [UInt8](repeating: 0, count: 16)
    let expected: [CustomBackgroundFit: [UInt8]] = [
      .contain: empty + row + row + empty,
      .max: Array(repeating: row, count: 4).flatMap { $0 },
      .cover: Array(repeating: colors[1] + colors[1] + colors[2] + colors[2], count: 4).flatMap { $0 }]
    for fit in CustomBackgroundFit.allCases {
      let output = try renderer.renderViewport(frame: source, layout: layout(.init(x: 0, y: 0, width: 4, height: 4)),
        fit: fit, filter: .init(), viewport: .init(width: 4, height: 4), pointsPerRem: 16,
        pixelsPerPoint: 1, sampling: .nearest)
      XCTAssertEqual(output.width, 4); XCTAssertEqual(output.height, 4)
      XCTAssertEqual(try pixels(output), expected[fit])
    }
  }

  func testEightMetadataDirectionsRemainCorrectThroughCompleteGraph() throws {
    let order = [[0, 1, 2, 3, 4, 5], [2, 1, 0, 5, 4, 3], [5, 4, 3, 2, 1, 0], [3, 4, 5, 0, 1, 2],
      [0, 3, 1, 4, 2, 5], [3, 0, 4, 1, 5, 2], [5, 2, 4, 1, 3, 0], [2, 5, 1, 4, 0, 3]]
    let renderer = WebsiteConfigBackgroundRasterizer()
    for orientation in 1...8 {
      let source = try frame(colors.flatMap { $0 }, width: 3, height: 2, orientation: orientation)
      let size = orientation < 5 ? CGSize(width: 3, height: 2) : CGSize(width: 2, height: 3)
      let output = try renderer.renderViewport(frame: source, layout: layout(CGRect(origin: .zero, size: size)),
        fit: .max, filter: .init(), viewport: size, pointsPerRem: 16, pixelsPerPoint: 1, sampling: .nearest)
      XCTAssertEqual(try pixels(output), order[orientation - 1].flatMap { colors[$0] }, "\(orientation)")
      XCTAssertEqual(source.orientation.rawValue, UInt32(orientation))
    }
  }

  func testAsymmetricTopHistoryUsesYDownLayoutAndBackingScale() throws {
    var geometry = WebsiteConfigBackgroundGeometry(blurRem: 0.25)
    _ = geometry.apply(blurRem: -1)
    let size = CGSize(width: 20, height: 20)
    let resolved = try geometry.resolve(viewport: size, intrinsicSize: .init(width: 1, height: 1), pointsPerRem: 1)
    let output = try WebsiteConfigBackgroundRasterizer().renderViewport(
      frame: frame(colors[0], width: 1, height: 1), layout: resolved, fit: .max, filter: .init(),
      viewport: size, pointsPerRem: 1, pixelsPerPoint: 2, sampling: .nearest)
    XCTAssertEqual(output.width, 40); XCTAssertEqual(output.height, 40)
    let bytes = try pixels(output)
    XCTAssertEqual(Array(bytes[((2 * 40 + 20) * 4)..<((2 * 40 + 20) * 4 + 4)]), colors[0])
    XCTAssertEqual(Array(bytes[((34 * 40 + 20) * 4)..<((34 * 40 + 20) * 4 + 4)]), [0, 0, 0, 0])
  }

  func testBlurCanPaintOutsideBoxAndReadPixelsOutsideViewport() throws {
    let source = try frame([255, 255, 255, 255], width: 1, height: 1)
    let renderer = WebsiteConfigBackgroundRasterizer()
    let outsideBox = try renderer.renderViewport(frame: source,
      layout: layout(.init(x: 2, y: 2, width: 4, height: 4)), fit: .max, filter: blur(1),
      viewport: .init(width: 8, height: 8), pointsPerRem: 1, pixelsPerPoint: 1)
    XCTAssertGreaterThan(try pixels(outsideBox)[(3 * 8 + 1) * 4 + 3], 0)
    let outsideViewport = try renderer.renderViewport(frame: source,
      layout: layout(.init(x: -4, y: 0, width: 8, height: 8)), fit: .max, filter: blur(1),
      viewport: .init(width: 8, height: 8), pointsPerRem: 1, pixelsPerPoint: 1)
    let bytes = try pixels(outsideViewport)
    XCTAssertGreaterThan(bytes[(4 * 8) * 4 + 3], 235, "Viewport crop must not precede blur")
    XCTAssertLessThan(bytes[(4 * 8 + 7) * 4 + 3], 5)
  }

  func testScaleAfterBlurMagnifiesKernelRatherThanOnlyImageGeometry() throws {
    let source = try frame([255, 255, 255, 255], width: 1, height: 1)
    let size = CGSize(width: 128, height: 128)
    let transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 2, tx: -64, ty: -64)
    let output = try WebsiteConfigBackgroundRasterizer().renderViewport(frame: source,
      layout: layout(.init(x: 63.5, y: 0, width: 1, height: 128), transform: transform),
      fit: .max, filter: blur(1), viewport: size, pointsPerRem: 1, pixelsPerPoint: 1)
    let bytes = try pixels(output)
    let weights = (0..<128).map { Double(bytes[(64 * 128 + $0) * 4 + 3]) / 255 }
    let mass = weights.reduce(0, +)
    let center = weights.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element } / mass
    let variance = weights.enumerated().reduce(0.0) { $0 + pow(Double($1.offset) - center, 2) * $1.element } / mass
    XCTAssertGreaterThan(mass, 1)
    XCTAssertGreaterThan(variance, 3, "Applying blur after scale would leave a much narrower kernel")
    XCTAssertLessThan(variance, 7)
  }

  func testNoFilterKeepsP3AndFloatDynamicRangeWithoutIntermediateQuantization() throws {
    let renderer = WebsiteConfigBackgroundRasterizer()
    let p3 = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
    let source = try frame(colors.flatMap { $0 }, width: 3, height: 2, orientation: 4, space: p3)
    let output = try renderer.renderViewport(frame: source, layout: layout(.init(x: 0, y: 0, width: 3, height: 2)),
      fit: .max, filter: .init(), viewport: .init(width: 3, height: 2), pointsPerRem: 16,
      pixelsPerPoint: 1, sampling: .nearest)
    XCTAssertEqual(output.colorSpace?.name, p3.name)
    XCTAssertEqual(try pixels(output), [3, 4, 5, 0, 1, 2].flatMap { colors[$0] })
    let linear = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
    let values: [Float] = [1.5, 0.25, 0.125, 1]
    let data = values.withUnsafeBytes { Data($0) }
    let flags = CGBitmapInfo.floatComponents.union(.byteOrder32Little).union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
    let floatImage = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 32, bitsPerPixel: 128,
      bytesPerRow: 16, space: linear, bitmapInfo: flags, provider: CGDataProvider(data: data as CFData)!,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let floatOutput = try renderer.renderViewport(frame: .init(image: floatImage, properties: [:] as CFDictionary),
      layout: layout(.init(x: 0, y: 0, width: 2, height: 2)), fit: .max, filter: .init(),
      viewport: .init(width: 2, height: 2), pointsPerRem: 16, pixelsPerPoint: 1, sampling: .nearest)
    XCTAssertEqual(floatOutput.bitsPerComponent, 32)
    var received = [Float](repeating: 0, count: 16)
    try received.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 2, height: 2,
        bitsPerComponent: 32, bytesPerRow: 32, space: linear, bitmapInfo: flags.rawValue))
      context.draw(floatOutput, in: .init(x: 0, y: 0, width: 2, height: 2))
    }
    for (actual, expected) in zip(received, Array(repeating: values, count: 4).flatMap { $0 }) {
      XCTAssertEqual(actual, expected, accuracy: 0.002)
    }
  }

  func testHiddenLayerAndFailurePathsAreExplicitAndKeepOriginalState() throws {
    let renderer = WebsiteConfigBackgroundRasterizer(), size = CGSize(width: 4, height: 4)
    let source = try frame(colors[0], width: 1, height: 1)
    let normal = layout(CGRect(origin: .zero, size: size))
    var limits = WebsiteConfigBackgroundRasterizer.Limits(); limits.pixels = 3
    XCTAssertThrowsError(try renderer.renderViewport(frame: source, layout: normal, fit: .max,
      filter: .init(), viewport: size, pointsPerRem: 16, pixelsPerPoint: 1, limits: limits)) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .resourceLimit)
    }
    limits.pixels = 100; limits.renderedBytes = 1
    XCTAssertThrowsError(try renderer.renderViewport(frame: source, layout: normal, fit: .max,
      filter: .init(), viewport: size, pointsPerRem: 16, pixelsPerPoint: 1, limits: limits))
    let zero = CGAffineTransform(a: 0, b: 0, c: 0, d: 0, tx: 2, ty: 2)
    let output = try renderer.renderViewport(frame: source, layout: layout(normal.imageBox, transform: zero),
      fit: .max, filter: blur(1), viewport: size, pointsPerRem: 16, pixelsPerPoint: 1)
    XCTAssertEqual(try pixels(output), [UInt8](repeating: 0, count: 64))
    XCTAssertEqual(source.image.width, 1); XCTAssertEqual(source.orientation, .up)
  }

  func testSmallTransformedContentDoesNotBudgetTheEntireEmptyInverseViewport() throws {
    let source = try frame(colors[0], width: 1, height: 1)
    var limits = WebsiteConfigBackgroundRasterizer.Limits(); limits.pixels = 4096
    let transform = CGAffineTransform(a: 0.1, b: 0, c: 0, d: 0.1, tx: 14.4, ty: 14.4)
    let output = try WebsiteConfigBackgroundRasterizer().renderViewport(frame: source,
      layout: layout(.init(x: 0, y: 0, width: 32, height: 32), transform: transform), fit: .max,
      filter: .init(), viewport: .init(width: 32, height: 32), pointsPerRem: 16,
      pixelsPerPoint: 1, sampling: .nearest, limits: limits)
    let bytes = try pixels(output)
    XCTAssertEqual(Array(bytes[((16 * 32 + 16) * 4)..<((16 * 32 + 16) * 4 + 4)]), colors[0])
    XCTAssertEqual(Array(bytes.prefix(4)), [0, 0, 0, 0])
  }

  func testNegativeCSSMatrixReversesPixelsRatherThanOnlyUsingPositiveBounds() throws {
    let source = try frame(Array(colors.prefix(4)).flatMap { $0 }, width: 2, height: 2)
    let transform = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 2, ty: 2)
    let output = try WebsiteConfigBackgroundRasterizer().renderViewport(frame: source,
      layout: layout(.init(x: 0, y: 0, width: 2, height: 2), transform: transform), fit: .max,
      filter: .init(), viewport: .init(width: 2, height: 2), pointsPerRem: 16,
      pixelsPerPoint: 1, sampling: .nearest)
    XCTAssertEqual(try pixels(output), [3, 2, 1, 0].flatMap { colors[$0] })
  }

  func testFractionalViewportRoundsDeviceCanvasWithoutStretchingLogicalContent() throws {
    let row = Array(colors.prefix(4)).flatMap { $0 }
    let source = try frame(row + row, width: 4, height: 2)
    let output = try WebsiteConfigBackgroundRasterizer().renderViewport(frame: source,
      layout: layout(.init(x: 0, y: 0, width: 3.25, height: 3.25)), fit: .max,
      filter: .init(), viewport: .init(width: 3.25, height: 3.25), pointsPerRem: 16,
      pixelsPerPoint: 2, sampling: .nearest)
    XCTAssertEqual(output.width, 7); XCTAssertEqual(output.height, 7)
    let bytes = try pixels(output)
    let expected = [0, 0, 1, 2, 2, 3].flatMap { colors[$0] }
    XCTAssertEqual(Array(bytes[(3 * 7 * 4)..<(3 * 7 * 4 + 24)]), expected)
  }

  func testRenderedByteBudgetIncludesActualRowStride() throws {
    let source = try frame(colors.flatMap { $0 }, width: 3, height: 2)
    let renderer = WebsiteConfigBackgroundRasterizer()
    let resolved = layout(.init(x: 0, y: 0, width: 5, height: 3))
    let output = try renderer.renderViewport(frame: source, layout: resolved, fit: .max,
      filter: .init(), viewport: .init(width: 5, height: 3), pointsPerRem: 16,
      pixelsPerPoint: 1, sampling: .nearest)
    var limits = WebsiteConfigBackgroundRasterizer.Limits()
    limits.renderedBytes = output.bytesPerRow * output.height - 1
    XCTAssertThrowsError(try renderer.renderViewport(frame: source, layout: resolved, fit: .max,
      filter: .init(), viewport: .init(width: 5, height: 3), pointsPerRem: 16,
      pixelsPerPoint: 1, sampling: .nearest, limits: limits)) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .resourceLimit)
    }
  }
}
