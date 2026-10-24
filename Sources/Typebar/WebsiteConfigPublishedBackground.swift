import AppKit
import SwiftUI

enum WebsiteConfigPublishedBackgroundError: Error { case wrongOwner, unprepared }

/// Consumes committed bytes and source numbers, never the legacy snapshot or loader.
/// The full-configuration host still owns publication selection and cutover.
struct WebsiteConfigPublishedBackground: View {
  private let publication: WebsiteConfigCommitCoordinator.Publication
  private let resource: WebsiteConfigBackgroundResource
  let fallbackStyle: PracticeBackdropStyle
  let theme: ResolvedTheme
  let reduceMotion: Bool
  var onFailure: BackgroundFailureFeedback.Sink

  init(publication: WebsiteConfigCommitCoordinator.Publication, owner: UUID,
    fallbackStyle: PracticeBackdropStyle, theme: ResolvedTheme, reduceMotion: Bool,
    onFailure: @escaping BackgroundFailureFeedback.Sink = { _ in }) throws {
    guard publication.owner == owner else { throw WebsiteConfigPublishedBackgroundError.wrongOwner }
    guard let resource = publication.background else { throw WebsiteConfigPublishedBackgroundError.unprepared }
    self.publication = publication; self.resource = resource
    self.fallbackStyle = fallbackStyle; self.theme = theme; self.reduceMotion = reduceMotion
    self.onFailure = onFailure
  }

  var body: some View {
    ZStack {
      PracticeBackdrop(style: fallbackStyle, theme: theme, reduceMotion: reduceMotion)
      PublishedBackgroundSurface(publication: publication, resource: resource, onFailure: onFailure)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
    .allowsHitTesting(false)
  }
}

private struct PublishedBackgroundSurface: NSViewRepresentable {
  let publication: WebsiteConfigCommitCoordinator.Publication
  let resource: WebsiteConfigBackgroundResource
  let onFailure: BackgroundFailureFeedback.Sink
  func makeNSView(context: Context) -> WebsiteConfigPublishedBackgroundView { .init() }
  func updateNSView(_ view: WebsiteConfigPublishedBackgroundView, context: Context) {
    view.configure(publication: publication, resource: resource, onFailure: onFailure)
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
    if identity != publication.applicationID {
      stop()
      identity = publication.applicationID
      feedback.begin(identity: publication.applicationID, sink: onFailure)
    }
    switch resource.state {
    case .ready(let image):
      surface.configure(image: image, identity: publication.applicationID,
        fit: publication.draft.pagePreferences.backgroundFit,
        filter: publication.draft.pagePreferences.backgroundFilter,
        pointsPerRem: publication.pointsPerRem, feedback: feedback)
    case .none: surface.stop()
    case .failed(let reason):
      surface.stop()
      let kind: BackgroundFailureFeedback.Kind = reason == .resourceLimit ? .resourceLimit
        : resource.source == .local ? .local : .remote
      feedback.report(kind, identity: publication.applicationID)
    }
  }
  func stop() { identity = nil; feedback.cancel(); surface.stop() }
}
