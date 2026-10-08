import AppKit
import SwiftUI

struct TypingVisualFocusMouseBridge: NSViewRepresentable {
  let onMovement: (Double, Double) -> Void

  func makeNSView(context: Context) -> TypingVisualFocusMouseView {
    TypingVisualFocusMouseView()
  }

  func updateNSView(_ view: TypingVisualFocusMouseView, context: Context) {
    view.onMovement = onMovement
  }

  static func dismantleNSView(_ view: TypingVisualFocusMouseView, coordinator: ()) {
    view.onMovement = { _, _ in }
    view.removeMovementTracking()
  }
}

/// Only the practice content's visible rect in its key window is tracked.
/// No global/local event monitors, acceptsMouseMovedEvents mutation, cursor
/// hide count, first-responder change or event swallowing is required.
final class TypingVisualFocusMouseView: NSView {
  var onMovement: (Double, Double) -> Void = { _, _ in }
  private var movementArea: NSTrackingArea?

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func updateTrackingAreas() {
    removeMovementTracking()
    super.updateTrackingAreas()
    guard window != nil else { return }
    let area = NSTrackingArea(rect: .zero,
      options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
    movementArea = area
    addTrackingArea(area)
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    removeMovementTracking()
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateTrackingAreas()
  }

  func removeMovementTracking() {
    if let movementArea { removeTrackingArea(movementArea) }
    movementArea = nil
  }

  override func mouseMoved(with event: NSEvent) {
    receiveMovement(x: event.deltaX, y: event.deltaY, from: event.window)
  }

  func receiveMovement(x: Double, y: Double, from eventWindow: NSWindow?) {
    guard let window, eventWindow === window, window.isKeyWindow, window.attachedSheet == nil else { return }
    // Native device deltas, not a proven CSS-pixel conversion. Direction and
    // strict per-axis threshold are preserved; device scaling is manual QA.
    onMovement(x, y)
  }
}
