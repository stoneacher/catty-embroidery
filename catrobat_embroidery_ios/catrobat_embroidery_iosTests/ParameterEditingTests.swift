@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Samples
import Testing

/// US-410's test-first items 2–10, the app half: the parameter editor's session on the editor
/// view model. Whole-`Program` assertions (ADR-006 pattern 3) throughout.
///
/// The session **is** the presentation (ADR-036, ADR-039): the editor shows while
/// `parameterSession` is non-`nil`, and every change inside it applies live under one coalescing
/// key — so twenty stepper taps are one undo entry with no timer anywhere.
///
/// ```
/// 0  moveNSteps(10)
/// 1  zigZagStitch(2, 10)
/// 2  setThreadColor("#ff0000")
/// 3  stitch
/// ```
@MainActor
@Suite("Parameter editing")
struct ParameterEditingTests {
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

    // MARK: Opening

    @Test("opening selects the brick and opens one session on it")
    func opening() throws {
        let (editor, _) = Self.editor()

        #expect(editor.beginParameterEdit(at: 1))

        let session = try #require(editor.parameterSession)
        #expect(session.address == BrickAddress(brickIndex: 1))
        #expect(editor.undoStack.openSession == session.key)
        #expect(editor.selectedBrickIndex == 1)
        #expect(editor.editedBrick == .zigZagStitch(length: .number(2), width: .number(10)))
    }

    /// A stitch has nothing to edit, and an index past the end has no brick: neither opens an
    /// empty editor, and neither leaves a session behind.
    @Test("a brick without parameters, or no brick, opens nothing", arguments: [3, 4, -1])
    func nothingToEdit(index: Int) {
        let (editor, _) = Self.editor()
        #expect(!editor.beginParameterEdit(at: index))
        #expect(editor.parameterSession == nil)
        #expect(editor.undoStack.openSession == nil)
    }

    @Test("whether the selected brick can be edited follows the selection")
    func canEditSelection() {
        let (editor, _) = Self.editor()
        #expect(!editor.canEditSelectedBrick)
        editor.selectedBrickIndex = 0
        #expect(editor.canEditSelectedBrick)
        editor.selectedBrickIndex = 3
        #expect(!editor.canEditSelectedBrick)
    }

    // MARK: 2 — committing a number

    @Test("item 2: committing a number is one replaceBrick with the whole brick")
    func committingANumber() {
        let (editor, announcements) = Self.editor()
        editor.beginParameterEdit(at: 1)

        #expect(editor.enterNumber("7", for: .width) == nil)

        #expect(editor.program == Self.replacing(1, with: .zigZagStitch(length: .number(2), width: .number(7))))
        #expect(editor.undoStack.undoDepth == 1)
        #expect(announcements.fired == 1)
        // A parameter edit moves no row, so the selection survives it.
        #expect(editor.selectedBrickIndex == 1)
    }

    @Test("the locale's decimal separator is accepted")
    func decimalComma() {
        let (editor, _) = Self.editor(decimalSeparator: ",")
        editor.beginParameterEdit(at: 0)
        #expect(editor.enterNumber("2,5", for: .steps) == nil)
        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(2.5))))
    }

    // MARK: 3 — a rejected literal is surfaced, not committed

    @Test("item 3: 1e400 and a 310-digit entry are reported and change nothing",
          arguments: ["1e400", String(repeating: "9", count: 310)])
    func nonFiniteIsReported(text: String) {
        let (editor, announcements) = Self.editor()
        editor.beginParameterEdit(at: 0)

        #expect(editor.enterNumber(text, for: .steps) == .nonFinite)

        #expect(editor.program == Self.seed)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    /// Found on the simulator: live-apply commits every keystroke that parses, so typing
    /// `1e400` commits `1e40` on the way. A rejected entry must not leave that prefix behind —
    /// the slot returns to what it held when typing began, and the session nets to nothing.
    @Test("item 3: a rejected entry returns the slot to its value from before the typing began")
    func rejectionRestoresTheAnchor() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.beginNumberEntry(for: .steps)

        for prefix in ["1", "1e", "1e4", "1e40", "1e400"] {
            _ = editor.enterNumber(prefix, for: .steps)
        }

        #expect(editor.program == Self.seed)
        editor.endParameterEdit()
        #expect(editor.undoStack.undoDepth == 0)
    }

    /// The anchor is per typing run: a value committed by an earlier run (or the stepper) is
    /// what a later rejection returns to, not the value the session opened with.
    @Test("item 3: the anchor follows the last typing run, not the session's opening")
    func anchorIsPerRun() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.beginNumberEntry(for: .steps)
        _ = editor.enterNumber("25", for: .steps)
        editor.stepNumber(.steps, by: 1)

        editor.beginNumberEntry(for: .steps)
        _ = editor.enterNumber("2", for: .steps)
        _ = editor.enterNumber("2e999", for: .steps)

        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(26))))
    }

    @Test("every literal error has a readable reason", arguments: [
        FormulaLiteralError.empty, .malformed, .nonFinite
    ])
    func literalErrorText(error: FormulaLiteralError) {
        let text = ParameterEditorText.message(for: error)
        #expect(!text.isEmpty)
        #expect(!text.contains("parameter."), "unresolved key: \(text)")
    }

    // MARK: 4, 5 — one entry per session

    @Test("item 4: twenty stepper taps in one session are one undo entry")
    func twentyStepsOneEntry() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)

        for _ in 0 ..< 20 {
            editor.stepNumber(.steps, by: 1)
        }
        editor.endParameterEdit()

        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(30))))
        #expect(editor.undoStack.undoDepth == 1)
        editor.undo()
        // The value that was there when the editor opened.
        #expect(editor.program == Self.seed)
    }

    @Test("item 5: two sessions are two entries")
    func twoSessionsTwoEntries() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.stepNumber(.steps, by: 1)
        editor.endParameterEdit()
        editor.beginParameterEdit(at: 0)
        editor.stepNumber(.steps, by: 1)
        editor.endParameterEdit()

        #expect(editor.undoStack.undoDepth == 2)
        editor.undo()
        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(11))))
    }

    @Test("endParameterEdit is idempotent")
    func endIsIdempotent() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.stepNumber(.steps, by: 1)
        editor.endParameterEdit()
        let after = editor.undoStack
        editor.endParameterEdit()
        #expect(editor.undoStack == after)
        #expect(editor.parameterSession == nil)
    }

    // MARK: 6 — a session torn down without endParameterEdit

    /// ADR-023's container swap can dismiss the sheet without its `onDisappear` firing, and a
    /// late write from the torn-down sheet — a text field's submit, say — must not land. The
    /// teardown here is `load`, the view model's own reset path.
    @Test("item 6: after a reset, a late write from the old session changes nothing")
    func lateWriteAfterReset() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.stepNumber(.steps, by: 1)

        editor.load(Self.seed)

        #expect(editor.parameterSession == nil)
        #expect(editor.undoStack.openSession == nil)
        #expect(editor.enterNumber("99", for: .steps) == nil)
        editor.stepNumber(.steps, by: 1)
        #expect(editor.program == Self.seed)
        #expect(editor.undoStack.undoDepth == 0)
    }

    /// Undo and redo clear the selection because the rows may have moved (US-408), and for the
    /// same reason they end the session: its address may now name a different brick.
    @Test("undo and redo end the session")
    func historyEndsTheSession() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 0)
        editor.stepNumber(.steps, by: 1)
        editor.undo()
        #expect(editor.parameterSession == nil)

        editor.beginParameterEdit(at: 0)
        editor.redo()
        #expect(editor.parameterSession == nil)
        editor.stepNumber(.steps, by: 1)
        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(11))))
    }

    // MARK: 8 — the thread palette

    @Test("item 8: a swatch writes its exact hex string")
    func swatch() {
        let (editor, _) = Self.editor()
        editor.beginParameterEdit(at: 2)
        editor.setParameter(.hex, to: .threadColor(hex: ThreadSwatch.royalBlue.hex))
        #expect(editor.program == Self.replacing(2, with: .setThreadColor(hex: "#1d4ed8")))
    }

    @Test("every swatch has a readable name", arguments: ThreadSwatch.allCases)
    func swatchNames(swatch: ThreadSwatch) {
        let name = ParameterEditorText.name(of: swatch)
        #expect(!name.isEmpty)
        #expect(!name.contains("thread."), "unresolved key: \(name)")
    }

    // MARK: 9 — read-only formulas

    /// Octagon Rosette's `turnRight(360 ÷ "Inner Loop")`: open it, close it, nothing changed —
    /// not even an undo entry for a value written back unchanged.
    @Test("item 9: opening and closing a read-only formula leaves the program untouched")
    func readOnlyRoundTrip() throws {
        let rosette = SampleLibrary[.octagonRosette].program
        let bricks = rosette.scenes[0].objects[0].scripts[0].bricks
        let index = try #require(bricks.firstIndex {
            if case .turnRight(.binary) = $0 {
                true
            } else {
                false
            }
        })
        let (editor, announcements) = Self.editor(rosette)

        #expect(editor.beginParameterEdit(at: index))
        let parameter = try #require(editor.editedBrick?.parameters.first)
        guard case .readOnlyFormula = ParameterEditorKind(parameter.value) else {
            Issue.record("expected a read-only formula, got \(parameter.value)")
            return
        }
        editor.endParameterEdit()

        #expect(editor.program == rosette)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    @Test("item 9: each read-only reason is a readable sentence", arguments: [
        ReadOnlyFormulaReason.binary, .unaryMinus
    ])
    func readOnlyReason(reason: ReadOnlyFormulaReason) {
        let text = ParameterEditorText.message(for: reason)
        #expect(!text.isEmpty)
        #expect(!text.contains("parameter."), "unresolved key: \(text)")
    }

    // MARK: 10 — never a different kind

    /// A value of the wrong shape for its slot is refused at the view model's boundary — no
    /// `replaceBrick` reaches the funnel, so ADR-035's guard is never what stops it.
    @Test("item 10: a mismatched value is refused before the funnel")
    func mismatchRefused() {
        let (editor, announcements) = Self.editor()
        editor.beginParameterEdit(at: 0)

        #expect(editor.setParameter(.steps, to: .threadColor(hex: "#000000")) == nil)
        #expect(editor.setParameter(.hex, to: .threadColor(hex: "#000000")) == nil)

        #expect(editor.program == Self.seed)
        #expect(announcements.fired == 0)
    }
}
