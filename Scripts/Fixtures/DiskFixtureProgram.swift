import Foundation
import SwiftData

enum DiskFixtureFailure: Error {
  case invalidArguments, unsafePath, missingField(String), invalidValue(String)
}

enum DiskFixtureValue {
  static func optional<T>(_ values: [String: Any], _ key: String, as: T.Type) throws -> T? {
    guard let value = values[key], !(value is NSNull) else { return nil }
    return try required(values, key, as: T.self)
  }

  static func required<T>(_ values: [String: Any], _ key: String, as: T.Type) throws -> T {
    guard let value = values[key] else { throw DiskFixtureFailure.missingField(key) }
    if T.self == UUID.self, let text = value as? String, let id = UUID(uuidString: text) { return id as! T }
    if T.self == Data.self, let text = value as? String, let data = Data(base64Encoded: text) { return data as! T }
    if T.self == Date.self, let seconds = value as? Double { return Date(timeIntervalSinceReferenceDate: seconds) as! T }
    if let parsed = value as? T { return parsed }
    throw DiskFixtureFailure.invalidValue(key)
  }

  static func encode(_ value: Any) -> Any {
    switch value {
    case let value as UUID: value.uuidString
    case let value as Data: value.base64EncodedString()
    case let value as Date: value.timeIntervalSinceReferenceDate
    default: value
    }
  }
}

// Same descriptor representation is compared to actual production models by
// XCTest, including defaults, types, optionals and uniqueness constraints.
func diskSchemaDescription(_ schema: Schema) -> [String: Any] {
  Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
    let fields: [[String: Any]] = entity.properties.sorted { $0.name < $1.name }.map { property in
      let attribute = property as? Schema.Attribute
      return ["name": property.name, "originalName": property.originalName,
        "type": String(reflecting: property.valueType), "optional": property.isOptional,
        "unique": property.isUnique, "transient": property.isTransient,
        "default": attribute?.defaultValue.map { String(describing: $0) } ?? "<nil>",
        "hashModifier": attribute?.hashModifier ?? "<nil>"]
    }
    return (entity.name, ["properties": fields,
      "unique": entity.uniquenessConstraints.map { $0.sorted() }.sorted { $0.joined() < $1.joined() }] as [String: Any])
  })
}

@main
@MainActor
enum DiskFixtureProgram {
  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let schema = Schema([TestResultRecord.self, TestPresetRecord.self,
      SavedCustomTextRecord.self, ResultFilterPresetRecord.self])
    if arguments.count == 2, arguments[0] == "schema" {
      try write(["schema": diskSchemaDescription(schema)], to: arguments[1]); return
    }
    guard arguments.count == 4, ["create", "inspect"].contains(arguments[0]) else {
      throw DiskFixtureFailure.invalidArguments
    }
    let store = URL(fileURLWithPath: arguments[1]).standardizedFileURL.resolvingSymlinksInPath()
    let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
    guard store.path.hasPrefix(temporary.path + "/"), store.lastPathComponent == "store.sqlite",
      store.pathComponents.contains(where: { $0.hasPrefix("typebar-disk-migration-") })
    else { throw DiskFixtureFailure.unsafePath }
    let creates = arguments[0] == "create"
    guard creates != FileManager.default.fileExists(atPath: store.path) else {
      throw DiskFixtureFailure.unsafePath
    }
    let container = try ModelContainer(for: schema,
      configurations: ModelConfiguration(url: store, allowsSave: creates, cloudKitDatabase: .none))
    container.mainContext.autosaveEnabled = false
    if creates {
      let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
      guard let rows = payload as? [String: [[String: Any]]] else { throw DiskFixtureFailure.invalidArguments }
      try diskFixtureInsert(rows, into: container.mainContext)
      try container.mainContext.save()
    }
    try write(["schema": diskSchemaDescription(container.schema),
      "rows": diskFixtureRows(container.mainContext)], to: arguments[3])
  }

  private static func write(_ value: [String: Any], to path: String) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
      .write(to: URL(fileURLWithPath: path), options: .atomic)
  }
}
