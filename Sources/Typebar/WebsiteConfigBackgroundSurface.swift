import AppKit
import SwiftUI

struct WebsiteConfigBackgroundSurface: NSViewRepresentable {
  let image: WebsiteConfigBackgroundResource.Image
  let identity: UUID
  let fit: CustomBackgroundFit
  let filter: WebsiteConfigNativePagePreferences.BackgroundFilter
  var pointsPerRem: Double = 16
  func makeNSView(context: Context) -> WebsiteConfigBackgroundSurfaceView { .init() }
  func updateNSView(_ view: WebsiteConfigBackgroundSurfaceView, context: Context) {
    view.configure(image: image, identity: identity, fit: fit, filter: filter, pointsPerRem: pointsPerRem)
  }
  static func dismantleNSView(_ view: WebsiteConfigBackgroundSurfaceView, coordinator: ()) { view.stop() }
}

@MainActor
final class WebsiteConfigBackgroundSurfaceView: NSView {
  private(set) var renderedImage: CGImage?
  private(set) var renderedScale: Double = 1
  private(set) var error: Error?
  let player: WebsiteConfigBackgroundPlayer
  private let rasterizer = WebsiteConfigBackgroundRasterizer()
  private let limits: WebsiteConfigBackgroundRasterizer.Limits
  private var identity: UUID?
  private var currentFrame: WebsiteConfigBackgroundResource.Frame?
  private var geometry = WebsiteConfigBackgroundGeometry(blurRem: 0)
  private var filterState = WebsiteConfigBackgroundFilter()
  private var rawFilter: WebsiteConfigNativePagePreferences.BackgroundFilter?
  private var fit: CustomBackgroundFit = .cover
  private var pointsPerRem: Double = 16
  private var lastViewport: CGSize?
  init(player: WebsiteConfigBackgroundPlayer = .init(), limits: WebsiteConfigBackgroundRasterizer.Limits = .init()) {
    self.player = player; self.limits = limits
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  func configure(image: WebsiteConfigBackgroundResource.Image, identity: UUID, fit: CustomBackgroundFit,
    filter: WebsiteConfigNativePagePreferences.BackgroundFilter, pointsPerRem: Double = 16) {
    let replacing = self.identity != identity
    let changed = replacing || self.fit != fit || rawFilter != filter || self.pointsPerRem != pointsPerRem
    self.fit = fit; self.pointsPerRem = pointsPerRem
    if replacing {
      player.stop(); currentFrame = nil; renderedImage = nil; error = nil
      self.identity = identity
      geometry = .init(blurRem: filter.blurRem); filterState = .init()
    } else if rawFilter != filter { geometry.apply(blurRem: filter.blurRem) }
    if replacing || rawFilter != filter { _ = filterState.apply(filter) }
    rawFilter = filter
    if replacing {
      do {
        let playback = try WebsiteConfigBackgroundPlayback(image: image)
        player.start(playback, present: { [weak self] sample in
          guard let self, self.identity == identity else { return }
          self.currentFrame = sample.frame
          self.render(force: false)
        }, failed: { [weak self] failure in
          guard let self, self.identity == identity else { return }
          self.error = failure; self.renderedImage = nil; self.needsDisplay = true
        })
      } catch { self.error = error; needsDisplay = true }
    } else if changed { render(force: true) }
    synchronizeActivity()
  }

  func stop() {
    identity = nil; player.stop(); currentFrame = nil; renderedImage = nil; error = nil
    rawFilter = nil; lastViewport = nil; needsDisplay = true
  }

  private func synchronizeActivity() {
    if window != nil, !isHiddenOrHasHiddenAncestor, bounds.width > 0, bounds.height > 0 { player.resume() }
    else { player.pause() }
  }
  private func refreshLayout() {
    let scale = Double(window?.backingScaleFactor ?? 1)
    if lastViewport != bounds.size || renderedScale != scale { render(force: true) }
    synchronizeActivity()
  }
  override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); refreshLayout() }
  override func setBoundsSize(_ newSize: NSSize) { super.setBoundsSize(newSize); refreshLayout() }
  override func layout() { super.layout(); refreshLayout() }
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties(); refreshLayout(); needsDisplay = true
  }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refreshLayout() }
  override func viewDidHide() { super.viewDidHide(); synchronizeActivity() }
  override func viewDidUnhide() { super.viewDidUnhide(); refreshLayout() }

  private func render(force: Bool) {
    guard force || error == nil else { return }
    lastViewport = bounds.size; renderedScale = Double(window?.backingScaleFactor ?? 1)
    guard let frame = currentFrame, bounds.width > 0, bounds.height > 0 else {
      renderedImage = nil; needsDisplay = true; return
    }
    do {
      let natural = frame.orientation.rawValue >= 5
        ? CGSize(width: frame.image.height, height: frame.image.width)
        : CGSize(width: frame.image.width, height: frame.image.height)
      let layout = try geometry.resolve(viewport: bounds.size, intrinsicSize: natural, pointsPerRem: pointsPerRem)
      renderedImage = try rasterizer.renderViewport(frame: frame, layout: layout, fit: fit,
        filter: filterState, viewport: bounds.size, pointsPerRem: pointsPerRem,
        pixelsPerPoint: renderedScale, limits: limits)
      error = nil
    } catch { self.error = error; renderedImage = nil }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: bounds)
    // This view owns its layer. Source-over transparent pixels cannot erase a prior frame.
    context.clear(bounds)
    guard let image = renderedImage else { return }
    context.interpolationQuality = .none
    let width = Double(image.width) / renderedScale, height = Double(image.height) / renderedScale
    context.translateBy(x: bounds.minX, y: bounds.minY + height)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  }
}
