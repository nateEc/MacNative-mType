import CoreGraphics
import Foundation
import XCTest
@testable import Typebar

@MainActor
final class WebsiteConfigBackgroundObjectFitTests: XCTestCase {
  private let space = CGColorSpace(name: CGColorSpace.sRGB)!
  private let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255]
  private let blue: [UInt8] = [0, 0, 255, 255], yellow: [UInt8] = [255, 255, 0, 255]
  private let clear: [UInt8] = [0, 0, 0, 0]
  private func source() throws -> CGImage {
    try XCTUnwrap(CGImage(width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
      space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data((red + green + blue + yellow) + (red + green + blue + yellow)) as CFData)!,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }
  private func context(width: Int = 4, height: Int = 4) throws -> CGContext {
    let result = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    result.interpolationQuality = .none
    result.setShouldAntialias(false)
    return result
  }
  private func bytes(_ context: CGContext) throws -> [UInt8] {
    Array(UnsafeBufferPointer(start: try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self),
      count: context.bytesPerRow * context.height))
  }

  func testCenteredPlacementForWideTallFractionalAndTranslatedBoxes() throws {
    let box = CGRect(x: 11, y: -7, width: 120, height: 80)
    XCTAssertEqual(try WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 400, height: 100),
      in: box, fit: .cover), CGRect(x: -89, y: -7, width: 320, height: 80))
    XCTAssertEqual(try WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 400, height: 100),
      in: box, fit: .contain), CGRect(x: 11, y: 18, width: 120, height: 30))
    XCTAssertEqual(try WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 100, height: 400),
      in: box, fit: .contain), CGRect(x: 61, y: -7, width: 20, height: 80))
    XCTAssertEqual(try WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 400, height: 100),
      in: box, fit: .max), box, "Source max clears object-fit, whose initial value is fill")
    XCTAssertEqual(try WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 3, height: 2),
      in: .init(x: 0, y: 0, width: 4.5, height: 4.5), fit: .contain),
      CGRect(x: 0, y: 0.75, width: 4.5, height: 3))
  }

  func testActualContainPixelsHaveTransparentLetterboxAndUnstretchedColumns() throws {
    let canvas = try context()
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: .init(x: 0, y: 0, width: 4, height: 4),
      fit: .contain, context: canvas)
    let empty = Array(repeating: clear, count: 4).flatMap { $0 }, row = red + green + blue + yellow
    XCTAssertEqual(try bytes(canvas), empty + row + row + empty)
  }

  func testActualCoverPixelsCropCenteredContentWhileMaxStretchesEveryColumn() throws {
    let covered = try context(), stretched = try context()
    let box = CGRect(x: 0, y: 0, width: 4, height: 4)
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: box, fit: .cover, context: covered)
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: box, fit: .max, context: stretched)
    XCTAssertEqual(try bytes(covered), Array(repeating: green + green + blue + blue, count: 4).flatMap { $0 })
    XCTAssertEqual(try bytes(stretched), Array(repeating: red + green + blue + yellow, count: 4).flatMap { $0 })
  }

  func testBackingScaleIsOwnedByCallerAndDoesNotChangeLogicalObjectPlacement() throws {
    let canvas = try context(width: 8, height: 8)
    canvas.scaleBy(x: 2, y: 2)
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: .init(x: 0, y: 0, width: 4, height: 4),
      fit: .contain, context: canvas)
    let empty = Array(repeating: clear, count: 8).flatMap { $0 }
    let row = red + red + green + green + blue + blue + yellow + yellow
    XCTAssertEqual(try bytes(canvas), empty + empty + row + row + row + row + empty + empty)
    XCTAssertEqual(canvas.ctm.a, 2); XCTAssertEqual(canvas.ctm.d, 2)
  }

  func testDrawingRespectsAndRestoresCallerClipAndTransform() throws {
    let canvas = try context(width: 8, height: 4)
    canvas.translateBy(x: 1, y: 0)
    canvas.clip(to: .init(x: 0, y: 0, width: 6, height: 4))
    let transform = canvas.ctm, clip = canvas.boundingBoxOfClipPath
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: .init(x: 1, y: 1, width: 4, height: 2),
      fit: .cover, context: canvas)
    XCTAssertEqual(canvas.ctm, transform); XCTAssertEqual(canvas.boundingBoxOfClipPath, clip)
    let actual = try bytes(canvas)
    XCTAssertEqual(Array(actual.prefix(8 * 4)), Array(repeating: 0, count: 8 * 4))
    XCTAssertEqual(Array(actual[(8 * 4)..<(16 * 4)]), clear + clear + red + green + blue + yellow + clear + clear)
    canvas.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    canvas.fill(.init(x: 0, y: 0, width: 1, height: 1))
    let afterFill = try bytes(canvas)
    let whitePixelIndices = (0..<32).filter {
      Array(afterFill[($0 * 4)..<($0 * 4 + 4)]) == [255, 255, 255, 255]
    }
    // Bitmap memory rows run top-to-bottom; user-space y=0 is the bottom row.
    XCTAssertEqual(whitePixelIndices, [25], "Temporary object clip must be gone and caller transform preserved")
  }

  func testDrawingAlsoPreservesCurrentPathWhichIsNotPartOfSavedGraphicsState() throws {
    let canvas = try context()
    canvas.move(to: .init(x: 0.25, y: 0.5))
    canvas.addCurve(to: .init(x: 3, y: 3), control1: .init(x: 1, y: 2), control2: .init(x: 2, y: 1))
    let path = try XCTUnwrap(canvas.path)
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: .init(x: 0, y: 0, width: 4, height: 4),
      fit: .contain, context: canvas)
    XCTAssertEqual(canvas.path, path)
  }

  func testFitCanvasFeedsExistingPixelPipelineWithoutFillingTransparentBars() throws {
    let canvas = try context()
    try WebsiteConfigBackgroundObjectFit.draw(source(), in: .init(x: 0, y: 0, width: 4, height: 4),
      fit: .contain, context: canvas)
    var filter = WebsiteConfigBackgroundFilter()
    _ = filter.apply(.init(blurRem: 0, brightness: 0.5, saturation: 1, opacity: 1))
    let rendered = try WebsiteConfigBackgroundRasterizer().render(canvas: XCTUnwrap(canvas.makeImage()),
      filter: filter, pointsPerRem: 16, pixelsPerPoint: 1)
    let result = try context()
    result.draw(rendered, in: .init(x: 0, y: 0, width: 4, height: 4))
    let actual = try bytes(result)
    XCTAssertEqual(Array(actual.prefix(16)), Array(repeating: 0, count: 16))
    XCTAssertEqual(Array(actual.suffix(16)), Array(repeating: 0, count: 16))
    for (a, b) in zip(actual[16..<32], [128, 0, 0, 255, 0, 128, 0, 255, 0, 0, 128, 255, 128, 128, 0, 255]) {
      XCTAssertLessThanOrEqual(abs(Int(a) - b), 1)
    }
  }

  func testDegenerateInvalidAndUnrepresentableGeometryDoNotDraw() throws {
    let size = CGSize(width: 4, height: 2)
    XCTAssertNil(try WebsiteConfigBackgroundObjectFit.placement(imageSize: size, in: .zero, fit: .cover))
    for invalid in [CGSize(width: 0, height: 1), .init(width: -1, height: 1), .init(width: CGFloat.infinity, height: 1)] {
      XCTAssertThrowsError(try WebsiteConfigBackgroundObjectFit.placement(imageSize: invalid,
        in: .init(x: 0, y: 0, width: 4, height: 4), fit: .contain))
    }
    XCTAssertThrowsError(try WebsiteConfigBackgroundObjectFit.placement(imageSize: size,
      in: .init(x: 0, y: 0, width: -1, height: 1), fit: .cover))
    let canvas = try context()
    XCTAssertThrowsError(try WebsiteConfigBackgroundObjectFit.draw(source(),
      in: .init(x: CGFloat.infinity, y: 0, width: 4, height: 4), fit: .max, context: canvas))
    XCTAssertEqual(try bytes(canvas), Array(repeating: 0, count: 64))
    XCTAssertThrowsError(try WebsiteConfigBackgroundObjectFit.placement(
      imageSize: .init(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.greatestFiniteMagnitude),
      in: .init(x: 0, y: 0, width: 4, height: 4), fit: .cover))
  }
}

@MainActor
final class WebsiteConfigBackgroundObjectFitSourceTests: XCTestCase {
  func testActualPinnedSizeSetterClearsMaxRatherThanChoosingContainOrCover() throws {
    let environment = ProcessInfo.processInfo.environment
    guard let reference = environment["TYPEBAR_WEBSITE_CONFIG_REFERENCE_ROOT"] ?? environment["TYPEBAR_REFERENCE_ROOT"]
    else { throw XCTSkip("Requires pinned reference checkout") }
    struct Fixture: Decodable { let fit: String, objectFit: String }
    struct Result: Decodable { let pin: String; let fitFixtures: [Fixture] }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(), output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["node", root.appendingPathComponent("Scripts/check-source-background-filter.mjs").path, reference]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    let result = try JSONDecoder().decode(Result.self, from: data)
    XCTAssertEqual(result.pin, "91bd24bb8513785c7364cbea29296ff7adafac41")
    XCTAssertEqual(result.fitFixtures.count, 3)
    XCTAssertEqual(Set(result.fitFixtures.map(\.fit)), Set(CustomBackgroundFit.allCases.map(\.rawValue)))
    for fixture in result.fitFixtures {
      let fit = try XCTUnwrap(CustomBackgroundFit(rawValue: fixture.fit))
      XCTAssertEqual(fixture.objectFit, fit == .max ? "" : fixture.fit)
      let box = CGRect(x: 0, y: 0, width: 4, height: 4)
      let placement = try XCTUnwrap(WebsiteConfigBackgroundObjectFit.placement(imageSize: .init(width: 4, height: 2),
        in: box, fit: fit))
      if fixture.objectFit.isEmpty { XCTAssertEqual(placement, box) }
      else { XCTAssertEqual(placement.width / placement.height, 2) }
    }
  }
}
