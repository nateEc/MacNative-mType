import Foundation

struct RemoteAccountTagEditResponse: Decodable {
  let result: RemoteAccountResult
  let tagPbs: [UUID]
  private enum CodingKeys: String, CodingKey { case tagPbs }
  init(from decoder: Decoder) throws {
    result = try RemoteAccountResult(from: decoder)
    tagPbs = try decoder.container(keyedBy: CodingKeys.self).decode([UUID].self, forKey: .tagPbs)
    try RemoteAccountTagPolicy.validateIDs(tagPbs)
    guard Set(tagPbs).isSubset(of: Set(result.accountTagIDs ?? [])) else { throw RemoteAccountError.unexpectedResponse }
  }
}

enum RemoteAccountTagEditPolicy {
  static func editableResult(id: UUID, history: AccountTagHistoryCache?,
    lastResult: RemoteAccountResult?) throws -> RemoteAccountResult {
    if let history, history.isComplete {
      guard let result = history.results.first(where: { $0.id == id }) else { throw RemoteAccountError.unexpectedResponse }
      return result
    }
    guard let lastResult, lastResult.id == id else {
      throw RemoteAccountError.serverMessage("最后成绩尚未就绪，或不是这条成绩。未发送更改请求。")
    }
    return lastResult
  }

  static func requireCapabilities(_ capabilities: RemoteServiceCapabilities) throws {
    guard capabilities.supportsAccountTags,
      capabilities.capabilities["accountTagEditPersonalBests"] == "available" else {
      throw RemoteAccountError.serverMessage("当前服务尚未提供标签编辑的 PB 检查，请先升级自建服务。未发送更改请求。")
    }
  }
}
