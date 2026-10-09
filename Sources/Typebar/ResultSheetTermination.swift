import AppKit
import SwiftUI

/// A finished result has no active attempt to protect. AppKit's modal-window
/// default can otherwise veto Quit before the application delegate gets to
/// check other windows' active long tests. Scope this only to result content.
struct ResultSheetTerminationBridge: NSViewRepresentable {
  func makeNSView(context: Context) -> ResultSheetTerminationView {
    ResultSheetTerminationView(frame: .zero)
  }

  func updateNSView(_ view: ResultSheetTerminationView, context: Context) {
    view.attach(to: view.window)
  }

  static func dismantleNSView(_ view: ResultSheetTerminationView, coordinator: ()) {
    view.detach()
  }
}

@MainActor
final class ResultSheetTerminationView: NSView {
  private weak var trackedWindow: NSWindow?
  private var originalPreventsTermination: Bool?

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if trackedWindow !== newWindow { detach() }
    super.viewWillMove(toWindow: newWindow)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    attach(to: window)
  }

  func attach(to candidate: NSWindow?) {
    if trackedWindow === candidate {
      candidate?.preventsApplicationTerminationWhenModal = false
      return
    }
    detach()
    guard let candidate else { return }
    originalPreventsTermination = candidate.preventsApplicationTerminationWhenModal
    trackedWindow = candidate
    candidate.preventsApplicationTerminationWhenModal = false
  }

  func detach() {
    if let trackedWindow, let originalPreventsTermination {
      trackedWindow.preventsApplicationTerminationWhenModal = originalPreventsTermination
    }
    trackedWindow = nil
    originalPreventsTermination = nil
  }
}
