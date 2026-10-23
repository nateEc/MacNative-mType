import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundRasterizerTests: XCTestCase {
  private let space = CGColorSpace(name: CGColorSpace.sRGB)!
  private func image(_ bytes: [UInt8], width: Int = 1, height: Int = 1) throws -> CGImage {
    try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: space,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
  }
  private func pixels(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    try bytes.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: .init(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
  }
  private func filter(blur: Double = 0, brightness: Double = 1,
    saturation: Double = 1, opacity: Double = 1) -> WebsiteConfigBackgroundFilter {
    var result = WebsiteConfigBackgroundFilter()
    XCTAssertEqual(result.apply(.init(blurRem: blur, brightness: brightness, saturation: saturation,
      opacity: opacity)), .replaced)
    return result
  }
  private func assertPixels(_ image: CGImage, _ expected: [UInt8], tolerance: Int = 2,
    file: StaticString = #filePath, line: UInt = #line) throws {
    let actual = try pixels(image)
    XCTAssertEqual(actual.count, expected.count, file: file, line: line)
    for (a, b) in zip(actual, expected) {
      XCTAssertLessThanOrEqual(abs(Int(a) - Int(b)), tolerance,
        "\(actual) != \(expected)", file: file, line: line)
    }
  }

  func testIdentityPreservesCanvasDimensionsAndPremultipliedPixels() throws {
    let bytes: [UInt8] = [64, 32, 16, 128, 0, 0, 0, 0, 17, 93, 211, 255]
    let input = try image(bytes, width: 3)
    let output = try WebsiteConfigBackgroundRasterizer().render(canvas: input, filter: filter(),
      pointsPerRem: 16, pixelsPerPoint: 2)
    XCTAssertEqual(output.width, 3); XCTAssertEqual(output.height, 1)
    try assertPixels(output, bytes)
    try assertPixels(input, bytes, tolerance: 0)
  }

  func testEmptyFilterPreservesOriginalWideGamutContainerRatherThanConvertingIt() throws {
    let input = try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.displayP3)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data([200, 100, 20, 255]) as CFData)!, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let output = try WebsiteConfigBackgroundRasterizer().render(canvas: input, filter: filter(),
      pointsPerRem: 16, pixelsPerPoint: 1)
    XCTAssertTrue(output === input, "Removing the filter must not introduce an sRGB/8-bit conversion")
    XCTAssertEqual(output.colorSpace?.name, input.colorSpace?.name)
  }

  func testColorPaletteAgainstIndependentScalarOracleAcross64FilterCombinations() throws {
    let colors: [[UInt8]] = [[64, 64, 64, 255], [204, 0, 0, 255], [1, 2, 3, 255],
      [128, 64, 32, 255], [64, 32, 16, 128], [31, 23, 15, 64], [0, 0, 0, 0], [255, 255, 255, 255]]
    let input = try image(colors.flatMap { $0 }, width: colors.count)
    let renderer = WebsiteConfigBackgroundRasterizer()
    func clip(_ value: Double) -> Double { min(1, max(0, value)) }
    for brightness in [0.0, 0.25, 1, 2.5] {
      for saturation in [0.0, 0.5, 1, 3.5] {
        for opacity in [0.0, 0.4, 1, 2] {
          let expected = colors.flatMap { color -> [UInt8] in
            guard color[3] > 0 else { return [0, 0, 0, 0] }
            let rgb = color.prefix(3).map { clip(Double($0) / Double(color[3]) * brightness) }
            let gray = rgb[0] * 0.213 + rgb[1] * 0.715 + rgb[2] * 0.072
            let alpha = Double(color[3]) / 255 * min(opacity, 1)
            let result = rgb.map { UInt8((clip(gray + saturation * ($0 - gray)) * alpha * 255).rounded()) }
            return result + [UInt8((alpha * 255).rounded())]
          }
          try assertPixels(renderer.render(canvas: input,
            filter: filter(brightness: brightness, saturation: saturation, opacity: opacity),
            pointsPerRem: 16, pixelsPerPoint: 1), expected)
        }
      }
    }
  }

  func testBrightnessMultipliesSRGBRatherThanAddingOrMultiplyingLinearLight() throws {
    for software in [false, true] {
      let renderer = WebsiteConfigBackgroundRasterizer(useSoftwareRenderer: software)
      try assertPixels(renderer.render(canvas: image([64, 64, 64, 255]), filter: filter(brightness: 2),
        pointsPerRem: 16, pixelsPerPoint: 1), [128, 128, 128, 255])
      // Unpremultiplied RGB is doubled, then the final alpha multiplier is applied once.
      try assertPixels(renderer.render(canvas: image([64, 32, 16, 128]),
        filter: filter(brightness: 2, opacity: 0.5), pointsPerRem: 16, pixelsPerPoint: 1), [64, 32, 16, 64])
    }
  }

  func testCSSSaturationMatrixAndClampingBetweenOrderedOperations() throws {
    let renderer = WebsiteConfigBackgroundRasterizer()
    try assertPixels(renderer.render(canvas: image([255, 0, 0, 255]), filter: filter(saturation: 0),
      pointsPerRem: 16, pixelsPerPoint: 1), [54, 54, 54, 255])
    // 0.8*2 clips to 1 before desaturation; combining matrices first would yield 0.3408.
    try assertPixels(renderer.render(canvas: image([204, 0, 0, 255]),
      filter: filter(brightness: 2, saturation: 0, opacity: 0.5),
      pointsPerRem: 16, pixelsPerPoint: 1), [27, 27, 27, 128])
    try assertPixels(renderer.render(canvas: image([128, 64, 32, 255]),
      filter: filter(saturation: 2), pointsPerRem: 16, pixelsPerPoint: 1), [181, 53, 0, 255])
  }

  func testInvalidDeclarationKeepsPreviousPixelsAndDefaultClearsIt() throws {
    let renderer = WebsiteConfigBackgroundRasterizer(), input = try image([64, 64, 64, 255])
    var state = filter(brightness: 2)
    _ = state.apply(.init(blurRem: -1, brightness: 0, saturation: 0, opacity: 0))
    try assertPixels(renderer.render(canvas: input, filter: state, pointsPerRem: 16,
      pixelsPerPoint: 1), [128, 128, 128, 255])
    _ = state.apply(.init(blurRem: 0, brightness: 1, saturation: 1, opacity: 1))
    try assertPixels(renderer.render(canvas: input, filter: state, pointsPerRem: 16,
      pixelsPerPoint: 1), [64, 64, 64, 255])
  }

  func testGaussianSpreadUsesExplicitRemAndBackingScale() throws {
    let size = 129, center = size / 2
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size { for c in 0..<4 { bytes[(y * size + center) * 4 + c] = 255 } }
    let input = try image(bytes, width: size, height: size)
    let renderer = WebsiteConfigBackgroundRasterizer()
    for (rem, root, backing, sigma) in [(0.125, 16.0, 1.0, 2.0), (0.125, 16.0, 2.0, 4.0),
      (0.25, 8.0, 2.0, 4.0)] {
      let output = try pixels(renderer.render(canvas: input, filter: filter(blur: rem),
        pointsPerRem: root, pixelsPerPoint: backing))
      let weights = (0..<size).map { Double(output[(center * size + $0) * 4 + 3]) / 255 }
      let mass = weights.reduce(0, +)
      let variance = weights.enumerated().reduce(0.0) { $0 + pow(Double($1.offset - center), 2) * $1.element } / mass
      XCTAssertEqual(mass, 1, accuracy: 0.07)
      XCTAssertEqual(variance, sigma * sigma, accuracy: sigma * sigma * 0.15,
        "A similarly named native blur must still match the requested standard deviation")
      XCTAssertGreaterThan(weights[center - 2], 0)
      XCTAssertEqual(weights[center - 2], weights[center + 2], accuracy: 0.005)
      for distance in [0, 1, 2, 4] {
        let gaussian = exp(-pow(Double(distance), 2) / (2 * sigma * sigma)) / (sqrt(2 * .pi) * sigma)
        XCTAssertEqual(weights[center + distance], gaussian, accuracy: 0.012)
      }
    }
  }

  func testTransparentOutsideCanvasDoesNotClampEdgePixels() throws {
    let input = try image(Array(repeating: [UInt8](repeating: 255, count: 4), count: 32 * 32).flatMap { $0 },
      width: 32, height: 32)
    let output = try pixels(WebsiteConfigBackgroundRasterizer().render(canvas: input,
      filter: filter(blur: 0.125), pointsPerRem: 16, pixelsPerPoint: 1))
    XCTAssertLessThan(output[3], 150, "Transparent black, not a repeated edge, surrounds this finite canvas")
    XCTAssertGreaterThan(output[(16 * 32 + 16) * 4 + 3], 250)
  }

  func testRealPreparedPNGFrameCanBeRenderedWithoutChangingOwnedContainer() throws {
    let encoded = NSMutableData()
    let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try image([40, 80, 120, 255]), nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    let preferences = try WebsiteConfigNativePagePreferences(runtime: WebsiteConfigNativeProfile.defaultDocument().values)
    let resource = try WebsiteConfigBackgroundResource.prepare(preferences: preferences, local: .data(encoded as Data))
    guard case .ready(let prepared) = resource.state else { return XCTFail("Expected real decoded image") }
    let output = try WebsiteConfigBackgroundRasterizer().render(canvas: prepared.frames[0].image,
      filter: filter(brightness: 0.5), pointsPerRem: 16, pixelsPerPoint: 1)
    try assertPixels(output, [20, 40, 60, 255])
    XCTAssertEqual(prepared.encodedData, encoded as Data)
    try assertPixels(prepared.frames[0].image, [40, 80, 120, 255])
  }

  func testInvalidScaleAndResourceFailuresAreExplicitWithoutChangingRawIntent() throws {
    let renderer = WebsiteConfigBackgroundRasterizer(), input = try image([255, 255, 255, 255])
    for scale in [0.0, -1, .infinity, .nan] {
      XCTAssertThrowsError(try renderer.render(canvas: input, filter: filter(), pointsPerRem: scale,
        pixelsPerPoint: 1)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .invalidScale) }
      XCTAssertThrowsError(try renderer.render(canvas: input, filter: filter(), pointsPerRem: 16,
        pixelsPerPoint: scale)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .invalidScale) }
    }
    var limits = WebsiteConfigBackgroundRasterizer.Limits(); limits.pixels = 0
    XCTAssertThrowsError(try renderer.render(canvas: input, filter: filter(), pointsPerRem: 16,
      pixelsPerPoint: 1, limits: limits)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .invalidLimits) }
    limits.pixels = 1; limits.blurPixels = 1
    XCTAssertThrowsError(try renderer.render(canvas: input, filter: filter(blur: 1), pointsPerRem: 16,
      pixelsPerPoint: 1, limits: limits)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .resourceLimit) }
    let huge = filter(brightness: .greatestFiniteMagnitude)
    XCTAssertThrowsError(try renderer.render(canvas: input, filter: huge, pointsPerRem: 16,
      pixelsPerPoint: 1)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .unrepresentableStage) }
    XCTAssertEqual(huge.stages, [.brightness(multiplier: .greatestFiniteMagnitude)])
    let twoPixels = try image([255, 255, 255, 255, 255, 255, 255, 255], width: 2)
    XCTAssertThrowsError(try renderer.render(canvas: twoPixels, filter: filter(), pointsPerRem: 16,
      pixelsPerPoint: 1, limits: limits)) { XCTAssertEqual($0 as? WebsiteConfigBackgroundRasterizer.Failure, .resourceLimit) }
  }
}
