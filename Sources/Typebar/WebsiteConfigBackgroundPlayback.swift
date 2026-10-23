import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A deterministic, image-owned clock projection. Does not start a timer or publish UI state.
@MainActor
struct WebsiteConfigBackgroundPlayback {
  enum Failure: Error, Equatable { case emptyImage, invalidTiming, invalidElapsed }
  struct Sample {
    let frameIndex: Int
    let frame: WebsiteConfigBackgroundResource.Frame
    /// Relative delay; nil means no further frame change is needed.
    let timeUntilNextFrame: Double?
  }
  let image: WebsiteConfigBackgroundResource.Image
  let durations: [Double]
  /// nil means infinite. Still images have one play and no frame deadlines.
  let totalPlays: Double?
  let cycleDuration: Double
  private let frameEnds: [Double]
  private let finalFrameStarts: Double?

  init(image: WebsiteConfigBackgroundResource.Image) throws {
    guard !image.frames.isEmpty else { throw Failure.emptyImage }
    self.image = image
    let keys: (dictionary: CFString, delay: CFString, unclamped: CFString, loop: CFString)?
    switch image.type {
    case UTType.gif.identifier:
      keys = (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFDelayTime,
        kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFLoopCount)
    case UTType.png.identifier:
      keys = (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGDelayTime,
        kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGLoopCount)
    case UTType.webP.identifier:
      keys = (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPDelayTime,
        kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPLoopCount)
    default: keys = nil
    }
    guard image.frames.count > 1, let keys else {
      durations = []; frameEnds = []; cycleDuration = 0; totalPlays = 1; finalFrameStarts = nil
      return
    }
    var durations: [Double] = []
    var ends: [Double] = []
    var cycle = 0.0
    for frame in image.frames {
      let metadata = (frame.properties as NSDictionary)[keys.dictionary] as? NSDictionary
      let raw = metadata?[keys.unclamped] ?? metadata?[keys.delay]
      var delay = 0.0
      if let raw {
        guard let number = raw as? NSNumber, number.doubleValue.isFinite, number.doubleValue >= 0,
          number.floatValue.isFinite else { throw Failure.invalidTiming }
        // Match the browser's ImageIO float conversion, not its clamped metadata alone.
        delay = Double(number.floatValue)
      }
      if delay < 0.011 { delay = 0.1 }
      let end = cycle + delay
      guard end.isFinite, end > cycle else { throw Failure.invalidTiming }
      durations.append(delay); ends.append(end); cycle = end
    }
    let global = (image.properties as NSDictionary?)?[keys.dictionary] as? NSDictionary
    let rawLoop = global?[keys.loop]
    var plays: Double? = 1
    if let rawLoop {
      guard let number = rawLoop as? NSNumber else { throw Failure.invalidTiming }
      let count = number.doubleValue
      guard count.isFinite, count >= 0, count <= Double(UInt32.max), count.rounded(.towardZero) == count
      else { throw Failure.invalidTiming }
      plays = count == 0 ? nil : count
    }
    let stop = plays.map { cycle * ($0 - 1) + (ends.dropLast().last ?? 0) }
    guard stop?.isFinite != false else { throw Failure.invalidTiming }
    self.durations = durations; frameEnds = ends; cycleDuration = cycle
    totalPlays = plays; finalFrameStarts = stop
  }

  func sample(elapsed: Double) throws -> Sample {
    guard elapsed.isFinite, elapsed >= 0 else { throw Failure.invalidElapsed }
    if frameEnds.isEmpty {
      return .init(frameIndex: 0, frame: image.frames[0], timeUntilNextFrame: nil)
    }
    if let finalFrameStarts, elapsed >= finalFrameStarts {
      let last = image.frames.count - 1
      return .init(frameIndex: last, frame: image.frames[last], timeUntilNextFrame: nil)
    }
    let position = elapsed.truncatingRemainder(dividingBy: cycleDuration)
    // At most the prepared frame count (resource preparation bounds this to 256 by default).
    let index = frameEnds.firstIndex(where: { position < $0 }) ?? frameEnds.count - 1
    return .init(frameIndex: index, frame: image.frames[index],
      timeUntilNextFrame: frameEnds[index] - position)
  }
}
