import CoreGraphics

/// Per-image geometry declarations after the source setter has run. Logical
/// coordinates are CSS-like (origin at top left, positive y downward), not pixels.
struct WebsiteConfigBackgroundGeometry {
  enum Failure: Error, Equatable { case invalidEnvironment, unrepresentableGeometry }
  struct Update: Equatable { let dimensions: Bool, top: Bool, transform: Bool }
  struct Layout {
    let imageBox: CGRect
    let transform: CGAffineTransform
    let transformedBounds: CGRect
  }
  private(set) var expansionRem: Double?
  private(set) var topRem: Double?
  private(set) var scale: Double = 1

  init(blurRem: Double) { _ = apply(blurRem: blurRem) }

  @discardableResult
  mutating func apply(blurRem: Double) -> Update {
    let expansion = blurRem * 8, topMagnitude = blurRem * 4, nextScale = 1 + blurRem / 100
    let dimensionsAccepted = expansion.isFinite
    // Source prefixes a minus sign to JS String(blur*4); a negative nonzero
    // operand produces "--...rem", an invalid top declaration, not a positive top.
    let topAccepted = topMagnitude.isFinite && topMagnitude >= 0
    let transformAccepted = nextScale.isFinite
    if dimensionsAccepted { expansionRem = expansion == 0 ? 0 : expansion }
    if topAccepted { topRem = -topMagnitude }
    if transformAccepted { scale = nextScale }
    return .init(dimensions: dimensionsAccepted, top: topAccepted, transform: transformAccepted)
  }

  func resolve(viewport: CGSize, intrinsicSize: CGSize, pointsPerRem: Double) throws -> Layout {
    guard viewport.width.isFinite, viewport.height.isFinite, viewport.width >= 0, viewport.height >= 0,
      intrinsicSize.width.isFinite, intrinsicSize.height.isFinite, intrinsicSize.width > 0, intrinsicSize.height > 0,
      pointsPerRem.isFinite, pointsPerRem > 0 else { throw Failure.invalidEnvironment }
    let viewportWidth = Double(viewport.width), viewportHeight = Double(viewport.height)
    var width = Double(intrinsicSize.width), height = Double(intrinsicSize.height)
    if let expansionRem {
      let increment = expansionRem * pointsPerRem
      let proposedWidth = viewportWidth + increment, proposedHeight = viewportHeight + increment
      guard proposedWidth.isFinite, proposedHeight.isFinite else { throw Failure.unrepresentableGeometry }
      // Negative calc lengths are valid declarations, clamped at used-value time.
      width = max(0, proposedWidth); height = max(0, proposedHeight)
    }
    let x = (viewportWidth - width) / 2
    let y = topRem.map { $0 * pointsPerRem } ?? ((viewportHeight - height) / 2)
    let centerX = viewportWidth / 2, centerY = y + height / 2
    let tx = centerX * (1 - scale), ty = centerY * (1 - scale)
    guard [x, y, centerX, centerY, tx, ty].allSatisfy(\.isFinite) else { throw Failure.unrepresentableGeometry }
    let box = CGRect(x: x, y: y, width: width, height: height)
    let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: tx, ty: ty)
    let bounds = box.applying(transform)
    guard bounds.origin.x.isFinite, bounds.origin.y.isFinite, bounds.width.isFinite, bounds.height.isFinite,
      bounds.maxX.isFinite, bounds.maxY.isFinite else { throw Failure.unrepresentableGeometry }
    return .init(imageBox: box, transform: transform, transformedBounds: bounds)
  }
}
