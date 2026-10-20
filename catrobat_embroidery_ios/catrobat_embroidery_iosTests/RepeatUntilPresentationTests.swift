@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Variables slice 4, the app half: Repeat until reads as Catroid writes it (`brick_repeat_until`
/// "Repeat until", `brick_wait_until_second_part` "is true"), its end names the loop it closes,
/// and it sits after Repeat in the palette.
@MainActor
@Suite("Repeat until in the app")
struct RepeatUntilPresentationTests {
    private static let english = Locale(identifier: "en_US")
    private static let condition = Formula.binary(.smallerThan, .number(1), .number(2))

    private static func rows(_ bricks: [Brick]) -> [BrickRowPresentation] {
        BrickRowPresentation.rows(
            for: Program(name: "", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            locale: english
        )
    }

    @Test("a Repeat until and its end read as Catroid's sentence and name each other")
    func rows() {
        let rows = Self.rows([.repeatUntil(condition: Self.condition), .stitch, .loopEnd])
        #expect(rows.map(\.text) == ["Repeat until 1 < 2 is true", "Stitch", "End of repeat until 1 < 2 is true"])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows[1].accessibilityLabel == "Stitch, inside 1 loop")
        #expect(rows[2].openerIndex == 0)
    }

    @Test("the palette offers Repeat until after Repeat, with its description")
    func palette() {
        let row = PaletteRowPresentation(kind: .repeatUntil, locale: Self.english)
        #expect(row.text == "Repeat until 1 < 2 is true")
        #expect(row.description == "Repeats the bricks inside it until the condition is true.")
        let kinds = PaletteGroup.controlAndData.kinds
        #expect(kinds.firstIndex(of: .repeatUntil).map { kinds[kinds.index(before: $0)] } == .repeatLoop)
    }

    @Test("its condition has the condition slot and is locked as a condition")
    func conditionSlot() {
        #expect(Brick.repeatUntil(condition: Self.condition).parameters.map(\.slot) == [.condition])
        #expect(ParameterEditorText.title(of: .condition, in: .repeatUntil, locale: Self.english) == "Condition")
    }

    /// A move out of a Repeat until is a move out of a loop.
    @Test("moves out of a Repeat until are named for a loop")
    func moveNames() {
        let rows = Self.rows([.repeatUntil(condition: Self.condition), .stitch, .loopEnd])
        #expect(rows[1].moveActions.map(\.title) == ["Move Above Loop", "Move Below Loop"])
    }
}
