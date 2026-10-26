import AppKit
import SwiftUI

@MainActor protocol PracticeDisplayFrameRateConsumer: AnyObject {
  var displayFrameRate: Int { get set }
}

struct PracticeDisplayCadence: NSViewRepresentable {
  let consumer: any PracticeDisplayFrameRateConsumer
  func makeNSView(context: Context) -> PracticeDisplayCadenceView { .init() }
  func updateNSView(_ view: PracticeDisplayCadenceView, context: Context) { view.bind(to: consumer) }
}

@MainActor final class PracticeDisplayCadenceView: NSView {
  private(set) weak var consumer: (any PracticeDisplayFrameRateConsumer)?
  private var reported: Int?
  private var generation = UUID()
  func bind(to consumer: any PracticeDisplayFrameRateConsumer) {
    if self.consumer !== consumer {
      self.consumer = consumer
      generation = UUID(); reported = nil
    }
    report()
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    generation = UUID(); reported = nil
    if let window {
      NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSWindow.didChangeScreenNotification, object: window)
      NotificationCenter.default.addObserver(self, selector: #selector(report), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    report()
  }
  @objc func report() {
    guard let window, let consumer else { return }
    let rate = window.screen?.maximumFramesPerSecond ?? 60
    guard reported != rate else { return }
    reported = rate
    let capturedGeneration = generation
    Task { @MainActor [weak self, weak window, weak consumer] in
      guard let self, let window, let consumer, self.window === window,
        self.generation == capturedGeneration, self.consumer === consumer,
        self.reported == rate, (window.screen?.maximumFramesPerSecond ?? 60) == rate else { return }
      consumer.displayFrameRate = rate
    }
  }
  deinit { NotificationCenter.default.removeObserver(self) }
}
