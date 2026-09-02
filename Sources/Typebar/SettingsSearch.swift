import Foundation

enum SettingsSearch {
    static func matches(query: String, terms: [String]) -> Bool {
        let tokens = normalized(query).split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        let searchable = terms.map(normalized).joined(separator: " ")
        return tokens.allSatisfy { searchable.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
