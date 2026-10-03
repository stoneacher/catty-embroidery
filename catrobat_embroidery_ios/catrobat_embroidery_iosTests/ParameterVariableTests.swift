@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-410's test-first items 7, 7b and 7c, the app half: the variable menu, declaring on use,
/// and switching a slot between a number and a variable. Split from `ParameterEditingTests`
/// for length; the fixture is the same.
@MainActor
@Suite("Parameter editing — variables")
struct ParameterVariableTests {
    private static let bricks: [Brick] = [
        .moveNSteps(.number(10)),
        .zigZagStitch(length: .number(2), width: .number(10)),
        .setThreadColor(hex: "#ff0000"),
        .stitch
    ]

    private static func program(_ bricks: [Brick], variables: [Variable] = []) -> Program {
        Program(name: "fixture", scenes: [Scene(objects: [
            Object(variables: variables, scripts: [Script(bricks: bricks)])
        ])])
    }

    private static let seed = program(bricks)

    private static func replacing(_ index: Int, with brick: Brick, in bricks: [Brick] = bricks) -> Program {
        var bricks = bricks
        bricks[index] = brick
        return program(bricks)
    }

    private final class Announcements {
        var fired = 0
    }

    private static func editor(
        _ program: Program = seed,
        decimalSeparator: String = "."
    ) -> (EditorViewModel, Announcements) {
        let editor = EditorViewModel(program: program, decimalSeparator: decimalSeparator)
        let announcements = Announcements()
        editor.onProgramChanged = { announcements.fired += 1 }
        return (editor, announcements)
    }

    // MARK: 7 — the variable menu

    @Test("item 7: the menu lists the edited object's variables, then the project's")
    func menu() {
        var program = Self.program(Self.bricks, variables: [Variable(name: "Side"), Variable(name: "Count")])
        program.variables = [Variable(name: "Speed"), Variable(name: "Side")]
        let (editor, _) = Self.editor(program)
        editor.beginParameterEdit(at: 0)

        #expect(editor.variableMenu.names == ["Side", "Count", "Speed"])
    }

    // MARK: 7b — the blank-program workflow

    @Test("item 7b: from the blank program, a variable is authored and referenced")
    func blankProgramWorkflow() {
        let (editor, _) = Self.editor(.blank)
        editor.insert(.setVariable)
        editor.beginParameterEdit(at: 0)
        #expect(editor.createVariable(named: " Side ", for: .variableName) == .applied(editor.program))
        editor.endParameterEdit()

        editor.insert(.moveNSteps)
        editor.beginParameterEdit(at: 1)
        #expect(editor.variableMenu.names == ["Side"])
        editor.chooseVariable(named: "Side", for: .steps)
        editor.endParameterEdit()

        var expected = Program.blank
        expected.scenes[0].objects[0].variables = [Variable(name: "Side")]
        expected.scenes[0].objects[0].scripts[0].bricks = [
            .setVariable(name: "Side", to: .number(BrickDefaults.setVariableValue)),
            .moveNSteps(.variable("Side"))
        ]
        #expect(editor.program == expected)
        // Insert, name (declaration + rename as one), insert, reference.
        #expect(editor.undoStack.undoDepth == 4)
    }

    @Test("an invalid name is refused with its rule, and declares nothing")
    func invalidName() {
        let (editor, _) = Self.editor(.blank)
        editor.insert(.setVariable)
        let before = editor.program
        editor.beginParameterEdit(at: 0)

        #expect(editor.createVariable(named: "(no variable)", for: .variableName)
            == .rejected(.invalidVariableName(.leadingOpenPunctuation)))
        #expect(editor.program == before)
    }

    @Test("every name problem has a readable reason", arguments: [
        VariableNameProblem.empty, .surroundingWhitespace, .controlCharacter, .quotationMark,
        .leadingOpenPunctuation
    ])
    func nameProblemText(problem: VariableNameProblem) {
        let text = ParameterEditorText.message(for: problem)
        #expect(!text.isEmpty)
        #expect(!text.contains("parameter."), "unresolved key: \(text)")
    }

    // MARK: 7c — number to variable and back

    @Test("item 7c: switching to a variable and back to a number")
    func switchAndBack() {
        let program = Self.program(Self.bricks, variables: [Variable(name: "Side")])
        let (editor, _) = Self.editor(program)
        editor.beginParameterEdit(at: 0)

        editor.chooseVariable(named: "Side", for: .steps)
        #expect(editor.program == Self.program(
            [.moveNSteps(.variable("Side"))] + Self.bricks.dropFirst(), variables: [Variable(name: "Side")]
        ))

        editor.switchToNumber(.steps)
        // Back to the number the slot held when the editor opened.
        #expect(editor.program == program)
    }

    /// A slot that opened as a variable has no number of its own, so switching it to a number
    /// seeds the kind's template default.
    @Test("item 7c: a slot that opened as a variable switches to the template's default")
    func switchFromOpenedVariable() {
        let program = Self.program([.moveNSteps(.variable("Side"))], variables: [Variable(name: "Side")])
        let (editor, _) = Self.editor(program)
        editor.beginParameterEdit(at: 0)

        editor.switchToNumber(.steps)

        #expect(editor.program == Self.program(
            [.moveNSteps(.number(BrickDefaults.moveSteps))], variables: [Variable(name: "Side")]
        ))
    }
}
