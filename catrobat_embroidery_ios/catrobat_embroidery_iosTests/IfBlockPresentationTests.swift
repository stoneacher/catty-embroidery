@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Variables slice 2, the app half: If and If/Else read as Catroid writes them (`brick_if_begin`
/// "If", `brick_if_begin_second_part` "is true then", `brick_if_else` "Else", `brick_if_end`
/// "End if"), sit in the palette, and offer the moves the package computes, each spoken with
/// the name of the block it moves out of or into.
@MainActor
@Suite("If blocks in the app")
struct IfBlockPresentationTests {
    private static let english = Locale(identifier: "en_US")
    private static let condition = Formula.binary(.smallerThan, .number(1), .number(2))

    private static func rows(_ bricks: [Brick]) -> [BrickRowPresentation] {
        BrickRowPresentation.rows(
            for: Program(name: "", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            locale: english
        )
    }

    private static let ifElse: [Brick] = [.ifElse(condition: condition), .stitch, .elseBranch, .sewUp, .ifEnd]

    // MARK: - Rows

    @Test("an If/Else reads as its four rows, indented around the else")
    func ifElseRows() {
        let rows = Self.rows(Self.ifElse)
        #expect(rows.map(\.text) == ["If 1 < 2 is true then", "Stitch", "Else", "Sew up", "End if"])
        #expect(rows.map(\.depth) == [0, 1, 0, 1, 0])
    }

    @Test("an If/Then reads like the If of an If/Else")
    func ifThenRow() {
        #expect(BrickRowPresentation.text(of: .ifThen(condition: Self.condition), locale: Self.english)
            == "If 1 < 2 is true then")
    }

    /// "inside 1 loop" for a brick inside an If would be false; the label names both kinds.
    @Test("a nested label names the loops and Ifs a row sits inside")
    func nestedLabel() {
        let inIf = Self.rows(Self.ifElse)
        #expect(inIf[1].accessibilityLabel == "Stitch, inside 1 If")
        #expect(inIf[2].accessibilityLabel == "Else", "the else sits at the top level")
        let mixed = Self.rows([.forever, .ifThen(condition: Self.condition), .ifThen(condition: Self.condition),
                               .stitch, .ifEnd, .ifEnd, .loopEnd])
        #expect(mixed[3].accessibilityLabel == "Stitch, inside 1 loop and 2 Ifs")
        #expect(mixed[2].accessibilityLabel == "If 1 < 2 is true then, inside 1 loop and 1 If")
        let loops = Self.rows([.forever, .stitch, .loopEnd])
        #expect(loops[1].accessibilityLabel == "Stitch, inside 1 loop", "loops alone read as before")
    }

    // MARK: - What the rows can do

    @Test("the else and end rows cannot be dragged and offer Delete alone", arguments: [2, 4])
    func markerRows(_ index: Int) {
        let row = Self.rows(Self.ifElse)[index]
        #expect(row.isMoveDisabled)
        #expect(row.moveActions.isEmpty)
        #expect(row.delete != nil)
    }

    @Test("each If move is offered where the package offers it, under its own name")
    func namedMoves() {
        let rows = Self.rows(Self.ifElse)
        #expect(rows[1].moveActions.map(\.title) == ["Move Above If", "Move Below Else"])
        // The rotor order is the existing one — up, down, out, into — with the else pair last.
        #expect(rows[3].moveActions.map(\.title) == ["Move Below If", "Move Above Else"])
        #expect(rows[1].moveBelowElse == .move(from: BrickAddress(brickIndex: 1), to: 2))
        #expect(rows[3].moveAboveElse == .move(from: BrickAddress(brickIndex: 3), to: 2))
    }

    @Test("a move beside or out of a loop keeps its loop name")
    func loopNamesStay() {
        let rows = Self.rows([.stitch, .forever, .sewUp, .loopEnd, .ifThen(condition: Self.condition), .ifEnd])
        #expect(rows[0].moveActions.map(\.title) == ["Move Down", "Move Into Loop Below"])
        #expect(rows[2].moveActions.map(\.title) == ["Move Above Loop", "Move Below Loop"])
        let afterIf = Self.rows([.ifThen(condition: Self.condition), .ifEnd, .stitch])
        #expect(afterIf[2].moveActions.map(\.title) == ["Move Up", "Move Into If Above"])
    }

    // MARK: - Palette and editor

    @Test("the palette offers If/Else then If/Then, each with its description")
    func palette() {
        let ifElse = PaletteRowPresentation(kind: .ifElse, locale: Self.english)
        let ifThen = PaletteRowPresentation(kind: .ifThen, locale: Self.english)
        #expect(ifElse.text == "If 1 < 2 is true then")
        #expect(ifElse.description
            == "Runs the bricks after it if the condition is true, and the bricks after Else if not.")
        #expect(ifThen.description == "Runs the bricks inside it only if the condition is true.")
    }

    @Test("the condition slot has a title, and the condition is locked as a condition")
    func conditionSlot() {
        #expect(ParameterEditorText.title(of: .condition, in: .ifThen, locale: Self.english) == "Condition")
        #expect(ParameterEditorKind(.formula(Self.condition)) == .readOnlyFormula(Self.condition, reason: .logic))
    }
}
