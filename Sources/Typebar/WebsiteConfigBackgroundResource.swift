import CoreGraphics
import Foundation
import ImageIO

enum WebsiteConfigBackgroundResourceError: Error, Equatable {
  case remoteNotProvided, wrongRemoteAddress, invalidLimits
}

/// Owned image preparation only. Never fetches a URL, reads a path from JSON,
/// writes a preference, registers a resource, renders a frame or posts a notice.
@MainActor
struct WebsiteConfigBackgroundResource {
  enum Local { case absent, empty, data(Data) }
  enum Remote {
    case received(address: WebsiteConfigValue, data: Data)
    case failed(address: WebsiteConfigValue)
  }
  enum Source: Equatable { case local, remote(WebsiteConfigValue) }
  enum Failure: Equatable { case transport, undecodable, resourceLimit }
  struct Limits {
    var encodedBytes = 64 * 1024 * 1024
    var pixels = 16 * 1024 * 1024
    var decodedBytes = 128 * 1024 * 1024
    var frames = 256
  }
  struct Frame {
    let image: CGImage
    let properties: CFDictionary
    /// ImageIO's per-image TIFF/EXIF value, not UIImage's differently numbered enum.
    /// Malformed metadata is retained in properties but never invents a transform.
    var orientation: CGImagePropertyOrientation {
      guard let number = (properties as NSDictionary)[kCGImagePropertyOrientation] as? NSNumber else { return .up }
      let value = number.doubleValue
      guard value.isFinite, value >= 1, value <= 8, value.rounded(.towardZero) == value
      else { return .up }
      return CGImagePropertyOrientation(rawValue: UInt32(value)) ?? .up
    }
  }
  struct Image {
    let encodedData: Data
    let type: String
    let properties: CFDictionary?
    let frames: [Frame]
  }
  enum State { case none, ready(Image), failed(Failure) }
  let source: Source?
  let state: State

  /// Explicit already-loaded bytes; no synthetic configuration is needed by native display hosts.
  static func prepare(loadedData: Data, source: Source, limits: Limits = .init()) throws -> Self {
    guard limits.encodedBytes > 0, limits.pixels > 0, limits.decodedBytes > 0, limits.frames > 0
    else { throw WebsiteConfigBackgroundResourceError.invalidLimits }
    return decode(loadedData, source: source, limits: limits)
  }

  static func prepare(preferences: WebsiteConfigNativePagePreferences, local: Local,
    remote: Remote? = nil, limits: Limits = .init()) throws -> Self {
    guard limits.encodedBytes > 0, limits.pixels > 0, limits.decodedBytes > 0, limits.frames > 0
    else { throw WebsiteConfigBackgroundResourceError.invalidLimits }
    switch local {
    case .empty: return .init(source: nil, state: .none)
    case .data(let data): return decode(data, source: .local, limits: limits)
    case .absent: break
    }
    guard preferences.backgroundAddress.stringUnits?.isEmpty != true else {
      return .init(source: nil, state: .none)
    }
    guard let remote else { throw WebsiteConfigBackgroundResourceError.remoteNotProvided }
    let address: WebsiteConfigValue
    switch remote {
    case .received(let value, _), .failed(let value): address = value
    }
    guard let actual = address.stringUnits, actual == preferences.backgroundAddress.stringUnits
    else { throw WebsiteConfigBackgroundResourceError.wrongRemoteAddress }
    switch remote {
    case .failed: return .init(source: .remote(address), state: .failed(.transport))
    case .received(_, let data): return decode(data, source: .remote(address), limits: limits)
    }
  }

  private static func decode(_ data: Data, source: Source, limits: Limits) -> Self {
    func failed(_ reason: Failure) -> Self { .init(source: source, state: .failed(reason)) }
    guard data.count <= limits.encodedBytes else { return failed(.resourceLimit) }
    // Own the bytes even if the input was Data(referencing: NSMutableData).
    let owned = data.withUnsafeBytes { Data($0) }
    guard let container = CGImageSourceCreateWithData(owned as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetStatus(container) == .statusComplete,
      let type = CGImageSourceGetType(container) else { return failed(.undecodable) }
    let count = CGImageSourceGetCount(container)
    guard count > 0 else { return failed(.undecodable) }
    guard count <= limits.frames else { return failed(.resourceLimit) }
    var remainingPixels = limits.pixels
    var metadata: [(properties: CFDictionary, width: Int, height: Int)] = []
    func dimension(_ value: Any?) -> Int? {
      guard let value = (value as? NSNumber)?.doubleValue, value.isFinite,
        value > 0, value < Double(Int.max), value.rounded(.towardZero) == value else { return nil }
      return Int(value)
    }
    for index in 0..<count {
      guard let properties = CGImageSourceCopyPropertiesAtIndex(container, index, nil),
        let width = dimension((properties as NSDictionary)[kCGImagePropertyPixelWidth]),
        let height = dimension((properties as NSDictionary)[kCGImagePropertyPixelHeight])
      else { return failed(.undecodable) }
      guard width <= remainingPixels / height else { return failed(.resourceLimit) }
      remainingPixels -= width * height
      metadata.append((properties, width, height))
    }
    var remainingBytes = limits.decodedBytes
    var frames: [Frame] = []
    for (index, item) in metadata.enumerated() {
      guard let image = CGImageSourceCreateImageAtIndex(container, index,
        [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
        CGImageSourceGetStatusAtIndex(container, index) == .statusComplete,
        image.width == item.width, image.height == item.height else { return failed(.undecodable) }
      guard image.bytesPerRow <= remainingBytes / image.height else { return failed(.resourceLimit) }
      remainingBytes -= image.bytesPerRow * image.height
      frames.append(.init(image: image, properties: item.properties))
    }
    return .init(source: source, state: .ready(.init(encodedData: owned, type: type as String,
      properties: CGImageSourceCopyProperties(container, nil), frames: frames)))
  }
}
