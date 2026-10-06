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
  static func requireCapabilities(_ capabilities: RemoteServiceCapabilities) throws {
    guard capabilities.supportsAccountTags,
      capabilities.capabilities["accountTagEditPersonalBests"] == "available" else {
      throw RemoteAccountError.serverMessage("当前服务尚未提供标签编辑的 PB 检查，请先升级自建服务。未发送更改请求。")
    }
  }
}
