import CoreGraphics
import XCTest
@testable import Typebar

final class WebsiteConfigBackgroundGeometryTests: XCTestCase {
  private let viewport = CGSize(width: 800, height: 600)
  private let intrinsic = CGSize(width: 100, height: 50)
  private func layout(_ value: WebsiteConfigBackgroundGeometry, root: Double = 16) throws -> WebsiteConfigBackgroundGeometry.Layout {
    try value.resolve(viewport: viewport, intrinsicSize: intrinsic, pointsPerRem: root)
  }

  func testPositiveOverdrawAndCenterScaleAreSeparateFromObjectFit() throws {
    let state = WebsiteConfigBackgroundGeometry(blurRem: 0.25)
    let result = try layout(state)
    XCTAssertEqual(result.imageBox, CGRect(x: -16, y: -16, width: 832, height: 632))
    XCTAssertEqual(result.transform.a, 1.0025, accuracy: 1e-10)
    XCTAssertEqual(result.transformedBounds.minX, -17.04, accuracy: 1e-8)
    XCTAssertEqual(result.transformedBounds.minY, -16.79, accuracy: 1e-8)
    XCTAssertEqual(result.transformedBounds.width, 834.08, accuracy: 1e-8)
  }

  func testNegativeBlurUpdatesDimensionsAndScaleButKeepsOldTopAndFilter() throws {
    var geometry = WebsiteConfigBackgroundGeometry(blurRem: 0.25)
    var filter = WebsiteConfigBackgroundFilter()
    _ = filter.apply(.init(blurRem: 0.25, brightness: 1, saturation: 1, opacity: 1))
    XCTAssertEqual(geometry.apply(blurRem: -1), .init(dimensions: true, top: false, transform: true))
    XCTAssertEqual(filter.apply(.init(blurRem: -1, brightness: 1, saturation: 1, opacity: 1)), .ignoredInvalidDeclaration)
    XCTAssertEqual(filter.stages, [.blur(rem: 0.25)])
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(x: 64, y: -16, width: 672, height: 472))
    XCTAssertEqual(geometry.topRem, -1); XCTAssertEqual(geometry.scale, 0.99)
    let narrow = try geometry.resolve(viewport: .init(width: 100, height: 600), intrinsicSize: intrinsic, pointsPerRem: 16)
    XCTAssertEqual(narrow.imageBox, CGRect(x: 50, y: -16, width: 0, height: 472))
  }

  func testNewInvalidImageUsesIntrinsicAutoSizeAndDoesNotBorrowOldDeclarationHistory() throws {
    var geometry = WebsiteConfigBackgroundGeometry(blurRem: .infinity)
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(x: 350, y: 275, width: 100, height: 50))
    _ = geometry.apply(blurRem: -1)
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(x: 64, y: 64, width: 672, height: 472))
    XCTAssertNil(geometry.topRem)
    XCTAssertEqual(geometry.apply(blurRem: .nan), .init(dimensions: false, top: false, transform: false))
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(x: 64, y: 64, width: 672, height: 472))
    XCTAssertEqual(try layout(.init(blurRem: -.infinity)).imageBox, CGRect(x: 350, y: 275, width: 100, height: 50))
  }

  func testRootReflowKeepsRelativeLengthsAndDefaultZeroResetsGeometry() throws {
    var geometry = WebsiteConfigBackgroundGeometry(blurRem: 0.25)
    XCTAssertEqual(try layout(geometry, root: 32).imageBox, CGRect(x: -32, y: -32, width: 864, height: 664))
    XCTAssertEqual(geometry.expansionRem, 2)
    _ = geometry.apply(blurRem: -0.0)
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(origin: .zero, size: viewport))
    XCTAssertEqual(try layout(geometry).transform, .identity)
  }

  func testZeroAndNegativeScaleAreNotReplacedByPositiveBoundingRectApproximation() throws {
    let zero = try layout(.init(blurRem: -100))
    XCTAssertEqual(zero.imageBox.size, .zero); XCTAssertEqual(zero.transform.a, 0)
    let flipped = try WebsiteConfigBackgroundGeometry(blurRem: -200).resolve(
      viewport: .init(width: 20_000, height: 20_000), intrinsicSize: intrinsic, pointsPerRem: 1)
    XCTAssertEqual(flipped.imageBox, CGRect(x: 800, y: 800, width: 18_400, height: 18_400))
    XCTAssertEqual(flipped.transform.a, -1); XCTAssertEqual(flipped.transform.d, -1)
    XCTAssertEqual(CGPoint(x: 800, y: 800).applying(flipped.transform), CGPoint(x: 19_200, y: 19_200))
  }

  func testProjectionFailureIsExplicitAndDoesNotChangeAcceptedDeclarations() throws {
    var geometry = WebsiteConfigBackgroundGeometry(blurRem: 0.25)
    for root in [0.0, -1, .infinity, .nan] {
      XCTAssertThrowsError(try layout(geometry, root: root)) {
        XCTAssertEqual($0 as? WebsiteConfigBackgroundGeometry.Failure, .invalidEnvironment)
      }
    }
    for invalidViewport in [CGSize(width: -1, height: 600), .init(width: CGFloat.infinity, height: 600)] {
      XCTAssertThrowsError(try geometry.resolve(viewport: invalidViewport, intrinsicSize: intrinsic, pointsPerRem: 16))
    }
    XCTAssertThrowsError(try geometry.resolve(viewport: viewport, intrinsicSize: .zero, pointsPerRem: 16))
    XCTAssertEqual(geometry.apply(blurRem: .greatestFiniteMagnitude), .init(dimensions: false, top: false, transform: true))
    XCTAssertEqual(geometry.expansionRem, 2); XCTAssertEqual(geometry.topRem, -1)
    XCTAssertThrowsError(try layout(geometry)) {
      XCTAssertEqual($0 as? WebsiteConfigBackgroundGeometry.Failure, .unrepresentableGeometry)
    }
    XCTAssertGreaterThan(geometry.scale, 1e300)
    _ = geometry.apply(blurRem: 0)
    XCTAssertEqual(try layout(geometry).imageBox, CGRect(origin: .zero, size: viewport))
  }
}
