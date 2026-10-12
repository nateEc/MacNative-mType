import AppKit
import Observation
import SwiftUI
import XCTest
@testable import Typebar

/// Isolate framework animation scheduling from text generation and caret timers.
@MainActor final class VisualFocusAnimationHostTests: XCTestCase {
  @Observable final class State {
    var focused = false
  }
  private struct Fixture: View {
    let state: State
    let reducesMotion: Bool
    var body: some View {
      VStack {
        Text("configuration")
          .opacity(state.focused ? 0 : 1)
          .animation(reducesMotion ? nil : .easeInOut(duration: 0.125), value: state.focused)
        Text("typing target remains unchanged")
      }
      .frame(width: 600, height: 200)
    }
  }
  private final class Host: NSHostingView<Fixture> {
    var layouts = 0
    override func layout() { layouts += 1; super.layout() }
  }

  func testHiddenOpacityAnimationSettlesWithoutTextOrCaretUpdates() {
    for reducesMotion in [false, true] {
      let state = State()
      let host = Host(rootView: Fixture(state: state, reducesMotion: reducesMotion))
      let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 200),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      host.frame = .init(x: 0, y: 0, width: 600, height: 200)
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      let frame = host.frame, initial = host.layouts
      state.focused = true
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      let active = host.layouts - initial
      RunLoop.main.run(until: Date().addingTimeInterval(0.25))
      let settled = host.layouts
      RunLoop.main.run(until: Date().addingTimeInterval(0.1))
      print("isolated hidden opacity: reduced=\(reducesMotion) activeLayouts=\(active) settledLayouts=\(host.layouts - settled)")
      XCTAssertEqual(host.frame, frame)
      XCTAssertFalse(window.isVisible)
      XCTAssertEqual(host.layouts, settled, "Completed opacity animation must stop scheduling layout")
      window.contentView = nil
      window.close()
    }
  }
}
