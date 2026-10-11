import XCTest
@testable import Typebar

final class ProviderFieldTargetTests: XCTestCase {
  func testTransformedBatchOnlyRetainsExactNonemptyProviderFields() {
    let fields = ["north\nsouth ", "tail"]
    XCTAssertEqual(TransformedPromptBatch(text: fields.joined(), sourceFields: fields).sourceFields, fields)
    for invalid in [[], ["wrong"], ["", fields.joined()]] {
      XCTAssertNil(TransformedPromptBatch(text: fields.joined(), sourceFields: invalid).sourceFields)
    }
    XCTAssertNil(TransformedPromptBatch(text: "e\u{301}\ntail", sourceFields: ["é\ntail"]).sourceFields)
  }

  func testExplicitProviderFieldsRetainInternalLineFeedAsContent() {
    let fields = ["north\nsouth ", "harbor ", "tail"]
    let targets = UnitInputTargets(fields.joined(), sourceFields: fields)
    XCTAssertTrue(targets.requiresUnitInput)
    XCTAssertFalse(targets.noSpace)
    XCTAssertTrue(targets.hasNewline)
    XCTAssertEqual(targets.sourceFieldCount, 3)
    XCTAssertEqual(targets.fields, [0..<12, 12..<19, 19..<23])
    XCTAssertEqual(targets.field(0, withoutCommit: true), Array("north\nsouth".utf16))
    XCTAssertEqual(targets.field(1), Array("harbor ".utf16))
    XCTAssertEqual(targets.cursor(field: 1, position: 0, endGlyph: 23), 12)
  }

  func testExplicitFieldsRetainSurrogatesCombiningMarksAndTabUnits() {
    let fields = ["🙂\ne\u{301}\t ", "尾"]
    let targets = UnitInputTargets(fields.joined(), sourceFields: fields)
    XCTAssertEqual(targets.sourceFieldCount, 2)
    XCTAssertEqual(targets.fields, [0..<7, 7..<8])
    XCTAssertEqual(targets.field(0), Array(fields[0].utf16))
    XCTAssertEqual(targets.field(0, withoutCommit: true), Array("🙂\ne\u{301}\t".utf16))
    XCTAssertEqual(targets.cursor(field: 1, position: 0, endGlyph: 6), 5)
  }

  func testInvalidMetadataDoesNotReassignTargetUnits() {
    let text = "north\nsouth tail"
    for fields in [[], ["wrong"], ["", text], ["north\nsouth ", "TAIL"]] {
      let targets = UnitInputTargets(text, buildsASCIICatalog: true, sourceFields: fields)
      let legacy = UnitInputTargets(text, buildsASCIICatalog: true)
      XCTAssertEqual(targets.units, legacy.units)
      XCTAssertEqual(targets.fields, legacy.fields)
      XCTAssertEqual(targets.sourceFieldCount, legacy.sourceFieldCount)
    }
  }

  func testCanonicalEquivalenceCannotValidateDifferentProviderSpelling() {
    let targets = UnitInputTargets("e\u{301}\ntail", buildsASCIICatalog: true,
      sourceFields: ["é\ntail"])
    XCTAssertEqual(targets.sourceFieldCount, 2)
    XCTAssertEqual(targets.field(0), Array("e\u{301}\n".utf16))
  }

  func testExistingLineFeedAndNoSpaceCatalogsRemainUnchangedWithoutMetadata() {
    let legacy = UnitInputTargets("north\nsouth tail", buildsASCIICatalog: true)
    XCTAssertEqual(legacy.sourceFieldCount, 3)
    let noSpace = UnitInputTargets("ab\ncd", noSpaceWords: ["ab\n", "cd"])
    XCTAssertTrue(noSpace.noSpace)
    XCTAssertEqual(noSpace.sourceFieldCount, 2)
    XCTAssertEqual(noSpace.field(0), Array("ab\n".utf16))
  }

  func testExplicitFieldsOverrideStaleSeparatorCountButNotNoSpaceTargets() {
    let fields = ["north\nsouth ", "tail"]
    let targets = UnitInputTargets(fields.joined(), asciiSeparatorCount: 99, sourceFields: fields)
    XCTAssertEqual(targets.sourceFieldCount, 2)
    let noSpace = UnitInputTargets("ab\ncd", noSpaceWords: ["ab\n", "cd"],
      sourceFields: ["ab\ncd"])
    XCTAssertTrue(noSpace.noSpace)
    XCTAssertEqual(noSpace.sourceFieldCount, 2)
    XCTAssertEqual(noSpace.field(1), Array("cd".utf16))
  }

  func testTrailingLineFeedIsRetainedAndOnlyItsFinalCommitIsOmitted() {
    let targets = UnitInputTargets("north\nsouth\ntail",
      sourceFields: ["north\nsouth\n", "tail"])
    XCTAssertEqual(targets.sourceFieldCount, 2)
    XCTAssertEqual(targets.field(0), Array("north\nsouth\n".utf16))
    XCTAssertEqual(targets.field(0, withoutCommit: true), Array("north\nsouth".utf16))
  }
}
