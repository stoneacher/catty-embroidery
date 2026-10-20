@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Variables slice 6, the app half: For values reads as Catroid writes it
/// (`brick_loop_for_values_from` "For values from", `brick_loop_to` "to", `brick_loop_in` "in"),
/// names its variable bare as Set variable does, and sits after Repeat until in the palette.
@MainActor
@Suite("For values in the app")
struct ForVariableFromToPresentationTests {
    private static let english = Locale(identifier: "en_US")

    private static func rows(_ bricks: [Brick]) -> [BrickRowPresentation] {
        BrickRowPresentation.rows(
            for: Program(name: "", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])]),
            locale: english
        )
    }

    @Test("a For and its end read as Catroid's sentence and name each other")
    func rows() {
        let rows = Self.rows([.forVariableFromTo(name: "i", from: .number(1), to: .number(10)), .stitch, .loopEnd])
        #expect(rows.map(\.text) == ["For values from 1 to 10 in i", "Stitch", "End of for values from 1 to 10 in i"])
        #expect(rows[1].accessibilityLabel == "Stitch, inside 1 loop")
    }

    @Test("an unchosen variable reads as the placeholder")
    func unnamed() {
        #expect(BrickRowPresentation.text(
            of: .forVariableFromTo(name: "", from: .number(1), to: .number(10)), locale: Self.english
        ) == "For values from 1 to 10 in (no variable)")
    }

    @Test("the palette offers For values after Repeat until, with its description")
    func palette() {
        let row = PaletteRowPresentation(kind: .forVariableFromTo, locale: Self.english)
        #expect(row.text == "For values from 1 to 10 in (no variable)")
        #expect(row.description == "Repeats the bricks inside it, counting a variable from one value to another.")
        let kinds = PaletteGroup.controlAndData.kinds
        #expect(kinds.firstIndex(of: .forVariableFromTo).map { kinds[kinds.index(before: $0)] } == .repeatUntil)
    }

    @Test("its slots are the variable, From and To")
    func slots() {
        #expect(Brick.forVariableFromTo(name: "i", from: .number(1), to: .number(10)).parameters.map(\.slot)
            == [.variableName, .from, .to])
        #expect(ParameterEditorText.title(of: .from, in: .forVariableFromTo, locale: Self.english) == "From")
        #expect(ParameterEditorText.title(of: .to, in: .forVariableFromTo, locale: Self.english) == "To")
    }
}
