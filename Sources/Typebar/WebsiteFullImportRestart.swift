import Foundation

/// Synchronous state seen by the first test-page restart listener during a
/// full JSON application. Later setters must not decide old-attempt saving.
struct WebsiteFullImportRestart {
  let runtime: [String: WebsiteConfigValue]
  var savesIncomplete: Bool { runtime["resultSaving"] == .bool(true) }
  var repeatedPace: Bool { runtime["repeatedPace"] == .bool(true) }

  init(projection: WebsiteConfigRuntimeProjection, defaults: [String: WebsiteConfigValue]) throws {
    guard projection.events.first?.key == "fullConfigChange" else {
      throw WebsiteConfigProjectionError.invalidInput
    }
    var current = defaults
    for event in projection.events {
      if let value = event.newValue { current[event.key] = value }
      if event.key == "language" {
        runtime = current
        return
      }
    }
    throw WebsiteConfigProjectionError.invalidOrder
  }
}
