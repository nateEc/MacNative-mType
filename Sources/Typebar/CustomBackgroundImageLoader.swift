import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

enum CustomBackgroundDownload {
  enum Failure: Error, Equatable { case unsupportedURL, invalidLimit, resourceLimit, httpStatus(Int) }
  static func data(from url: URL, maximumBytes: Int, session: URLSession? = nil) async throws -> Data {
    guard maximumBytes > 0, maximumBytes < Int.max else { throw Failure.invalidLimit }
    guard allows(url) else { throw Failure.unsupportedURL }
    try Task.checkCancellation()
    let transfer: URLSession
    if let session { transfer = session }
    else {
      transfer = URLSession(configuration: configuration())
    }
    defer { if session == nil { transfer.invalidateAndCancel() } }
    let (bytes, response) = try await transfer.bytes(from: url, delegate: RedirectPolicy())
    defer { bytes.task.cancel() }
    guard let response = response as? HTTPURLResponse, response.url.map(allows) == true
    else { throw Failure.unsupportedURL }
    guard (200..<300).contains(response.statusCode) else { throw Failure.httpStatus(response.statusCode) }
    guard response.expectedContentLength <= maximumBytes else { throw Failure.resourceLimit }
    let task = bytes.task
    return try await withTaskCancellationHandler {
      var data = Data()
      for try await byte in bytes {
        guard data.count < maximumBytes else { throw Failure.resourceLimit }
        if data.count % 4096 == 0 { try Task.checkCancellation() }
        data.append(byte)
      }
      try Task.checkCancellation()
      return data
    } onCancel: { task.cancel() }
  }

  static func configuration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil; configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil; configuration.httpShouldSetCookies = false
    configuration.httpCookieAcceptPolicy = .never
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 60
    return configuration
  }

  private static func allows(_ url: URL) -> Bool {
    ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
  }
  final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
      completionHandler(request.url.map(allows) == true ? request : nil)
    }
  }
}

/// Legacy display bridge. Keeps the admitted original container for the native frame pipeline.
@MainActor @Observable
final class CustomBackgroundImageLoader {
  enum State: Equatable { case empty, loading, ready, failed }
  typealias Download = @MainActor (URL, Int) async throws -> Data
  private(set) var state: State = .empty
  private(set) var encodedData: Data?
  private(set) var image: NSImage?
  private(set) var nativeImage: WebsiteConfigBackgroundResource.Image?
  var imageIdentity: UUID { generation }
  private(set) var error: Error?
  @ObservationIgnored private let download: Download
  @ObservationIgnored private let resourceLimits: WebsiteConfigBackgroundResource.Limits
  @ObservationIgnored private var generation = UUID()
  init(resourceLimits: WebsiteConfigBackgroundResource.Limits = .init(),
    download: @escaping Download = { try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1) }) {
    self.download = download; self.resourceLimits = resourceLimits
  }
  func load(remoteURL: String, maximumBytes: Int = 64 * 1024 * 1024,
    local: () throws -> Data?) async {
    clear()
    let token = generation
    state = .loading
    do {
      try Task.checkCancellation()
      guard maximumBytes > 0, maximumBytes < Int.max else { throw CustomBackgroundDownload.Failure.invalidLimit }
      let localData = try local()
      guard token == generation else { return }
      let data: Data
      let source: WebsiteConfigBackgroundResource.Source
      if let localData { data = localData; source = .local }
      else if remoteURL.isEmpty { state = .empty; return }
      else {
        guard let url = URL(string: remoteURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
          url.host?.isEmpty == false else { throw CustomBackgroundDownload.Failure.unsupportedURL }
        data = try await download(url, maximumBytes)
        source = .remote(.string(remoteURL))
      }
      try Task.checkCancellation()
      guard token == generation else { return }
      guard data.count <= maximumBytes else { throw CustomBackgroundDownload.Failure.resourceLimit }
      let owned = data.withUnsafeBytes { Data($0) }
      guard let image = NSImage(data: owned) else { throw LocalBackgroundError.unsupportedImage }
      let prepared = try WebsiteConfigBackgroundResource.prepare(loadedData: owned, source: source, limits: resourceLimits)
      switch prepared.state {
      case .ready(let native): nativeImage = native
      case .failed(.resourceLimit): throw LocalBackgroundError.resourceLimit
      case .failed, .none:
        // A PDF can be identified by ImageIO yet have no raster pixel properties.
        // Preserve native vectors, never a quota failure or a broken raster decoder.
        if let source = CGImageSourceCreateWithData(owned as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let type = CGImageSourceGetType(source) {
          let nativePDF = image.representations.contains { $0 is NSPDFImageRep }
          let nativeSVG = UTType(type as String)?.conforms(to: .svg) == true
          if !nativePDF && !nativeSVG { throw LocalBackgroundError.unsupportedImage }
        }
      }
      encodedData = owned; self.image = image; state = .ready
    } catch {
      guard token == generation else { return }
      if Task.isCancelled || error is CancellationError { clear() }
      else { self.error = error; state = .failed }
    }
  }
  func clear() {
    generation = UUID(); state = .empty; image = nil; nativeImage = nil; encodedData = nil; error = nil
  }
}
