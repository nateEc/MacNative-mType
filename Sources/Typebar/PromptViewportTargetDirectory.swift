import Foundation

/// Source ownership for a future whole-preview viewport. This is not a
/// drawable layout: the complete target stays with the session, while a
/// requested field window receives only its own lightweight target records.
struct PromptViewportTargetDirectory {
  struct Cell: Equatable {
    let id: Int
    let unit: UInt16
    let fieldIndex: Int
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

  let attemptID: UUID
  let targetUTF16: [UInt16]
  private let fieldRanges: [Range<Int>]
  var fieldCount: Int { fieldRanges.count }

  init?(session: TypingSession) {
    guard let source = session.promptCompositionField, source.boundary == .separated else { return nil }
    let units = source.sourceTargetUTF16
    // Every supported UTF-16 unit is one canonical target ID. CRLF can be
    // one native grapheme despite two ASCII units, so retain the full path.
    guard session.prompt.utf8.count == units.count,
      units.allSatisfy({ $0 < 128 && $0 != 13 }) else { return nil }
    var end = 0
    for range in source.sourceFieldUTF16Ranges {
      guard range.lowerBound == end, range.upperBound <= units.count else { return nil }
      end = range.upperBound
    }
    guard end == units.count else { return nil }
    attemptID = session.automaticInputAttemptID
    targetUTF16 = units
    fieldRanges = source.sourceFieldUTF16Ranges
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
      fields.append(.init(index: index, targetUTF16Range: range,
        cellIDs: Array(range),
        structuralReturnCount: targetUTF16[range].filter { $0 == 10 }.count))
      for unit in range {
        cells.append(.init(id: unit, unit: targetUTF16[unit], fieldIndex: index))
      }
    }
    return .init(attemptID: attemptID, fields: fields, cells: cells)
  }

  /// A strictly admitted first step toward window coloring. Unsupported
  /// presentation paths remain on the existing full projection.
  func materializeStates(fields requested: Range<Int>, session: TypingSession) -> [StateCell]? {
    guard let slice = materialize(fields: requested),
      session.automaticInputAttemptID == attemptID,
      session.prompt.utf16.elementsEqual(targetUTF16),
      let glyphs = session.promptViewportTargetGlyphs(in: slice.cells.map(\.id),
        targetUTF16: targetUTF16)
    else { return nil }
    return zip(slice.cells, glyphs).map { StateCell(id: $0.id, glyph: $1) }
  }
}
