import Foundation

/// Presentation is distinct from accepted-text reconstruction and grading.
enum FieldReplayPresentation {
  static func glyphs(prompt: String, events: [TypingReplayEvent], through elapsed: TimeInterval,
    configuration: TestConfiguration? = nil,
    targetWordDirectory: ResultTargetWordDirectory? = nil) -> [TypingPromptGlyph] {
    FieldReplayPlan.make(prompt: prompt, events: events, configuration: configuration,
      targetWordDirectory: targetWordDirectory)?
      .frame(through: elapsed).presentation.glyphs
      ?? TypingReplay.inputGlyphs(prompt: prompt, events: events, through: elapsed, configuration: configuration)
  }
}

/// Target-letter state is separate from the input-field snapshots used for
/// grading. Cursor positions count rendered letters; deletion positions retain
/// the source's UTF-16 numeric length, even when these units differ.
struct FieldReplayPlan {
  struct Coordinate: Equatable, Comparable {
    let word: Int
    let position: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.word == rhs.word ? lhs.position < rhs.position : lhs.word < rhs.word
    }
  }

  struct Letter: Equatable {
    let text: String
    let extra: Bool
    var correct = false
    var incorrect = false
    var state: TypingPromptCharacterState {
      incorrect ? (extra ? .extra : .incorrect) : correct ? .correct : .pending
    }
    var unmarked: Bool { !extra && !correct && !incorrect }
  }

  struct Field: Equatable {
    var letters: [Letter]
    var isError = false
  }

  struct Presentation {
    var glyphs: [TypingPromptGlyph] = []
    var coordinates: [Coordinate] = []
    var errorIndices: Set<Int> = []
    var text: String { String(glyphs.map(\.character)) }
  }

  struct Frame: Equatable {
    var fields: [Field]
    var word = 0
    var position = 0
    var nextActionIndex = 0
    var coordinate: Coordinate { .init(word: word, position: position) }
    var presentation: Presentation {
      var result = Presentation()
      for (word, field) in fields.enumerated() {
        for (position, letter) in field.letters.enumerated() {
          // An extra source DOM letter may contain a multi-character string.
          // All its native display spans refer to the same action coordinate.
          for character in letter.text {
            if field.isError { result.errorIndices.insert(result.glyphs.count) }
            result.glyphs.append(.init(character: character, state: letter.state))
            result.coordinates.append(.init(word: word, position: position))
          }
        }
      }
      return result
    }
  }

  struct Seek {
    let frame: Frame
    let nextOffset: TimeInterval
  }

  let actions: [TypingReplay.FieldAction]
  let initialFrame: Frame
  let maximumSeekCoordinate: Coordinate?

  static func make(prompt: String, events: [TypingReplayEvent],
    configuration: TestConfiguration? = nil,
    targetWordDirectory: ResultTargetWordDirectory? = nil) -> Self? {
    // Partial/imported tapes must not index a missing target or retreat before
    // the first rendered word. They keep the legacy viewer, without backfill.
    let ordered = TypingReplay.chronologicalEvents(events)
    // A captured no-space catalog can have leading empty targets. The source
    // still initializes display word zero, not the first recorded field index.
    let capturedNoSpace = targetWordDirectory?.noSpace == true
    guard ordered.first?.inputField?.index == 0 || capturedNoSpace,
      ordered.allSatisfy({ $0.offset.isFinite && $0.offset >= 0 }),
      let actions = TypingReplay.fieldActions(prompt: prompt, events: ordered, configuration: configuration,
        targetWordDirectory: targetWordDirectory)
    else { return nil }
    var wordCount = 0
    for action in actions {
      switch action.kind {
      case .advance: wordCount += 1
      case .retreat: wordCount -= 1
      default: break
      }
      guard wordCount >= 0 else { return nil }
    }
    let targets = configuration?.mode == .zen
      ? SavedTextInputHistoryPolicy.inputFields(events: ordered)
      : TypingReplay.replayTargetFields(prompt: prompt, configuration: configuration,
        targetWordDirectory: targetWordDirectory) ?? []
    guard !targets.isEmpty else { return nil }
    // The original initializes the net final word prefix, not max visited.
    let fields = targets.prefix(min(targets.count, wordCount + 1)).map { target in
      Field(letters: target.unicodeScalars.map { Letter(text: String($0), extra: false) })
    }
    let initial = Frame(fields: fields)
    var probe = initial
    var maximum: Coordinate?
    for action in actions {
      maximum = max(maximum ?? probe.coordinate, probe.coordinate)
      _ = apply(action, to: &probe)
    }
    return .init(actions: actions, initialFrame: initial, maximumSeekCoordinate: maximum)
  }

  func frame(through elapsed: TimeInterval) -> Frame {
    var frame = initialFrame
    _ = advance(&frame, through: elapsed)
    return frame
  }

  /// Resume by action index, not timestamp: a character seek may stop in the
  /// middle of several actions sharing the same original input timestamp.
  func advance(_ frame: inout Frame, through elapsed: TimeInterval) -> [TypingReplaySoundCue] {
    var cues: [TypingReplaySoundCue] = []
    while actions.indices.contains(frame.nextActionIndex),
      actions[frame.nextActionIndex].offset <= elapsed
    {
      let action = actions[frame.nextActionIndex]
      if Self.apply(action, to: &frame) { cues.append(action.soundCue) }
      frame.nextActionIndex += 1
    }
    return cues
  }

  func seek(_ coordinate: Coordinate) -> Seek? {
    guard coordinate.word >= 0, coordinate.position >= 0,
      let maximumSeekCoordinate, coordinate <= maximumSeekCoordinate
    else { return nil }
    var frame = initialFrame
    while frame.coordinate < coordinate, actions.indices.contains(frame.nextActionIndex) {
      _ = Self.apply(actions[frame.nextActionIndex], to: &frame)
      frame.nextActionIndex += 1
    }
    guard frame.coordinate >= coordinate, actions.indices.contains(frame.nextActionIndex) else { return nil }
    return .init(frame: frame, nextOffset: actions[frame.nextActionIndex].offset)
  }

  @discardableResult private static func apply(_ action: TypingReplay.FieldAction, to frame: inout Frame) -> Bool {
    // Source handleDisplayLogic ignores the entire action if activeWord is
    // absent. Preserve that behavior; guard malformed backward destinations.
    guard frame.fields.indices.contains(frame.word) else { return false }
    switch action.kind {
    case .input(let text, let correct):
      if correct {
        if frame.fields[frame.word].letters.indices.contains(frame.position) {
          frame.fields[frame.word].letters[frame.position].correct = true
        }
      } else {
        if frame.position >= frame.fields[frame.word].letters.count {
          frame.fields[frame.word].letters.append(.init(text: text, extra: true))
        }
        if frame.fields[frame.word].letters.indices.contains(frame.position) {
          frame.fields[frame.word].letters[frame.position].incorrect = true
        }
      }
      frame.position += 1
    case .resize(let position):
      frame.position = position
      let suffix = min(position, frame.fields[frame.word].letters.count)
      for index in (suffix..<frame.fields[frame.word].letters.count).reversed() {
        if frame.fields[frame.word].letters[index].extra {
          frame.fields[frame.word].letters.remove(at: index)
        } else {
          frame.fields[frame.word].letters[index].correct = false
          frame.fields[frame.word].letters[index].incorrect = false
        }
      }
    case .advance(let correct):
      if !correct { frame.fields[frame.word].isError = true }
      frame.word += 1
      frame.position = 0
    case .retreat:
      guard frame.word > 0 else { return false }
      frame.word -= 1
      frame.position = frame.fields[frame.word].letters.count
      while frame.position > 0, frame.fields[frame.word].letters[frame.position - 1].unmarked {
        frame.position -= 1
      }
      frame.fields[frame.word].isError = false
    }
    return true
  }
}
