import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class PracticeBackdropSchedulingTests: XCTestCase {
  func testOnlyMovingHalosRequireTimelineDelivery() {
    for style in PracticeBackdropStyle.allCases {
      for reduceMotion in [false, true] {
        for systemReduceMotion in [false, true] {
          XCTAssertEqual(style.requiresTimeline(reduceMotion: reduceMotion,
            systemReduceMotion: systemReduceMotion),
            style == .halos && !reduceMotion && !systemReduceMotion)
        }
      }
    }
  }

  func testSolidBackgroundRetainsThemeAndResizeUpdatesWithoutTimeline() throws {
    func content(_ color: Color) -> PracticeBackdrop {
      .init(style: .solid, theme: .init(background: color, panel: .clear,
        accent: .clear, colorScheme: .light), reduceMotion: false)
    }
    let host = NSHostingView(rootView: content(.red))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100),
      styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    func pixel(in view: NSView) throws -> NSColor {
      view.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.03))
      let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
      view.cacheDisplay(in: view.bounds, to: bitmap)
      return try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2,
        y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
    }
    for (color, size) in [(Color.red, CGSize(width: 200, height: 100)),
      (Color.blue, CGSize(width: 240, height: 120))] {
      host.rootView = content(color)
      window.contentView = host
      window.setContentSize(size)
      let actual = try pixel(in: host)
      // Resolve semantic SwiftUI colors through the same window/rendering path.
      let reference = NSHostingView(rootView: color)
      window.contentView = reference
      let expected = try pixel(in: reference)
      XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.02)
      XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.02)
      XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.02)
      XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.02)
    }
    XCTAssertFalse(window.isVisible)
  }
}
