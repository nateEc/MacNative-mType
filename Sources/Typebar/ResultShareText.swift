import Foundation

enum ResultShareText {
    static func make(for result: CompletedTestResult) -> String {
        let configuration = result.configuration
        let detail: String
        switch configuration.mode {
        case .time: detail = "\(Int(configuration.duration ?? 0)) 秒"
        case .words: detail = "\(configuration.wordLimit ?? 0) 词"
        case .quote: detail = "引语"
        case .zen: detail = "禅模式"
        case .custom: detail = "自定义文本"
        }
        return "Typebar\n\(result.wpm) WPM · \(result.accuracy)% 准确率 · \(result.errorCount) 错误\n\(configuration.mode.rawValue) · \(configuration.language.rawValue) · \(detail)"
    }
}
