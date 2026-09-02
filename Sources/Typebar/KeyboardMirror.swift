import Foundation

/// A Typebar-authored mirror of the physical ANSI key rows. It is applied to
/// accepted ASCII input only; composed and non-ASCII text remains untouched.
enum KeyboardMirror {
    private static let lowerMap: [Character: Character] = makeMap()

    static func transform(_ text: String) -> String {
        String(text.map(transform))
    }

    static func transform(_ character: Character) -> Character {
        guard character.isASCII else { return character }
        let lower = Character(String(character).lowercased())
        guard let mapped = lowerMap[lower] else { return character }
        return character.isUppercase ? Character(String(mapped).uppercased()) : mapped
    }

    private static func makeMap() -> [Character: Character] {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890", "-=[]\\", ";'", ",./"]
        return rows.reduce(into: [:]) { map, row in
            let source = Array(row)
            let target = Array(row.reversed())
            for (from, to) in zip(source, target) { map[from] = to }
        }
    }
}
