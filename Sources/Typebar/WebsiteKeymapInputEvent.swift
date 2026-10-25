import Foundation

/// A transient primitive event keeps source units, including lone surrogates.
struct WebsiteKeymapInputEvent: Equatable {
  let units: [UInt16]
  let isCorrect: Bool
}
