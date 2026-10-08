import Foundation
import SwiftUI

/// The pinned notification producers emit escaped text and br elements only.
/// This is deliberately not an HTML document importer: no scripts, styles,
/// attachments, URLs, Markdown, or resource loads are interpreted.
struct LocalNoticeMessagePresentation: Equatable {
  let text: String
  let usesLiteralFallback: Bool

  static func make(_ message: String, containsHTML: Bool) -> Self {
    guard containsHTML else { return .init(text: message, usesLiteralFallback: false) }
    var text = "", cursor = message.startIndex
    while let start = message[cursor...].firstIndex(of: "<") {
      text += decodeEntities(String(message[cursor..<start]))
      guard let end = message[start...].firstIndex(of: ">") else {
        return .init(text: message, usesLiteralFallback: true)
      }
      let tag = message[message.index(after: start)..<end].lowercased()
      guard ["br", "br/", "br /"].contains(tag) else {
        return .init(text: message, usesLiteralFallback: true)
      }
      text += "\n"; cursor = message.index(after: end)
    }
    text += decodeEntities(String(message[cursor...]))
    return .init(text: text, usesLiteralFallback: false)
  }

  private static func decodeEntities(_ text: String) -> String {
    let values = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
      "&#39;": "'", "&#x2F;": "/", "&#x60;": "`"]
    // Single pass: escaped ampersands never turn an escaped literal br into markup.
    var result = "", cursor = text.startIndex
    while cursor < text.endIndex {
      if text[cursor] == "&", let end = text[cursor...].prefix(8).firstIndex(of: ";"),
        let decoded = values[String(text[cursor...end])] {
        result += decoded; cursor = text.index(after: end)
      } else { result.append(text[cursor]); cursor = text.index(after: cursor) }
    }
    return result
  }
}

struct LocalNoticeMessageView: View {
  let entry: LocalNoticeEntry
  var body: some View {
    let presentation = LocalNoticeMessagePresentation.make(entry.message, containsHTML: entry.containsHTML)
    VStack(alignment: .leading, spacing: 6) {
      Text(verbatim: presentation.text).fixedSize(horizontal: false, vertical: true)
      if presentation.usesLiteralFallback {
        Text("包含尚未支持的网页格式，按原始文本显示。").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}
