/// Transient choreography state. First-word positioning changes the leading
/// foot, not the facing/repetition history. Never part of a saved record.
struct WebsiteArrowChart: Equatable {
  private var rightFoot = false
  private var facing = 0
  private var facingBudget = 0
  private var last = [0, 3]
  private var repeats = [0, 0]

  static func isSelected(_ configuration: TestConfiguration) -> Bool {
    configuration.websiteTextAlterationOrder != nil && configuration.modifiers.contains(.arrowStream)
  }

  mutating func word(first: Bool, randomUnit: () -> Double) -> String? {
    var next = self
    var text = ""
    for position in 0..<4 {
      guard let direction = next.step(leading: first && position == 0, randomUnit: randomUnit) else { return nil }
      text.append(Array("←↓↑→")[direction])
    }
    self = next
    return text
  }

  private mutating func step(leading: Bool, randomUnit: () -> Double) -> Int? {
    func unit() -> Double? {
      let value = randomUnit()
      return value.isFinite && value >= 0 && value < 1 ? value : nil
    }
    facingBudget -= 1
    guard let choice = unit(), unit() != nil else { return nil }
    // Preserve the second (unused) random draw in the observable source stream.
    var side = choice < 0.5 ? 0 : 1
    if leading {
      guard let foot = unit() else { return nil }
      rightFoot = foot >= 0.5
      return rightFoot ? 3 : 0
    }
    let foot = rightFoot ? 0 : 1
    repeats[foot] = last[foot] == side ? repeats[foot] + 1 : 0
    if repeats[foot] > 1 || repeats.allSatisfy({ $0 > 0 }) {
      side = 1 - side
      repeats[foot] = 0
    }
    last[foot] = side
    let direction = rightFoot ? side * (facing + 1) : 3 - side * (facing + 1)
    rightFoot.toggle()
    if facingBudget < 0 && side == 0 {
      guard let duration = unit() else { return nil }
      facing = 1 - facing
      facingBudget = Int((duration * 3).rounded(.down)) + 3
    }
    return direction
  }
}
