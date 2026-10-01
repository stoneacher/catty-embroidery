@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Samples
import StagePreview
import Testing

/// US-409's test-first items 2, 3, 4, 7 and 8, the app half: a palette tap through the editor's
/// one door, the selection it inserts after, and what the list scrolls to.
///
/// Whole-`Program` assertions (ADR-006 pattern 3) against a fixture that is not `.blank`, so a
/// wrong blank program cannot also make this door look broken:
///
/// ```
/// 0  stitch
/// 1  repeatLoop(2)  ─┐
/// 2    sewUp         │
/// 3  loopEnd        ─┘
/// 4  stopRunningStitch
/// ```
@MainActor
@Suite("Palette insert")
struct PaletteInsertTests {
    private static let bricks: [Brick] = [
        .stitch, .repeatLoop(times: .number(2)), .sewUp, .loopEnd, .stopRunningStitch
    ]

    private static func program(_ bricks: [Brick]) -> Program {
        Program(name: "fixture", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
    }

    private static let seed = program(bricks)

    private static func inserted(_ kind: BrickKind, at index: Int) -> Program {
        var bricks = bricks
        bricks.insert(contentsOf: kind.template(), at: index)
        return program(bricks)
    }

    private final class Announcements {
        var fired = 0
    }

    private static func editor(_ program: Program = seed) -> (EditorViewModel, Announcements) {
        let editor = EditorViewModel(program: program)
        let announcements = Announcements()
        editor.onProgramChanged = { announcements.fired += 1 }
        return (editor, announcements)
    }

    private static func window(stored: Program? = nil) -> AppModel {
        AppModel(
            autosave: ProgramAutosave(store: InMemoryProgramStore(stored: stored)),
            runner: RunViewModel(driver: InterpreterDriver(pacing: ImmediateRunPacing())),
            exporter: ExportViewModel(writer: RecordingDSTFileWriter())
        )
    }

    // MARK: 2 — one insert, through the one door

    @Test("an insert is one applied edit: the whole program, one undo entry, one announcement")
    func oneInsertThroughTheDoor() {
        let (editor, announcements) = Self.editor()

        let index = editor.insert(.wait)

        #expect(index == 5)
        #expect(editor.program == Self.inserted(.wait, at: 5))
        #expect(editor.undoStack.undoDepth == 1)
        #expect(announcements.fired == 1)
        // Undo returns exactly the program before — the insert is one entry, not two.
        editor.undo()
        #expect(editor.program == Self.seed)
    }

    // MARK: 3 — the insertion point follows the selection

    @Test("with nothing selected the brick is appended")
    func appendsWithNothingSelected() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = nil

        #expect(editor.insert(.wait) == 5)
        #expect(editor.program == Self.inserted(.wait, at: 5))
    }

    @Test("with a leaf selected the brick lands directly after it")
    func insertsAfterTheSelectedLeaf() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 0

        #expect(editor.insert(.wait) == 1)
        #expect(editor.program == Self.inserted(.wait, at: 1))
    }

    // MARK: 4 — a loop opener selected: inside the loop

    @Test("with a loop opener selected the brick lands inside the loop, before its end")
    func insertsInsideTheSelectedLoop() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 1

        #expect(editor.insert(.wait) == 2)
        #expect(editor.program == Self.program([
            .stitch, .repeatLoop(times: .number(2)), .wait(seconds: .number(1)), .sewUp, .loopEnd, .stopRunningStitch
        ]))
    }

    @Test("with a loop's end selected the brick lands after the loop")
    func insertsAfterTheSelectedLoopEnd() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 3

        #expect(editor.insert(.wait) == 4)
        #expect(editor.program == Self.inserted(.wait, at: 4))
    }

    // MARK: 8 — the inserted brick becomes the selection, and the scroll target

    @Test("the inserted brick is selected, so the next tap builds after it")
    func insertedBrickIsSelected() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 0

        editor.insert(.wait)
        #expect(editor.selectedBrickIndex == 1)
        editor.insert(.sewUp)
        #expect(editor.selectedBrickIndex == 2)
        #expect(editor.program == Self.program([
            .stitch, .wait(seconds: .number(1)), .sewUp, .repeatLoop(times: .number(2)), .sewUp, .loopEnd,
            .stopRunningStitch
        ]))
    }

    /// The opener is selected after a loop insert, so the next tap fills the new loop's body —
    /// which is what makes a loop buildable by tap-to-add alone.
    @Test("inserting a loop selects its opener, and the next tap lands inside it")
    func insertedLoopIsFillable() throws {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 0

        #expect(editor.insert(.forever) == 1)
        #expect(editor.selectedBrickIndex == 1)
        #expect(editor.insert(.stitch) == 2)
        let script = try #require(editor.program.scenes.first?.objects.first?.scripts.first)
        #expect(Array(script.bricks.prefix(4)) == [.stitch, .forever, .stitch, .loopEnd])
        #expect(script.indentDepths[2] == 1)
        #expect(throws: Never.self) { try script.validate() }
    }

    @Test("a palette tap applies, dismisses the palette and asks the list to scroll to the brick")
    func paletteTapDismissesAndScrolls() {
        let model = Self.window()
        model.editor.load(Self.seed)
        model.editor.selectedBrickIndex = 1
        model.isPalettePresented = true

        model.addFromPalette(.repeatLoop)

        #expect(model.editor.program == Self.inserted(.repeatLoop, at: 2))
        #expect(model.isPalettePresented == false)
        #expect(model.paletteInsertion?.index == 2)
    }

    /// The same index twice must still scroll twice — the list scrolls on a change of the value.
    @Test("two inserts at the same index are two distinct scroll requests")
    func repeatedInsertsAreDistinctRequests() throws {
        let model = Self.window()
        model.editor.load(Self.program([]))

        model.addFromPalette(.stitch)
        let first = try #require(model.paletteInsertion)
        model.editor.undo()
        model.addFromPalette(.stitch)
        let second = try #require(model.paletteInsertion)

        #expect(first.index == 0)
        #expect(second.index == 0)
        #expect(first != second)
    }

    // MARK: 7 — a rejected insert changes nothing

    @Test("a rejected insert changes nothing: program, history, selection, announcement")
    func rejectedInsertChangesNothing() {
        let (editor, announcements) = Self.editor()
        editor.selectedBrickIndex = 2

        #expect(editor.insert(.loopEnd) == nil)

        #expect(editor.program == Self.seed)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(editor.selectedBrickIndex == 2)
        #expect(announcements.fired == 0)
    }

    @Test("a program with no script refuses the insert and changes nothing")
    func noScriptRefuses() {
        let empty = Program(name: "no script", scenes: [])
        let (editor, announcements) = Self.editor(empty)

        #expect(editor.insert(.stitch) == nil)
        #expect(editor.program == empty)
        #expect(editor.undoStack.undoDepth == 0)
        #expect(announcements.fired == 0)
    }

    @Test("a refused palette tap leaves the palette open and asks for no scroll")
    func refusedPaletteTap() {
        let model = Self.window()
        model.editor.load(Program(name: "no script", scenes: []))
        model.isPalettePresented = true

        model.addFromPalette(.stitch)

        #expect(model.isPalettePresented)
        #expect(model.paletteInsertion == nil)
    }

    // MARK: The selection goes stale with the program (ADR-034)

    /// Rows are identified by position, so after a change that moves rows the selected index may
    /// hold a different brick. Clearing is the only answer that cannot point at the wrong one.
    @Test("a change that moves rows clears the selection")
    func rowChangesClearTheSelection() {
        let changes: [(String, (EditorViewModel) -> Void)] = [
            ("apply insert", { $0.apply(.insert(.stitch, at: BrickAddress(brickIndex: 0))) }),
            ("apply delete", { $0.apply(.delete(at: BrickAddress(brickIndex: 4))) }),
            ("apply move", { $0.apply(.move(from: BrickAddress(brickIndex: 4), to: 0)) }),
            ("list move", { $0.moveRows(fromOffsets: [0], toOffset: 5) }),
            ("list delete", { $0.deleteRows(atOffsets: [0]) }),
            ("load", { $0.load(Self.seed) })
        ]
        for (name, change) in changes {
            let (editor, _) = Self.editor()
            editor.selectedBrickIndex = 2
            change(editor)
            #expect(editor.selectedBrickIndex == nil, "\(name)")
        }
    }

    @Test("undo and redo clear the selection")
    func historyClearsTheSelection() {
        let (editor, _) = Self.editor()
        editor.apply(.delete(at: BrickAddress(brickIndex: 4)))
        editor.selectedBrickIndex = 2
        editor.undo()
        #expect(editor.selectedBrickIndex == nil)

        editor.selectedBrickIndex = 2
        editor.redo()
        #expect(editor.selectedBrickIndex == nil)
    }

    /// No row moved, so nothing went stale — and US-410 edits the selected brick's parameters
    /// without losing the selection it was opened from.
    @Test("a rejected edit, a rename, a parameter edit and an empty undo keep the selection")
    func nonRowChangesKeepTheSelection() {
        let (editor, _) = Self.editor()
        editor.selectedBrickIndex = 2

        editor.apply(.move(from: BrickAddress(brickIndex: 3), to: 0))
        editor.apply(.renameProgram("renamed"))
        editor.apply(.replaceBrick(at: BrickAddress(brickIndex: 1), with: .repeatLoop(times: .number(7))))
        #expect(editor.undoStack.undoDepth == 2, "the premise: rename and replace both applied")
        let (fresh, _) = Self.editor()
        fresh.selectedBrickIndex = 2
        fresh.undo()

        #expect(editor.selectedBrickIndex == 2)
        #expect(fresh.selectedBrickIndex == 2)
    }

    // MARK: The palette's presentation is window state (ADR-023)

    @Test("selecting a design closes the palette")
    func selectingClosesThePalette() {
        let model = Self.window()
        model.isPalettePresented = true

        model.select(SampleLibrary[.squareCoil])

        #expect(model.isPalettePresented == false)
    }

    /// On compact the stage link stays tappable under a sheet that allows background
    /// interaction; the palette must not follow the user onto the stage.
    @Test("pushing the stage closes the palette")
    func pushingTheStageClosesThePalette() {
        let model = Self.window()
        model.isPalettePresented = true

        model.path.append(.stage)

        #expect(model.isPalettePresented == false)
    }

    @Test("Back to the script leaves the palette's state alone")
    func poppingKeepsItClosed() {
        let model = Self.window()
        model.path = [.script]
        model.isPalettePresented = true

        model.path = [.script]

        #expect(model.isPalettePresented)
    }

    /// `swift-code-reviewer`'s repro: the stage was pushed on compact, the window went regular
    /// (the split ignores `path`), the palette was opened from the script column, and the window
    /// went compact again. The stack rebuilds with the stage on top, and the button that
    /// presented the palette is off-screen, so a flag still `true` would present over the stage
    /// or turn the next Add tap into a no-op.
    @Test("becoming compact with the stage on top closes the palette")
    func compactWithTheStageOnTopClosesThePalette() {
        let model = Self.window()
        model.path = [.script, .stage]
        model.isPalettePresented = true // opened from the regular layout's script column

        model.layoutChanged(isCompact: true)

        #expect(model.isPalettePresented == false)
    }

    @Test("a layout change that leaves the script on top keeps the palette")
    func layoutChangeKeepsThePaletteOverTheScript() {
        let compact = Self.window()
        compact.path = [.script]
        compact.isPalettePresented = true
        compact.layoutChanged(isCompact: true)
        #expect(compact.isPalettePresented)

        // Regular ignores `path`: the script column is always on screen.
        let regular = Self.window()
        regular.path = [.script, .stage]
        regular.isPalettePresented = true
        regular.layoutChanged(isCompact: false)
        #expect(regular.isPalettePresented)
    }

    @Test("restoring a saved program closes the palette")
    func restoringClosesThePalette() {
        let model = Self.window(stored: Self.seed)
        model.isPalettePresented = true

        model.restoreSavedProgram()

        #expect(model.editor.program == Self.seed)
        #expect(model.isPalettePresented == false)
    }
}
