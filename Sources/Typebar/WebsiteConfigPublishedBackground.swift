import AppKit
import SwiftUI

enum WebsiteConfigPublishedBackgroundError: Error { case wrongOwner, unprepared }

/// Consumes committed bytes and source numbers, never the legacy snapshot or loader.
/// The full-configuration host still owns publication selection and cutover.
struct WebsiteConfigPublishedBackground: View {
  private let snapshot: WebsiteConfigBackgroundDisplay.Snapshot
  let fallbackStyle: PracticeBackdropStyle
  let theme: ResolvedTheme
  let reduceMotion: Bool
  var onFailure: BackgroundFailureFeedback.Sink

  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID,
    fallbackStyle: PracticeBackdropStyle, theme: ResolvedTheme, reduceMotion: Bool,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws {
    guard publication.owner == owner else { throw WebsiteConfigPublishedBackgroundError.wrongOwner }
    guard let resource = publication.background else { throw WebsiteConfigPublishedBackgroundError.unprepared }
    try self.init(snapshot: .init(owner: owner, identity: publication.applicationID, resource: resource,
      preferences: publication.draft.pagePreferences, pointsPerRem: publication.pointsPerRem), owner: owner,
      fallbackStyle: fallbackStyle, theme: theme, reduceMotion: reduceMotion, onFailure: onFailure)
  }
  init(snapshot: WebsiteConfigBackgroundDisplay.Snapshot, owner: UUID,
    fallbackStyle: PracticeBackdropStyle, theme: ResolvedTheme, reduceMotion: Bool,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws {
    guard snapshot.owner == owner else { throw WebsiteConfigPublishedBackgroundError.wrongOwner }
    self.snapshot = snapshot
    self.fallbackStyle = fallbackStyle; self.theme = theme; self.reduceMotion = reduceMotion
    self.onFailure = onFailure
  }

  var backdrop: PracticeBackdrop {
    PracticeBackdrop(style: fallbackStyle, theme: theme, reduceMotion: reduceMotion)
  }
  var body: some View {
    ZStack {
      backdrop
      PublishedBackgroundSurface(snapshot: snapshot, onFailure: onFailure)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

private struct PublishedBackgroundSurface: NSViewRepresentable {
  let snapshot: WebsiteConfigBackgroundDisplay.Snapshot
  let onFailure: BackgroundFailureFeedback.Sink
  func makeNSView(context: Context) -> WebsiteConfigPublishedBackgroundView { .init() }
  func updateNSView(_ view: WebsiteConfigPublishedBackgroundView, context: Context) {
    view.configure(snapshot: snapshot, onFailure: onFailure)
  }
  static func dismantleNSView(_ view: WebsiteConfigPublishedBackgroundView, coordinator: ()) { view.stop() }
}

@MainActor
final class WebsiteConfigPublishedBackgroundView: NSView {
  let surface = WebsiteConfigBackgroundSurfaceView()
  private let feedback = BackgroundFailureFeedback()
  private var identity: UUID?
  override init(frame: NSRect) {
    super.init(frame: frame)
    addSubview(surface)
    setAccessibilityElement(false)
  }
  convenience init() { self.init(frame: .zero) }
  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func layout() { super.layout(); surface.frame = bounds }

  func configure(publication: WebsiteConfigCommitCoordinator.Publication,
    resource: WebsiteConfigBackgroundResource, onFailure: @escaping BackgroundFailureFeedback.Sink) {
    configure(snapshot: .init(owner: publication.owner, identity: publication.applicationID, resource: resource,
      preferences: publication.draft.pagePreferences, pointsPerRem: publication.pointsPerRem), onFailure: onFailure)
  }
  func configure(snapshot: WebsiteConfigBackgroundDisplay.Snapshot, onFailure: @escaping BackgroundFailureFeedback.Sink) {
    if identity != snapshot.identity {
      stop()
      identity = snapshot.identity
      feedback.begin(identity: snapshot.identity, sink: onFailure)
    }
    let resource = snapshot.resource
    switch resource.state {
    case .ready(let image):
      surface.configure(image: image, identity: snapshot.identity,
        fit: snapshot.fitOverride ?? snapshot.preferences.backgroundFit, filter: snapshot.preferences.backgroundFilter,
        pointsPerRem: snapshot.pointsPerRem, feedback: feedback)
    case .none: surface.stop()
    case .failed(let reason):
      surface.stop()
      let kind: BackgroundFailureFeedback.Kind = reason == .resourceLimit ? .resourceLimit
        : resource.source == .local ? .local : .remote
      feedback.report(kind, identity: snapshot.identity)
    }
  }
  func stop() { identity = nil; feedback.cancel(); surface.stop() }
}
