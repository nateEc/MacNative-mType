import AppKit
import SwiftUI
import XCTest
@testable import Typebar

@MainActor final class CaretHostingSizingProbeTests: XCTestCase {
  private final class Host: NSHostingView<PromptCaretMarkerView> {
    var invalidations = 0
    override func invalidateIntrinsicContentSize() {
      invalidations += 1
      super.invalidateIntrinsicContentSize()
    }
  }

  func testFixedMarkerSizingOptionsPreserveNativeFramesAndRenderedContent() throws {
    for automaticSizing in [true, false] {
      let host = Host(rootView: .init(style: .block, accent: .red,
        rect: .init(x: 0, y: 0, width: 18, height: 32)))
      if !automaticSizing { host.sizingOptions = [] }
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 300, height: 120),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let container = NSView(frame: .init(x: 0, y: 0, width: 300, height: 120))
      window.contentView = container
      container.addSubview(host)
      defer { window.contentView = nil; window.close() }
      let start = ProcessInfo.processInfo.systemUptime
      for step in 0..<20 {
        let size = CGSize(width: 18 + step % 3, height: 32 + step % 2)
        host.rootView = .init(style: .block, accent: .red, rect: .init(origin: .zero, size: size))
        let frame = CGRect(origin: .init(x: step * 2, y: step), size: size)
        host.frame = frame
        container.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        XCTAssertEqual(host.frame, frame)
      }
      let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
      XCTAssertGreaterThan(center.alphaComponent, 0.1)
      XCTAssertGreaterThan(center.redComponent, center.greenComponent)
      XCTAssertFalse(window.isVisible)
      print("caret-sizing automatic=\(automaticSizing) invalidations=\(host.invalidations) duration=\(ProcessInfo.processInfo.systemUptime - start)")
    }
  }
}
