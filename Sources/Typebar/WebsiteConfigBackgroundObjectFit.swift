import CoreGraphics

/// Object content inside an already resolved CSS image box. Not the image box's
/// absolute position, blur overdraw, transform, orientation or animation policy.
enum WebsiteConfigBackgroundObjectFit {
  enum Failure: Error, Equatable { case invalidGeometry, unrepresentableGeometry }

  static func placement(imageSize: CGSize, in box: CGRect, fit: CustomBackgroundFit) throws -> CGRect? {
    guard imageSize.width.isFinite, imageSize.height.isFinite, imageSize.width > 0, imageSize.height > 0,
      box.origin.x.isFinite, box.origin.y.isFinite, box.width.isFinite, box.height.isFinite,
      box.size.width >= 0, box.size.height >= 0, box.maxX.isFinite, box.maxY.isFinite
    else { throw Failure.invalidGeometry }
    guard box.width > 0, box.height > 0 else { return nil }
    // The source's "max" clears inline object-fit; CSS Images' initial value is fill.
    if fit == .max { return box }
    let horizontal = box.width / imageSize.width, vertical = box.height / imageSize.height
    let scale = fit == .cover ? max(horizontal, vertical) : min(horizontal, vertical)
    let width = imageSize.width * scale, height = imageSize.height * scale
    let result = CGRect(x: box.origin.x + (box.width - width) / 2,
      y: box.origin.y + (box.height - height) / 2, width: width, height: height)
    guard width.isFinite, height.isFinite, width > 0, height > 0,
      result.origin.x.isFinite, result.origin.y.isFinite, result.maxX.isFinite, result.maxY.isFinite
    else { throw Failure.unrepresentableGeometry }
    return result
  }

  /// Caller owns the context, coordinate system, color space and interpolation.
  static func draw(_ image: CGImage, in box: CGRect, fit: CustomBackgroundFit, context: CGContext) throws {
    guard let content = try placement(imageSize: .init(width: image.width, height: image.height), in: box, fit: fit)
    else { return }
    // CGContext's current path is not saved by saveGState, and clip(to:) clears it.
    let path = context.path
    context.saveGState()
    defer {
      context.restoreGState()
      context.beginPath()
      if let path { context.addPath(path) }
    }
    context.clip(to: box)
    context.draw(image, in: content)
  }
}
