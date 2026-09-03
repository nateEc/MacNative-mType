import Foundation

enum QAStoreMode {
  static let inMemoryInfoKey = "TypebarQAInMemoryStore"

  static func usesInMemoryStore(info: [String: Any]) -> Bool {
    info[inMemoryInfoKey] as? Bool == true
  }
}
