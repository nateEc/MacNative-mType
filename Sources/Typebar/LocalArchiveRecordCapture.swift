import Foundation

/// Export must not silently omit an opaque row while reporting a complete
/// backup or upload. Preserve the database and fail the whole capture instead.
@MainActor enum LocalArchiveRecordCapture {
  struct Failure: LocalizedError {
    let kind: String
    var errorDescription: String? { "有\(kind)记录无法无损读取，未导出不完整备份。原数据库未修改。" }
  }
  static func results(_ records: [TestResultRecord]) throws -> [CompletedTestResult] {
    try records.map {
      guard let value = $0.portableResult else { throw Failure(kind: "成绩") }
      return value
    }
  }
  static func presets(_ records: [TestPresetRecord]) throws -> [NamedPreset] {
    try records.map {
      guard let value = $0.definition else { throw Failure(kind: "预设") }
      return NamedPreset(id: $0.id, name: $0.name, definition: value)
    }
  }
  static func filters(_ records: [ResultFilterPresetRecord]) throws -> [NamedResultFilterPreset] {
    try records.map {
      guard let value = $0.portablePreset else { throw Failure(kind: "筛选预设") }
      return value
    }
  }
}
