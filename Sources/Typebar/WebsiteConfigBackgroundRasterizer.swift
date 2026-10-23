import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Native canvas and complete single-frame viewport rendering. No downloading,
/// animation, configuration writes or view publication is performed here.
@MainActor
final class WebsiteConfigBackgroundRasterizer {
  enum Failure: Error, Equatable {
    case invalidScale, invalidLimits, invalidGeometry, resourceLimit, unrepresentableStage, renderFailed
  }
  enum Sampling { case linear, nearest }
  struct Limits {
    var pixels = 16 * 1024 * 1024
    var blurPixels: Double = 256
    var renderedBytes = 128 * 1024 * 1024
  }
  private let space: CGColorSpace
  private let context: CIContext
  private let software: Bool

  init(useSoftwareRenderer: Bool = false) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    self.space = space
    software = useSoftwareRenderer
    // CSS filter functions use sRGB, not CIContext's default linear working space.
    context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space,
      .workingFormat: CIFormat.RGBAf.rawValue, .cacheIntermediates: false,
      .useSoftwareRenderer: useSoftwareRenderer])
  }

  func renderViewport(frame: WebsiteConfigBackgroundResource.Frame,
    layout: WebsiteConfigBackgroundGeometry.Layout, fit: CustomBackgroundFit,
    filter: WebsiteConfigBackgroundFilter, viewport: CGSize, pointsPerRem: Double,
    pixelsPerPoint: Double, sampling: Sampling = .linear, limits: Limits = .init()) throws -> CGImage {
    guard pointsPerRem.isFinite, pointsPerRem > 0, pixelsPerPoint.isFinite, pixelsPerPoint > 0,
      (pointsPerRem * pixelsPerPoint).isFinite, pointsPerRem * pixelsPerPoint > 0
    else { throw Failure.invalidScale }
    guard limits.pixels > 0, limits.renderedBytes > 0, limits.blurPixels.isFinite, limits.blurPixels >= 0
    else { throw Failure.invalidLimits }
    guard viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0
    else { throw Failure.invalidGeometry }
    let rawWidth = Double(viewport.width) * pixelsPerPoint, rawHeight = Double(viewport.height) * pixelsPerPoint
    let width = ceil(rawWidth), height = ceil(rawHeight)
    guard width.isFinite, height.isFinite, width > 0, height > 0, width < Double(Int.max), height < Double(Int.max)
    else { throw Failure.unrepresentableStage }
    let highDepth = filter.stages.isEmpty && (frame.image.bitsPerComponent > 8 || frame.image.bitmapInfo.contains(.floatComponents))
    let bytesPerPixel = highDepth ? 16 : 4
    guard Int(width) <= limits.pixels / Int(height),
      Int(width) <= limits.renderedBytes / bytesPerPixel / Int(height) else { throw Failure.resourceLimit }
    let output = CGRect(x: 0, y: 0, width: width, height: height)
    // Align the logical top edge with the integral device canvas; fractional
    // viewports leave transparent padding at right/bottom, never stretch content.
    let viewportClip = CGRect(x: 0, y: height - rawHeight, width: rawWidth, height: rawHeight)
    let box = layout.imageBox, logical = layout.transform
    guard box.origin.x.isFinite, box.origin.y.isFinite, box.width.isFinite, box.height.isFinite,
      box.size.width >= 0, box.size.height >= 0, box.maxX.isFinite, box.maxY.isFinite,
      [logical.a, logical.b, logical.c, logical.d, logical.tx, logical.ty].allSatisfy(\.isFinite)
    else { throw Failure.invalidGeometry }
    let post = CGAffineTransform(a: logical.a, b: -logical.b, c: -logical.c, d: logical.d,
      tx: pixelsPerPoint * logical.tx + logical.c * height,
      ty: height * (1 - logical.d) - pixelsPerPoint * logical.ty)
    try validateAffine(post)
    let determinant = post.a * post.d - post.b * post.c
    guard determinant.isFinite else { throw Failure.unrepresentableStage }
    let targetSpace = filter.stages.isEmpty && frame.image.colorSpace?.model == .rgb ? frame.image.colorSpace! : space
    var image = CIImage(color: .clear).cropped(to: output)
    if !box.isEmpty && determinant != 0 {
      let deviceBox = box.applying(.init(a: pixelsPerPoint, b: 0, c: 0, d: -pixelsPerPoint, tx: 0, ty: height))
      let oriented = CIImage(cgImage: frame.image).oriented(frame.orientation)
      guard let content = try WebsiteConfigBackgroundObjectFit.placement(imageSize: oriented.extent.size,
        in: deviceBox, fit: fit) else { throw Failure.invalidGeometry }
      let sx = content.width / oriented.extent.width, sy = content.height / oriented.extent.height
      let placement = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
        tx: content.minX - oriented.extent.minX * sx, ty: content.minY - oriented.extent.minY * sy)
      try validateAffine(placement)
      let pixelsPerRem = pointsPerRem * pixelsPerPoint
      let halo = try filterHalo(filter, pixelsPerRem: pixelsPerRem, limits: limits)
      let contentClip = content.intersection(deviceBox)
      // Empty space outside finite content cannot require an image-sized
      // intermediate. This is only a conservative admission estimate: the graph
      // is never cropped to this estimate; Core Image computes its real ROI.
      let work = viewportClip.applying(post.inverted()).insetBy(dx: -halo, dy: -halo)
        .intersection(contentClip.insetBy(dx: -halo, dy: -halo))
      try checkWorkArea(work, limits: limits)
      // Clamp only resampling at the original image edge, then restore the
      // finite replaced-content clip BEFORE filters. Blur itself stays unclamped.
      let extended = oriented.clampedToExtent()
      let sampled = sampling == .nearest ? extended.samplingNearest() : extended.samplingLinear()
      image = sampled.transformed(by: placement).cropped(to: contentClip)
      image = try filtered(image, filter: filter, pixelsPerRem: pixelsPerRem)
      image = image.transformed(by: post)
    }
    let destination = filter.stages.isEmpty ? CIContext(options: [.workingColorSpace: targetSpace,
      .outputColorSpace: targetSpace, .workingFormat: CIFormat.RGBAf.rawValue,
      .cacheIntermediates: false, .useSoftwareRenderer: software]) : context
    guard let result = destination.createCGImage(image.cropped(to: viewportClip), from: output,
      format: highDepth ? .RGBAf : .RGBA8, colorSpace: targetSpace, deferred: false)
    else { throw Failure.renderFailed }
    return try checkedOutput(result, limits: limits)
  }

  private func checkedOutput(_ image: CGImage, limits: Limits) throws -> CGImage {
    // Materialized Core Graphics rows may contain alignment padding. The
    // earlier format-based check is only a minimum allocation estimate.
    guard image.height > 0, image.bytesPerRow <= limits.renderedBytes / image.height
    else { throw Failure.resourceLimit }
    return image
  }

  private func validateAffine(_ transform: CGAffineTransform) throws {
    guard [transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty].allSatisfy({
      $0.isFinite && abs($0) <= CGFloat(Float.greatestFiniteMagnitude) / 8
    }) else { throw Failure.unrepresentableStage }
  }

  private func checkWorkArea(_ rect: CGRect, limits: Limits) throws {
    if rect.isNull || rect.isEmpty { return }
    let width = ceil(rect.width), height = ceil(rect.height)
    guard width.isFinite, height.isFinite, width > 0, height > 0,
      width < CGFloat(Int.max), height < CGFloat(Int.max),
      Int(width) <= limits.pixels / Int(height) else { throw Failure.resourceLimit }
  }

  private func filterHalo(_ filter: WebsiteConfigBackgroundFilter, pixelsPerRem: Double, limits: Limits) throws -> CGFloat {
    var halo: Double = 0
    for stage in filter.stages {
      switch stage {
      case .blur(let rem):
        let sigma = rem * pixelsPerRem
        guard sigma.isFinite, sigma <= Double(Float.greatestFiniteMagnitude) / 8 else { throw Failure.unrepresentableStage }
        guard sigma <= limits.blurPixels else { throw Failure.resourceLimit }
        halo += ceil(sigma * 4)
      case .brightness(let amount), .saturate(let amount), .opacity(let amount):
        guard amount <= Double(Float.greatestFiniteMagnitude) / 8 else { throw Failure.unrepresentableStage }
      }
    }
    return CGFloat(halo)
  }

  func render(canvas: CGImage, filter: WebsiteConfigBackgroundFilter,
    pointsPerRem: Double, pixelsPerPoint: Double, limits: Limits = .init()) throws -> CGImage {
    guard pointsPerRem.isFinite, pointsPerRem > 0, pixelsPerPoint.isFinite, pixelsPerPoint > 0,
      (pointsPerRem * pixelsPerPoint).isFinite, pointsPerRem * pixelsPerPoint > 0
    else { throw Failure.invalidScale }
    guard limits.pixels > 0, limits.renderedBytes > 0, limits.blurPixels.isFinite, limits.blurPixels >= 0
    else { throw Failure.invalidLimits }
    guard canvas.height > 0, canvas.width <= limits.pixels / canvas.height
    else { throw Failure.resourceLimit }
    // Empty source declaration removes the filter, including its color-space
    // conversion. Preserve the original gamut, depth and owned image identity.
    guard !filter.stages.isEmpty else { return canvas }
    guard canvas.width <= limits.renderedBytes / 4 / canvas.height else { throw Failure.resourceLimit }
    let pixelsPerRem = pointsPerRem * pixelsPerPoint
    // Preflight the complete chain before constructing a lazy processing graph.
    for stage in filter.stages {
      switch stage {
      case .blur(let rem):
        let sigma = rem * pixelsPerRem
        guard sigma.isFinite else { throw Failure.unrepresentableStage }
        guard sigma <= limits.blurPixels else { throw Failure.resourceLimit }
        let halo = ceil(sigma * 4) * 2
        let width = Double(canvas.width) + halo, height = Double(canvas.height) + halo
        guard width.isFinite, height.isFinite, width < Double(Int.max), height < Double(Int.max),
          Int(width) <= limits.pixels / Int(height) else { throw Failure.resourceLimit }
      case .brightness(let amount), .saturate(let amount), .opacity(let amount):
        guard amount <= Double(Float.greatestFiniteMagnitude) / 8 else { throw Failure.unrepresentableStage }
      }
    }
    let extent = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
    let image = try filtered(CIImage(cgImage: canvas), filter: filter, pixelsPerRem: pixelsPerRem)
    // The caller owns layout/overscan. Crop only after the full filter chain;
    // this finite output is not a claim that CSS effects stop at an image box.
    guard let result = context.createCGImage(image, from: extent, format: .RGBA8,
      colorSpace: space, deferred: false) else { throw Failure.renderFailed }
    return try checkedOutput(result, limits: limits)
  }

  private func filtered(_ input: CIImage, filter: WebsiteConfigBackgroundFilter, pixelsPerRem: Double) throws -> CIImage {
    var image = input
    for stage in filter.stages {
      switch stage {
      case .blur(let rem):
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image // No clampedToExtent: CSS filter blur uses transparent outside pixels.
        blur.radius = Float(rem * pixelsPerRem)
        guard let next = blur.outputImage else { throw Failure.renderFailed }
        image = next
      case .brightness(let amount):
        image = try matrix(image, red: .init(x: amount, y: 0, z: 0, w: 0),
          green: .init(x: 0, y: amount, z: 0, w: 0), blue: .init(x: 0, y: 0, z: amount, w: 0))
      case .saturate(let amount):
        // Filter Effects' feColorMatrix saturation matrix, on unpremultiplied RGB.
        image = try matrix(image,
          red: .init(x: 0.213 + 0.787 * amount, y: 0.715 - 0.715 * amount, z: 0.072 - 0.072 * amount, w: 0),
          green: .init(x: 0.213 - 0.213 * amount, y: 0.715 + 0.285 * amount, z: 0.072 - 0.072 * amount, w: 0),
          blue: .init(x: 0.213 - 0.213 * amount, y: 0.715 - 0.715 * amount, z: 0.072 + 0.928 * amount, w: 0))
      case .opacity(let amount):
        image = try matrix(image, red: .init(x: 1, y: 0, z: 0, w: 0),
          green: .init(x: 0, y: 1, z: 0, w: 0), blue: .init(x: 0, y: 0, z: 1, w: 0), alpha: amount)
      }
    }
    return image
  }

  private func matrix(_ image: CIImage, red: CIVector, green: CIVector, blue: CIVector,
    alpha: Double = 1) throws -> CIImage {
    let matrix = CIFilter.colorMatrix()
    matrix.inputImage = image
    matrix.rVector = red; matrix.gVector = green; matrix.bVector = blue
    matrix.aVector = .init(x: 0, y: 0, z: 0, w: alpha)
    matrix.biasVector = .init(x: 0, y: 0, z: 0, w: 0)
    guard let result = matrix.outputImage else { throw Failure.renderFailed }
    // Keep primitive boundaries: bright clipping must happen before saturation.
    let clamp = CIFilter.colorClamp()
    clamp.inputImage = result
    clamp.minComponents = .init(x: 0, y: 0, z: 0, w: 0)
    clamp.maxComponents = .init(x: 1, y: 1, z: 1, w: 1)
    guard let bounded = clamp.outputImage else { throw Failure.renderFailed }
    return bounded
  }
}
