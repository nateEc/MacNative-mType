import Foundation

struct WebsiteThresholdCommandReceipt {
  let publicationID: UUID
  let acceptedSetters: Int
  let rejectedKeys: [String]
  var message: String {
    if rejectedKeys.isEmpty { return acceptedSetters == 0 ? "阈值未修改。" : "阈值已保存，当前练习继续。" }
    return acceptedSetters == 0 ? "阈值未修改。" : "前面的阈值已保存；数值未通过校验，原数值保留。"
  }
}

enum WebsiteThresholdCommandError: Error, LocalizedError {
  case invalidInput
  case partiallySaved(Error)
  var errorDescription: String? {
    switch self {
    case .invalidInput: "输入未通过阈值命令校验。"
    case .partiallySaved: "前面的阈值已保存，后续设置尚未完成。请关闭后重新打开命令重试。"
    }
  }
}
