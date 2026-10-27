import Foundation
import Observation

struct TestSettingsLinkRoute: Identifiable {
  let id = UUID()
  let link: String
}

/// Opening a link only offers an import panel. It never applies a selection
/// or contacts a host, and retains at most one latest pending delivery.
@MainActor @Observable final class TestSettingsLinkInbox {
  var presented: TestSettingsLinkRoute?
  private(set) var pending: TestSettingsLinkRoute?
  @discardableResult func receive(_ url: URL, allowed: Bool) -> Bool {
    guard url.scheme?.lowercased() == "typebar", url.host?.lowercased() == "test",
      url.absoluteString.utf16.count <= 32_768,
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      items.contains(where: { $0.name == "testSettings" || $0.name == "preset" }) else { return false }
    let link = url.absoluteString
    if presented?.link == link || pending?.link == link { return true }
    pending = .init(link: link)
    presentNext(allowed: allowed)
    return true
  }
  func presentNext(allowed: Bool) {
    guard allowed, presented == nil, let pending else { return }
    self.pending = nil; presented = pending
  }
}
