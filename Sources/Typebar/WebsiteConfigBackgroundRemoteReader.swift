import Foundation

/// Transport bytes only. Never opens a local path or changes the raw intent.
@MainActor
struct WebsiteConfigBackgroundRemoteReader {
  enum Failure: Error { case invalidAddress, malformedData }
  typealias Download = @MainActor (URL, Int) async throws -> Data
  let baseURL: URL?
  private let download: Download
  init(baseURL: URL? = nil, download: @escaping Download = {
    try await CustomBackgroundDownload.data(from: $0, maximumBytes: $1)
  }) { self.baseURL = baseURL; self.download = download }

  func read(address: WebsiteConfigValue, maximumBytes: Int) async throws -> WebsiteConfigBackgroundResource.Remote {
    guard maximumBytes > 0, maximumBytes < Int.max else { throw CustomBackgroundDownload.Failure.invalidLimit }
    guard let units = address.stringUnits else { throw Failure.invalidAddress }
    try Task.checkCancellation()
    var lower = 0, upper = units.count
    while lower < upper, units[lower] <= 32 { lower += 1 }
    while upper > lower, units[upper - 1] <= 32 { upper -= 1 }
    let text = String(decoding: units[lower..<upper].filter { $0 != 9 && $0 != 10 && $0 != 13 }, as: UTF16.self)
    do {
      let data: Data
      if text.prefix(5).lowercased() == "data:" { data = try dataURL(text, maximumBytes: maximumBytes) }
      else {
        guard let url = httpURL(text) else { return .failed(address: address) }
        data = try await download(url, maximumBytes)
      }
      try Task.checkCancellation()
      guard data.count <= maximumBytes else { throw CustomBackgroundDownload.Failure.resourceLimit }
      return .received(address: address, data: data.withUnsafeBytes { Data($0) })
    } catch {
      if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
      return .failed(address: address, reason: (error as? CustomBackgroundDownload.Failure) == .resourceLimit ? .resourceLimit : .transport)
    }
  }

  private func httpURL(_ text: String) -> URL? {
    let suffix = text.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? text.endIndex
    var head = text[..<suffix].replacingOccurrences(of: "\\", with: "/")
    let tail = String(text[suffix...])
    if let colon = head.firstIndex(of: ":"), ["http", "https"].contains(head[..<colon].lowercased()) {
      let scheme = head[..<colon].lowercased()
      let rest = String(head[head.index(after: colon)...])
      if baseURL?.scheme?.lowercased() == scheme, !rest.hasPrefix("//") { head = rest }
      else { head = scheme + "://" + rest.drop(while: { $0 == "/" }) }
    }
    guard let url = URL(string: head + tail, relativeTo: baseURL)?.absoluteURL,
      var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
      let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let host = components.host, !host.isEmpty else { return nil }
    components.scheme = scheme; components.host = host.lowercased()
    if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) { components.port = nil }
    let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    var output: [Substring] = []
    for (index, segment) in segments.enumerated() {
      let dot = segment.replacingOccurrences(of: "%2e", with: ".", options: .caseInsensitive)
      if dot == "." || dot == ".." {
        if dot == "..", output.count > 1 { output.removeLast() }
        if index == segments.count - 1 { output.append("") }
      } else { output.append(segment) }
    }
    components.percentEncodedPath = output.joined(separator: "/")
    if let query = components.percentEncodedQuery { components.percentEncodedQuery = query.replacingOccurrences(of: "'", with: "%27") }
    return components.url
  }

  private func dataURL(_ text: String, maximumBytes: Int) throws -> Data {
    let input = Array(text.utf8), end = input.firstIndex(of: 35) ?? input.count
    guard let comma = input[5..<end].firstIndex(of: 44) else { throw Failure.malformedData }
    var start = 5, stop = comma
    while start < stop, Self.whitespace(input[start]) { start += 1 }
    while stop > start, Self.whitespace(input[stop - 1]) { stop -= 1 }
    var base64 = false
    if stop - start >= 7, input[(stop - 6)..<stop].map({ (65...90).contains($0) ? $0 + 32 : $0 }) == Array("base64".utf8) {
      var separator = stop - 6
      while separator > start, input[separator - 1] == 32 { separator -= 1 }
      base64 = separator > start && input[separator - 1] == 59
    }
    var data = Data(), encoded: [UInt8] = [], padding = 0, alphabetCount = 0
    var position = comma + 1
    while position < end {
      if position % 4096 == 0 { try Task.checkCancellation() }
      let byte: UInt8
      if input[position] == 37, position + 2 < end,
        let a = Self.hex(input[position + 1]), let b = Self.hex(input[position + 2]) {
        byte = a * 16 + b; position += 3
      } else { byte = input[position]; position += 1 }
      if base64 {
        if Self.whitespace(byte) { continue }
        if byte == 61 {
          padding += 1
          guard padding <= 2 else { throw Failure.malformedData }
        } else {
          guard padding == 0, Self.alphabet(byte) else { throw Failure.malformedData }
          alphabetCount += 1
          let remainder = alphabetCount % 4
          let decodedCount = alphabetCount / 4 * 3 + (remainder > 1 ? remainder - 1 : 0)
          guard decodedCount <= maximumBytes else { throw CustomBackgroundDownload.Failure.resourceLimit }
        }
        encoded.append(byte)
      } else {
        guard data.count < maximumBytes else { throw CustomBackgroundDownload.Failure.resourceLimit }
        data.append(byte)
      }
    }
    if !base64 { return data }
    if encoded.count % 4 == 0 { while encoded.last == 61 { encoded.removeLast() } }
    guard encoded.count % 4 != 1, encoded.allSatisfy(Self.alphabet) else { throw Failure.malformedData }
    while encoded.count % 4 != 0 { encoded.append(61) }
    guard let decoded = Data(base64Encoded: Data(encoded)), decoded.count <= maximumBytes else { throw Failure.malformedData }
    return decoded
  }
  private static func whitespace(_ byte: UInt8) -> Bool { byte == 9 || byte == 10 || byte == 12 || byte == 13 || byte == 32 }
  private static func alphabet(_ byte: UInt8) -> Bool {
    (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 43 || byte == 47
  }
  private static func hex(_ byte: UInt8) -> UInt8? {
    switch byte {
    case 48...57: byte - 48
    case 65...70: byte - 55
    case 97...102: byte - 87
    default: nil
    }
  }
}
