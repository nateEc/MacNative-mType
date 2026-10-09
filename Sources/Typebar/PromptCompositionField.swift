import Foundation

/// A read-only source field, not a split of the rendered/decoded input.
/// A field boundary can lie inside a canonical macOS grapheme. Such a slice
/// is an association, never permission to replace the whole glyph by its ID.
struct PromptCompositionField {
  enum Boundary { case separated, hidden, unsegmented, zen }

  struct TargetGlyphSlice: Equatable {
    let glyphID: Int
    let fieldUTF16Range: Range<Int>
    let glyphUTF16Range: Range<Int>
    let glyphUTF16Count: Int
    var isWholeGlyph: Bool { glyphUTF16Range == 0..<glyphUTF16Count }
  }

  let index: Int
  let boundary: Boundary
  /// Displayed target: a literal trailing SPACE is a commit gap, whereas
  /// Return remains a target letter. The validation catalog is unchanged.
  let targetUTF16: [UInt16]
  let inputUTF16: [UInt16]
  let targetGlyphSlices: [TargetGlyphSlice]
  let targetUTF16Range: Range<Int>
  let sourceTargetUTF16: [UInt16]
  let sourceFieldUTF16Ranges: [Range<Int>]

  init(index: Int, boundary: Boundary, inputUTF16: [UInt16],
    targets: UnitInputTargets, targetRange: Range<Int>, sourceFieldUTF16Ranges: [Range<Int>]? = nil) {
    self.index = index
    self.boundary = boundary
    self.inputUTF16 = inputUTF16
    self.sourceTargetUTF16 = targets.units
    self.sourceFieldUTF16Ranges = sourceFieldUTF16Ranges ?? targets.fields
    var targetRange = targetRange
    if boundary == .separated || boundary == .hidden,
      !targetRange.isEmpty, targets.units[targetRange.upperBound - 1] == 32 {
      targetRange = targetRange.lowerBound..<(targetRange.upperBound - 1)
    }
    targetUTF16 = Array(targets.units[targetRange])
    targetUTF16Range = targetRange
    var slices = [TargetGlyphSlice]()
    var unit = targetRange.lowerBound
    while unit < targetRange.upperBound {
      let id = targets.glyphs[unit]
      var glyphStart = unit, glyphEnd = unit + 1
      while glyphStart > 0, targets.glyphs[glyphStart - 1] == id { glyphStart -= 1 }
      while glyphEnd < targets.glyphs.count, targets.glyphs[glyphEnd] == id { glyphEnd += 1 }
      let end = min(glyphEnd, targetRange.upperBound)
      slices.append(.init(glyphID: id,
        fieldUTF16Range: (unit - targetRange.lowerBound)..<(end - targetRange.lowerBound),
        glyphUTF16Range: (unit - glyphStart)..<(end - glyphStart), glyphUTF16Count: glyphEnd - glyphStart))
      unit = end
    }
    targetGlyphSlices = slices
  }
}

extension PromptCompositionPlan {
  init(field: PromptCompositionField, composition: String, style: CompositionDisplayStyle) {
    self.init(target: String(decoding: field.targetUTF16, as: UTF16.self),
      input: String(decoding: field.inputUTF16, as: UTF16.self), composition: composition,
      isZen: field.boundary == .zen, style: style)
  }
}
