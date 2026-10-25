// Manual, bounded QA probe: swift Scripts/diagnose-hidden-wheel.swift
// No Typebar code, user store, event posting, visible window or activation.
import AppKit
import SwiftUI

@MainActor func firstScrollView(in view: NSView) -> NSScrollView? {
  if let scroll = view as? NSScrollView { return scroll }
  for child in view.subviews {
    if let scroll = firstScrollView(in: child) { return scroll }
  }
  return nil
}

@MainActor func diagnose() {
  _ = NSApplication.shared
  let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 1000, height: 720),
    styleMask: .borderless, backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.contentView = nil; window.close() }
  let host = NSHostingView(rootView: ScrollView {
    Text(String(repeating: "Owned diagnostic line\n", count: 200)).frame(maxWidth: .infinity)
  })
  let native = NSScrollView(frame: .init(x: 0, y: 0, width: 1000, height: 720))
  native.hasVerticalScroller = true
  native.documentView = NSView(frame: .init(x: 0, y: 0, width: 1000, height: 3200))
  for content: NSView in [native, host] {
    window.contentView = content
    for _ in 0..<10 {
      content.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    guard let scroll = firstScrollView(in: content) else {
      print("Missing diagnostic scroll view"); continue
    }
    scroll.tile()
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    scroll.contentView.scroll(to: .init(x: 0, y: 500))
    scroll.reflectScrolledClipView(scroll.contentView)
    for delta: Int32 in [-8, 8] {
      guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .line,
        wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0) else { fatalError("Missing CGEvent") }
      cg.flags = []
      guard let event = NSEvent(cgEvent: cg) else { fatalError("Missing NSEvent") }
      let before = scroll.contentView.bounds.minY
      scroll.scrollWheel(with: event)
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      print("owner=\(type(of: scroll)) delta=\(event.scrollingDeltaY) flags=\(event.modifierFlags.rawValue) window=\(event.windowNumber) before=\(before) after=\(scroll.contentView.bounds.minY) flipped=\(scroll.documentView?.isFlipped as Any)")
    }
  }
  precondition(!window.isVisible)
  print("Window stayed hidden. This probe does not establish physical wheel behavior.")
}

MainActor.assumeIsolated { diagnose() }
