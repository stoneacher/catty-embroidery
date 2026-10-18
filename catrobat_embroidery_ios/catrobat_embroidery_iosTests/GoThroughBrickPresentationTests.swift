@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// Brick backend slice 5, the app half: GoThrough reads as Catroid's sentence
/// (`go_through` "Go through", `go_through_target` "then to") and offers itself in
/// the palette after Arc.
@MainActor
@Suite("GoThrough in the app")
struct GoThroughBrickPresentationTests {
    private static let english = Locale(identifier: "en_US")

    @Test("a GoThrough reads as one sentence, through-point first")
    func sentence() {
        let brick = Brick.goThrough(throughX: .number(50), throughY: .variable("h"), x: .number(100), y: .number(-1))
        #expect(BrickRowPresentation.text(of: brick, locale: Self.english)
            == "Go through x: 50 y: \"h\" then to x: 100 y: \u{2212}1")
    }

    @Test("the palette offers GoThrough after Arc, with its description")
    func palette() {
        let row = PaletteRowPresentation(kind: .goThrough, locale: Self.english)
        #expect(row.text == "Go through x: 0 y: 0 then to x: 0 y: 0")
        #expect(row.description == "Moves the needle along a curve through one point to another.")
        #expect(PaletteGroup.motion.kinds.suffix(2) == [.arc, .goThrough])
    }

    @Test("the through-point slots have their own titles")
    func slotTitles() {
        #expect(ParameterEditorText.title(of: .throughX, locale: Self.english) == "Through x")
        #expect(ParameterEditorText.title(of: .throughY, locale: Self.english) == "Through y")
    }

    /// Each field through the parameter session, then undone: the through-point
    /// fields must not write the destination's `.x`/`.y` or each other.
    @Test("each field is one undoable edit of its own value", arguments: [
        ParameterSlot.throughX, .throughY, .x, .y
    ])
    func fieldEdit(_ slot: ParameterSlot) {
        let curve = Brick.goThrough(throughX: .number(1), throughY: .number(2), x: .number(3), y: .number(4))
        let program = Program(name: "fixture", scenes: [Scene(objects: [Object(scripts: [Script(bricks: [curve])])])])
        let editor = EditorViewModel(program: program, decimalSeparator: ".")
        editor.beginParameterEdit(at: 0)
        editor.setParameter(slot, to: .formula(.number(9)))
        let edited = editor.program.scenes[0].objects[0].scripts[0].bricks[0]
        #expect(edited.parameters.first { $0.slot == slot }?.value == .formula(.number(9)))
        #expect(edited.parameters.filter { $0.value == .formula(.number(9)) }.count == 1)
        editor.endParameterEdit()
        #expect(editor.undo())
        #expect(editor.program == program)
    }
}
