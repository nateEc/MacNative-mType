import Foundation

/// Source ownership for a future whole-preview viewport. This is not a
/// drawable layout: the complete target stays with the session, while a
/// requested field window receives only its own lightweight target records.
struct PromptViewportTargetDirectory {
  struct Cell: Equatable {
    let id: Int
    let unit: UInt16
    let fieldIndex: Int
    let wordOrdinal: Int
  }

  struct Field: Equatable {
    let index: Int
    let targetUTF16Range: Range<Int>
    let cellIDs: [Int]
    let structuralReturnCount: Int
  }

  struct Slice: Equatable {
    let attemptID: UUID
    let fields: [Field]
    let cells: [Cell]
  }

  struct StateCell: Equatable {
    let id: Int
    let glyph: TypingPromptGlyph
  }

  struct IndexedWord: Equatable {
    let index: Int
    let value: TypingPromptWordPresentation
  }

  struct WindowWordStates: Equatable {
    let activeWordIndex: Int?
    let words: [IndexedWord]
  }

  let attemptID: UUID
  let promptTargetID: UUID
  let targetUTF16: [UInt16]
  private let fieldRanges: [Range<Int>]
  private let wordOrdinalsAtFieldStart: [Int]
  private let separatorOffsets: [Int]
  var fieldCount: Int { fieldRanges.count }

  init?(session: TypingSession) {
    guard let source = session.promptCompositionField, source.boundary == .separated else { return nil }
    let units = source.sourceTargetUTF16
    // Every supported UTF-16 unit is one canonical target ID. CRLF can be
    // one native grapheme despite two ASCII units, so retain the full path.
    guard session.prompt.utf16.elementsEqual(units),
      units.allSatisfy({ $0 < 128 && $0 != 13 }) else { return nil }
    var end = 0
    for range in source.sourceFieldUTF16Ranges {
      guard range.lowerBound == end, range.upperBound <= units.count else { return nil }
      end = range.upperBound
    }
    guard end == units.count else { return nil }
    attemptID = session.automaticInputAttemptID
    promptTargetID = session.promptTargetID
    targetUTF16 = units
    fieldRanges = source.sourceFieldUTF16Ranges
    var ordinal = 0
    var starts: [Int] = []
    var separators: [Int] = []
    starts.reserveCapacity(fieldRanges.count)
    for range in fieldRanges {
      starts.append(ordinal)
      for index in range where units[index] == 32 || units[index] == 10 {
        separators.append(index)
        ordinal += 1
      }
    }
    wordOrdinalsAtFieldStart = starts
    separatorOffsets = separators
  }

  func materialize(fields requested: Range<Int>) -> Slice? {
    guard requested.lowerBound >= 0, requested.upperBound <= fieldRanges.count,
      !requested.isEmpty else { return nil }
    var fields: [Field] = []
    var cells: [Cell] = []
    fields.reserveCapacity(requested.count)
    cells.reserveCapacity(fieldRanges[requested].reduce(0) { $0 + $1.count })
    for index in requested {
      let range = fieldRanges[index]
      var ordinal = wordOrdinalsAtFieldStart[index]
      fields.append(.init(index: index, targetUTF16Range: range,
        cellIDs: Array(range),
        structuralReturnCount: targetUTF16[range].filter { $0 == 10 }.count))
      for unit in range {
        let value = targetUTF16[unit]
        cells.append(.init(id: unit, unit: value, fieldIndex: index, wordOrdinal: ordinal))
        if value == 32 || value == 10 { ordinal += 1 }
      }
    }
    return .init(attemptID: attemptID, fields: fields, cells: cells)
  }

  /// A strictly admitted first step toward window coloring. Unsupported
  /// presentation paths remain on the existing full projection.
  func materializeStates(fields requested: Range<Int>, session: TypingSession) -> [StateCell]? {
    guard let slice = materialize(fields: requested),
      session.automaticInputAttemptID == attemptID,
      session.promptTargetID == promptTargetID,
      let glyphs = session.promptViewportTargetGlyphs(in: slice.cells,
        targetUTF16: targetUTF16, separatorOffsets: separatorOffsets), glyphs.count == slice.cells.count
    else { return nil }
    return zip(slice.cells, glyphs).map { StateCell(id: $0.id, glyph: $1) }
  }

  /// Source-field word ink for one window. Admission mirrors local glyph
  /// state; unsupported projections still use the full presentation.
  func materializeWordStates(fields requested: Range<Int>, session: TypingSession) -> WindowWordStates? {
    guard materializeStates(fields: requested, session: session) != nil else { return nil }
    return session.promptViewportWordStates(in: fieldRanges, requested: requested,
      targetUTF16: targetUTF16, separatorOffsets: separatorOffsets)
  }

  func completedIndices(in cells: [Cell], session: TypingSession) -> Set<Int>? {
    guard session.automaticInputAttemptID == attemptID, session.promptTargetID == promptTargetID else { return nil }
    return session.promptViewportCompletedIndices(in: cells, separatorOffsets: separatorOffsets)
  }

  /// Build only requested drawable field runs. The caller supplies appearance
  /// ink; this directory owns target identity and live state, not theme style.
  func materializeFieldRuns(fields requested: Range<Int>, session: TypingSession,
    renderGlyph: (Int, TypingPromptGlyph) -> AttributedString) -> [PromptFieldTextRun]? {
    guard let states = materializeStates(fields: requested, session: session) else { return nil }
    var runs: [PromptFieldTextRun] = []
    runs.reserveCapacity(requested.count)
    var next = 0
    for fieldIndex in requested {
      let range = fieldRanges[fieldIndex]
      var cells: [PromptFieldTextRun.Cell] = []
      cells.reserveCapacity(range.count)
      for id in range {
        guard next < states.count else { return nil }
        let state = states[next]
        guard state.id == id else { return nil }
        cells.append(.init(id: id, glyph: state.glyph, text: renderGlyph(id, state.glyph),
          isGap: id == range.upperBound - 1 && targetUTF16[id] == 32))
        next += 1
      }
      runs.append(.init(fieldID: fieldIndex, cells: cells,
        structuralReturn: targetUTF16[range].contains(10)))
    }
    return runs
  }
}
