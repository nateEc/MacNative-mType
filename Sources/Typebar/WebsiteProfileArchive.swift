import Foundation

enum WebsiteProfileArchiveError: Error, LocalizedError {
  case invalidPayload, unavailable, conflict, pendingRecovery
  var errorDescription: String? {
    switch self {
    case .invalidPayload: return "完整配置备份无效或版本暂不支持，未忽略该配置。"
    case .unavailable: return "完整配置或独立文本无法安全读取，原数据未覆盖。"
    case .conflict: return "完整配置或独立文本已改变，未覆盖新的状态。"
    case .pendingRecovery: return "完整配置恢复尚未完成；记录可能已导入，请重试恢复，未报告全部成功。"
    }
  }
}

/// Saved source state only: no window-local nosave values or record revisions.
/// Native and website JSON remain distinct formats.
struct WebsiteProfileArchive: Equatable, Codable {
  let runtime: [String: WebsiteConfigValue]
  let lazyMemory: WebsiteConfigLazyModeMemory
  let customTextData: Data?
  let fallbackCustomTextData: Data?
  private static let kind = "typebar.archive.website-profile"
  static func sameRuntime(_ lhs: [String: WebsiteConfigValue], _ rhs: [String: WebsiteConfigValue]) -> Bool {
    guard let a = try? WebsiteConfigNativeStateCodec.encode(lhs), let b = try? WebsiteConfigNativeStateCodec.encode(rhs)
    else { return false }
    return a == b
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.lazyMemory == rhs.lazyMemory && lhs.customTextData == rhs.customTextData
      && lhs.fallbackCustomTextData == rhs.fallbackCustomTextData && sameRuntime(lhs.runtime, rhs.runtime)
  }
  static let maximumBytes = 41_943_040
  private struct Document: Codable {
    let kind: String
    let version: Int
    let runtimeData: Data
    let lazyRemember: Bool
    let lazyPrefersArabic: Bool
    let customTextData: Data?
    let fallbackCustomTextData: Data?
  }
  init(runtime: [String: WebsiteConfigValue], lazyMemory: WebsiteConfigLazyModeMemory,
    customTextData: Data?, fallbackCustomTextData: Data? = nil) throws {
    _ = try WebsiteConfigNativeStateCodec.encode(runtime)
    guard customTextData == nil || WebsiteCustomTextStateStore.decodeDocument(customTextData!) != nil
    else { throw WebsiteProfileArchiveError.invalidPayload }
    guard WebsiteCustomTextStateStore.acceptsFallbackArchiveDocument(fallbackCustomTextData) else { throw WebsiteProfileArchiveError.invalidPayload }
    self.runtime = runtime; self.lazyMemory = lazyMemory; self.customTextData = customTextData
    self.fallbackCustomTextData = fallbackCustomTextData
  }
  func encode(to encoder: Encoder) throws {
    _ = try Self(runtime: runtime, lazyMemory: lazyMemory, customTextData: customTextData, fallbackCustomTextData: fallbackCustomTextData)
    try Document(kind: Self.kind, version: 1, runtimeData: WebsiteConfigNativeStateCodec.encode(runtime),
      lazyRemember: lazyMemory.remember, lazyPrefersArabic: lazyMemory.prefersArabic,
      customTextData: customTextData, fallbackCustomTextData: fallbackCustomTextData).encode(to: encoder)
  }
  init(from decoder: Decoder) throws {
    let value = try Document(from: decoder)
    guard value.kind == Self.kind, value.version == 1 else { throw WebsiteProfileArchiveError.invalidPayload }
    try self.init(runtime: WebsiteConfigNativeStateCodec.decode(value.runtimeData),
      lazyMemory: .init(remember: value.lazyRemember, prefersArabic: value.lazyPrefersArabic),
      customTextData: value.customTextData, fallbackCustomTextData: value.fallbackCustomTextData)
  }
  func archiveData() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maximumBytes else { throw WebsiteProfileArchiveError.invalidPayload }
    return data
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= Self.maximumBytes else { throw WebsiteProfileArchiveError.invalidPayload }
    return try JSONDecoder().decode(Self.self, from: data)
  }
}
