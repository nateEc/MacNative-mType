import Foundation

enum WebsiteSharedLinkApplication {
  case applied(String), retained(String)
}

/// Transport admission only. Keep the JSON intact for the ordered receiver;
/// JSONSerialization would replace raw UTF-16 and reject overflowing numbers.
enum WebsiteSharedLinkImport {
  static func json(from link: String) throws -> String? {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URLComponents(string: trimmed) else { return nil }
    // The website compares the raw key, decodes only the value, and keeps
    // the final occurrence. URLComponents.queryItems also decodes keys, so
    // it cannot stand in for the pinned source's query lookup.
    let beforeFragment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
    guard let queryStart = beforeFragment.firstIndex(of: "?") else { return nil }
    let entries = beforeFragment[beforeFragment.index(after: queryStart)...]
      .split(separator: "&", omittingEmptySubsequences: false)
      .map { $0.split(separator: "=", omittingEmptySubsequences: false) }
      .filter { $0.first == "testSettings" }
    guard let selected = entries.last else { return nil }
    guard trimmed.utf16.count <= 32_768,
      let scheme = url.scheme?.lowercased(),
      ["https", "http", "typebar"].contains(scheme),
      let host = url.host, !host.isEmpty,
      scheme != "typebar" || (host.lowercased() == "test" && url.path.isEmpty
        && url.user == nil && url.password == nil && url.port == nil
        && url.fragment == nil && url.queryItems?.count == 1),
      let compressed = (selected.count > 1 ? String(selected[1]) : "undefined").removingPercentEncoding,
      !compressed.isEmpty, compressed.utf16.count <= 32_768,
      let json = URICompressedPayload.decompress(compressed),
      let value = try? WebsiteConfigJSONReader.read(json), case .array(let fields) = value, fields.count == 8 else {
      throw LegacyTestSettingsLinkImporter.ImportError.invalidLink
    }
    return json
  }
}
