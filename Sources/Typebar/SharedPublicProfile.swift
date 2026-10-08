import AppKit
import Foundation
import Observation

enum SharedProfileLinkError: Error, Equatable, LocalizedError {
  case invalidLink, invalidServer, unsupportedVersion, invalidResponse, responseTooLarge
  case httpStatus(Int)

  var errorDescription: String? {
    switch self {
    case .invalidLink: "这不是有效的 Typebar 公开资料链接。"
    case .invalidServer: "资料链接需使用不含凭据、查询或片段的 HTTP(S) 服务地址。"
    case .unsupportedVersion: "此公开资料链接版本暂不受支持。"
    case .invalidResponse: "服务器没有返回匹配的公开资料。"
    case .responseTooLarge: "公开资料响应过大，已停止读取。"
    case .httpStatus(let status): "公开资料读取失败（HTTP \(status)）；不会自动跟随重定向。"
    }
  }
}

struct SharedProfileTarget: Equatable, Hashable, Sendable {
  let server: URL
  let profileID: UUID

  init(server: String, profileID: UUID) throws {
    let value = server.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.utf8.count <= 2_048,
      value.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
      var components = URLComponents(string: value),
      let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
      let host = components.host?.lowercased(), !host.isEmpty,
      !(components.percentEncodedHost?.contains("%") ?? true),
      components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
      components.port.map({ (1...65_535).contains($0) }) ?? true,
      !components.percentEncodedPath.contains("%")
    else { throw SharedProfileLinkError.invalidServer }
    let segments = components.path.split(separator: "/", omittingEmptySubsequences: false)
    guard !segments.contains(where: { $0 == "." || $0 == ".." }),
      components.path.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/-._~".contains($0)) })
    else { throw SharedProfileLinkError.invalidServer }
    components.scheme = scheme; components.host = host
    if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
      components.port = nil
    }
    while components.path.hasSuffix("/") { components.path.removeLast() }
    guard let url = components.url, url.host != nil else { throw SharedProfileLinkError.invalidServer }
    self.server = url; self.profileID = profileID
  }

  var requestURL: URL { server.appendingPathComponent("v1/profiles/\(profileID.uuidString.lowercased())") }
  var usesPlainHTTP: Bool { server.scheme == "http" }
}

enum SharedProfileLinkCodec {
  static func link(for target: SharedProfileTarget) -> String {
    var components = URLComponents()
    components.scheme = "typebar"; components.host = "profile"
    components.queryItems = [.init(name: "v", value: "1"), .init(name: "server", value: target.server.absoluteString),
      .init(name: "id", value: target.profileID.uuidString.lowercased())]
    return components.string! // All components originate from validated values.
  }

  static func target(from raw: String) throws -> SharedProfileTarget {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.utf8.count <= 4_096, let components = URLComponents(string: value),
      components.scheme?.lowercased() == "typebar", components.host?.lowercased() == "profile",
      components.user == nil, components.password == nil, components.port == nil,
      components.path.isEmpty, components.fragment == nil,
      let items = components.queryItems, items.count == 3,
      Set(items.map(\.name)) == Set(["v", "server", "id"])
    else { throw SharedProfileLinkError.invalidLink }
    let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    guard values["v"] == "1" else { throw SharedProfileLinkError.unsupportedVersion }
    guard let rawID = values["id"], rawID.count == 36, let id = UUID(uuidString: rawID),
      let server = values["server"] else { throw SharedProfileLinkError.invalidLink }
    return try SharedProfileTarget(server: server, profileID: id)
  }
}

@MainActor @Observable final class ProfileShareCopyState {
  private(set) var message: String?
  private(set) var fallbackLink: String?

  func copy(target: SharedProfileTarget, write: (String) -> Bool) {
    let link = SharedProfileLinkCodec.link(for: target)
    let success = write(link)
    message = success ? "已复制 Typebar 公开资料链接。" : "无法写入剪贴板，请手动复制下方链接。"
    fallbackLink = success ? nil : link
  }
  func clear() { message = nil; fallbackLink = nil }
}

/// A separate ephemeral anonymous session. Never touches AccountSession, its
/// Keychain, default cookies, credential storage, or configured server.
struct SharedProfileReadClient: Sendable {
  let configuration: URLSessionConfiguration
  let maximumResponseBytes: Int

  init(configuration: URLSessionConfiguration = .ephemeral, maximumResponseBytes: Int = 8_388_608) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil; configuration.urlCache = nil
    configuration.httpAdditionalHeaders = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30
    self.configuration = configuration; self.maximumResponseBytes = maximumResponseBytes
  }

  func load(_ target: SharedProfileTarget) async throws -> RemotePublicProfile {
    let data = try await data(from: target.requestURL)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let profile = try decoder.decode(RemotePublicProfile.self, from: data)
    guard profile.id == target.profileID else { throw SharedProfileLinkError.invalidResponse }
    return profile
  }

  func data(from url: URL, accept: String = "application/json") async throws -> Data {
    try Task.checkCancellation()
    let session = URLSession(configuration: configuration, delegate: SharedProfileReadDelegate(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"; request.setValue(accept, forHTTPHeaderField: "Accept")
    request.httpShouldHandleCookies = false
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse, response.url == url else {
      throw SharedProfileLinkError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else { throw SharedProfileLinkError.httpStatus(response.statusCode) }
    guard response.expectedContentLength <= maximumResponseBytes else { throw SharedProfileLinkError.responseTooLarge }
    var data = Data()
    for try await byte in bytes {
      try Task.checkCancellation()
      guard data.count < maximumResponseBytes else { throw SharedProfileLinkError.responseTooLarge }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }
}

final class SharedProfileReadDelegate: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
    completionHandler(nil) // The user confirmed one server, not a redirect destination.
  }

  func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    complete(challenge, completionHandler: completionHandler)
  }
  func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    complete(challenge, completionHandler: completionHandler)
  }
  private func complete(_ challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
      ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
  }
}

@MainActor @Observable final class SharedProfileLoadState {
  private(set) var isConfirmed = false
  private(set) var isLoading = false
  private(set) var profile: RemotePublicProfile?
  private(set) var message: String?
  private var generation = UUID()

  func load(target: SharedProfileTarget, fetch: () async throws -> RemotePublicProfile) async {
    guard !Task.isCancelled else { return }
    let generation = UUID(); self.generation = generation
    isConfirmed = true; isLoading = true; profile = nil; message = nil
    defer { if self.generation == generation { isLoading = false } }
    do {
      let profile = try await fetch()
      guard self.generation == generation else { return }
      try Task.checkCancellation()
      guard profile.id == target.profileID else { throw SharedProfileLinkError.invalidResponse }
      self.profile = profile
    } catch {
      guard self.generation == generation else { return }
      if Task.isCancelled || error is CancellationError { cancel(); return }
      message = "公开资料读取失败，请重试：" + error.localizedDescription
    }
  }

  func cancel() {
    generation = UUID(); isConfirmed = false; isLoading = false; profile = nil; message = nil
  }
}

struct SharedProfileRoute: Identifiable {
  let id = UUID()
  let target: SharedProfileTarget?
  let message: String?
  init(link: String) {
    do { target = try SharedProfileLinkCodec.target(from: link); message = nil }
    catch { target = nil; message = error.localizedDescription }
  }
}

/// One current presentation plus one latest pending URL; no unbounded queue.
@MainActor @Observable final class SharedProfileLinkInbox {
  var presented: SharedProfileRoute?
  private(set) var pending: SharedProfileRoute?

  @discardableResult func receive(_ url: URL, allowed: Bool) -> Bool {
    guard url.scheme?.lowercased() == "typebar", url.host?.lowercased() == "profile" else { return false }
    let route = SharedProfileRoute(link: url.absoluteString)
    if route.target != nil, route.target == presented?.target || route.target == pending?.target { return true }
    pending = route
    presentNext(allowed: allowed)
    return true
  }
  func presentNext(allowed: Bool) {
    guard allowed, presented == nil, let pending else { return }
    self.pending = nil; presented = pending
  }
}
