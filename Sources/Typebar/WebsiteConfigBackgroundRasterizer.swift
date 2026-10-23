import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders an already laid-out device-pixel canvas. Does not perform object-fit,
/// orientation, animation, downloading, configuration writes or view publication.
@MainActor
final class WebsiteConfigBackgroundRasterizer {
  enum Failure: Error, Equatable {
    case invalidScale, invalidLimits, resourceLimit, unrepresentableStage, renderFailed
  }
  struct Limits {
    var pixels = 16 * 1024 * 1024
    var blurPixels: Double = 256
  }
  private let space: CGColorSpace
  private let context: CIContext

  init(useSoftwareRenderer: Bool = false) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    self.space = space
    // CSS filter functions use sRGB, not CIContext's default linear working space.
    context = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space,
      .workingFormat: CIFormat.RGBAf.rawValue, .cacheIntermediates: false,
      .useSoftwareRenderer: useSoftwareRenderer])
  }

  func render(canvas: CGImage, filter: WebsiteConfigBackgroundFilter,
    pointsPerRem: Double, pixelsPerPoint: Double, limits: Limits = .init()) throws -> CGImage {
    guard pointsPerRem.isFinite, pointsPerRem > 0, pixelsPerPoint.isFinite, pixelsPerPoint > 0,
      (pointsPerRem * pixelsPerPoint).isFinite, pointsPerRem * pixelsPerPoint > 0
    else { throw Failure.invalidScale }
    guard limits.pixels > 0, limits.blurPixels.isFinite, limits.blurPixels >= 0
    else { throw Failure.invalidLimits }
    guard canvas.height > 0, canvas.width <= limits.pixels / canvas.height
    else { throw Failure.resourceLimit }
    // Empty source declaration removes the filter, including its color-space
    // conversion. Preserve the original gamut, depth and owned image identity.
    guard !filter.stages.isEmpty else { return canvas }
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
    var image = CIImage(cgImage: canvas)
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
    // The caller owns layout/overscan. Crop only after the full filter chain;
    // this finite output is not a claim that CSS effects stop at an image box.
    guard let result = context.createCGImage(image, from: extent, format: .RGBA8,
      colorSpace: space, deferred: false) else { throw Failure.renderFailed }
    return result
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
