import SwiftUI
import AppKit

enum WebsiteLayoutFluidFade {
  static func duration(reducedMotion: Bool) -> Double { reducedMotion ? 0 : 0.125 }
  static func opacity(from: Double, target: Double, elapsed: Double, duration: Double) -> Double {
    guard elapsed > 0 else { return from }
    guard duration > 0 else { return target }
    let t = min(1, elapsed / duration)
    let progress = 1 - (1 - t) * (1 - t)
    return from + (target - from) * progress
  }
}

@MainActor struct WebsiteLayoutFluidFadeModifier: ViewModifier {
  let request: WebsiteLayoutFluidCountdown.AnimationRequest?
  let currentRequestID: () -> UUID?
  let reducedMotion: Bool
  var collapsesWhenHidden = false
  var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  var frameInterval: () -> TimeInterval = { 1.0 / 60 }
  var didSample: (UUID?, Double) -> Void = { _, _ in }
  @State private var opacity = 0.0

  func body(content: Content) -> some View {
    content
      .opacity(opacity)
      .frame(height: collapsesWhenHidden && opacity == 0 && request?.target != 1 ? 0 : nil)
      .clipped()
      .transaction { $0.animation = nil }
      .task(id: request?.id) {
        guard !Task.isCancelled, currentRequestID() == request?.id else { return }
        guard let request else { opacity = 0; didSample(nil, 0); return }
        let from = opacity, start = now()
        let duration = WebsiteLayoutFluidFade.duration(reducedMotion: reducedMotion)
        if duration == 0 { opacity = request.target; didSample(request.id, opacity); return }
        while !Task.isCancelled, currentRequestID() == request.id {
          let elapsed = max(0, now() - start)
          opacity = WebsiteLayoutFluidFade.opacity(from: from, target: request.target, elapsed: elapsed, duration: duration)
          didSample(request.id, opacity)
          if elapsed >= duration { return }
          do { try await Task.sleep(for: .seconds(min(max(0.001, frameInterval()), duration - elapsed))) }
          catch { return }
        }
      }
  }
}

struct WebsiteLayoutFluidCountdownBadge: View {
  let state: WebsiteLayoutFluidCountdown
  let currentRequestID: () -> UUID?
  @Environment(\.accessibilityReduceMotion) private var reducedMotion
  @Environment(\.typebarAnimationFrameRate) private var frameRate
  @State private var cadence = WebsiteLayoutFluidFadeCadence()
  var body: some View {
    Label(state.text ?? "", systemImage: "keyboard.badge.ellipsis")
      .font(.caption.weight(.medium))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: Capsule())
      .padding(.top, 10)
      .modifier(WebsiteLayoutFluidFadeModifier(request: state.animationRequest, currentRequestID: currentRequestID, reducedMotion: reducedMotion,
        collapsesWhenHidden: true, frameInterval: { cadence.interval }))
      .background { WebsiteLayoutFluidDisplayCadence(cadence: cadence).frame(width: 0, height: 0) }
      .onChange(of: frameRate, initial: true) { _, value in cadence.frameRate = value }
      .allowsHitTesting(false)
  }
}

@MainActor final class WebsiteLayoutFluidFadeCadence {
  var frameRate = AnimationFrameRatePolicy.nativeFrameRate
  var displayFrameRate = 60
  var interval: TimeInterval {
    PromptLineScrollMotion.frameInterval(frameRate: frameRate, displayFrameRate: displayFrameRate)
  }
}

private struct WebsiteLayoutFluidDisplayCadence: NSViewRepresentable {
  let cadence: WebsiteLayoutFluidFadeCadence
  func makeNSView(context: Context) -> WebsiteLayoutFluidDisplayCadenceView { .init() }
  func updateNSView(_ view: WebsiteLayoutFluidDisplayCadenceView, context: Context) {
    view.bind(to: cadence)
  }
}

@MainActor final class WebsiteLayoutFluidDisplayCadenceView: NSView {
  private weak var consumer: WebsiteLayoutFluidFadeCadence?
  private var reported: Int?
  private var generation = UUID()
  func bind(to consumer: WebsiteLayoutFluidFadeCadence) {
    if self.consumer !== consumer {
      self.consumer = consumer
      generation = UUID(); reported = nil
    }
    report()
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self)
    generation = UUID()
    reported = nil
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
