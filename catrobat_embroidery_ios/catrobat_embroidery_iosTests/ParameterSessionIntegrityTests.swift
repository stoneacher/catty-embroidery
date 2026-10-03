@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-410, from the `swift-code-reviewer` round: what the session must not do once the program
/// under it moves, and the mutants the first suites let survive (ADR-032 invariant 2).
///
/// ```
/// 0  moveNSteps(17)          — not BrickDefaults.moveSteps (10), so "the number it opened with"
/// 1  zigZagStitch(2, 10)       and "the template default" are different answers
/// 2  stitch
/// ```
@MainActor
@Suite("Parameter session integrity")
struct ParameterSessionIntegrityTests {
    private static let bricks: [Brick] = [
        .moveNSteps(.number(17)),
        .zigZagStitch(length: .number(2), width: .number(10)),
        .stitch
    ]

    private static func program(_ bricks: [Brick] = bricks, variables: [Variable] = []) -> Program {
        Program(name: "fixture", scenes: [Scene(objects: [
            Object(variables: variables, scripts: [Script(bricks: bricks)])
        ])])
    }

    private static func replacing(_ index: Int, with brick: Brick) -> Program {
        var bricks = bricks
        bricks[index] = brick
        return program(bricks)
    }

    /// Finding 3. Undo and redo end the session because its address may now name a different
    /// brick; an insert, delete or move does the same thing to the address and must too. On an
    /// iPad the popover does not stop a VoiceOver user reaching a row's Delete action.
    @Test("an edit that moves rows ends the session", arguments: [
        EditAction.delete(at: BrickAddress(brickIndex: 0)),
        .insert(.stitch, at: BrickAddress(brickIndex: 0)),
        .move(from: BrickAddress(brickIndex: 2), to: 0)
    ])
    func rowMovingEditEndsTheSession(action: EditAction) {
        let editor = EditorViewModel(program: Self.program())
        editor.beginParameterEdit(at: 1)

        editor.apply(action)

        #expect(editor.parameterSession == nil)
        #expect(editor.undoStack.openSession == nil)
    }

    /// The other half: a parameter edit or a declaration moves no row, so the session and the
    /// selection both survive it (review mutant A19).
    @Test("a declaration keeps the session and the selection")
    func declarationKeepsTheSession() {
        let editor = EditorViewModel(program: Self.program())
        editor.beginParameterEdit(at: 0)

        editor.createVariable(named: "Side", for: .steps)

        #expect(editor.parameterSession != nil)
        #expect(editor.selectedBrickIndex == 0)
    }

    /// Review mutant A15: with an opening value equal to the template default, "restore what it
    /// opened with" and "seed the default" cannot be told apart.
    @Test("switching back restores the opening number, not the template default")
    func switchBackRestoresTheOpeningNumber() {
        let editor = EditorViewModel(program: Self.program(variables: [Variable(name: "Side")]))
        editor.beginParameterEdit(at: 0)
        editor.chooseVariable(named: "Side", for: .steps)

        editor.switchToNumber(.steps)

        #expect(editor.program == Self.program(variables: [Variable(name: "Side")]))
    }

    /// Review mutant A22: a slot that cannot hold a variable must not get a declaration either.
    @Test("a variable for a slot that cannot hold one declares nothing")
    func noStrayDeclaration() {
        let editor = EditorViewModel(program: Self.program())
        editor.beginParameterEdit(at: 0)

        #expect(editor.createVariable(named: "New", for: .hex) == nil)

        #expect(editor.program == Self.program())
    }

    /// Review mutant A8: the anchor belongs to one slot. A rejection on another slot of the same
    /// brick must not write the first slot's anchor into it.
    @Test("a rejection on another slot does not use this slot's anchor")
    func anchorIsPerSlot() {
        let editor = EditorViewModel(program: Self.program(), decimalSeparator: ".")
        editor.beginParameterEdit(at: 1)
        editor.beginNumberEntry(for: .width)

        _ = editor.enterNumber("1e400", for: .length)

        #expect(editor.program == Self.program())
    }

    /// Finding 11: the stepper moves the anchor of its own slot, so a rejection typed after two
    /// taps returns to the tapped value rather than silently discarding the taps.
    @Test("a stepper tap moves the anchor")
    func stepperMovesTheAnchor() {
        let editor = EditorViewModel(program: Self.program(), decimalSeparator: ".")
        editor.beginParameterEdit(at: 0)
        editor.beginNumberEntry(for: .steps)
        editor.stepNumber(.steps, by: 1)
        editor.stepNumber(.steps, by: 1)

        _ = editor.enterNumber("a", for: .steps)

        #expect(editor.program == Self.replacing(0, with: .moveNSteps(.number(19))))
    }

    /// Item 9's other half (review mutant A11b): a `.unaryMinus` parameter round-trips untouched.
    @Test("item 9: opening and closing a negated formula leaves the program untouched")
    func unaryMinusRoundTrip() {
        let program = Self.program([.moveNSteps(.unaryMinus(.variable("Side")))], variables: [Variable(name: "Side")])
        let editor = EditorViewModel(program: program)

        #expect(editor.beginParameterEdit(at: 0))
        editor.endParameterEdit()

        #expect(editor.program == program)
        #expect(editor.undoStack.undoDepth == 0)
    }

    /// The test ADR-038 assigns to this story (review mutant A18): a key minted before a load can
    /// never equal one minted after it, which only holds if `load` resets the stack rather than
    /// replacing it.
    @Test("a key minted after a load differs from one minted before it")
    func keysSurviveALoad() throws {
        let editor = EditorViewModel(program: Self.program())
        editor.beginParameterEdit(at: 0)
        let before = try #require(editor.parameterSession?.key)

        editor.load(Self.program())
        editor.beginParameterEdit(at: 0)

        #expect(editor.parameterSession?.key != before)
    }

    /// Finding 15: a name the object already declares is chosen from the menu, not created, so
    /// the character rules — written for names this editor creates — do not stand between a
    /// loaded file's variable and its use.
    @Test("an already-declared name is usable even if this editor could not create it")
    func declaredNameBypassesCreationRules() {
        let loaded = Self.program(variables: [Variable(name: "a\"b")])
        let editor = EditorViewModel(program: loaded)
        editor.beginParameterEdit(at: 0)

        editor.chooseVariable(named: "a\"b", for: .steps)

        var bricks = Self.bricks
        bricks[0] = .moveNSteps(.variable("a\"b"))
        #expect(editor.program == Self.program(bricks, variables: [Variable(name: "a\"b")]))
    }

    /// Codex round 1: the menu lists names exactly as declared, so choosing one must reference
    /// exactly that one. Trimming first turned a loaded `" Side "` into a fresh `"Side"`
    /// declaration. Trimming belongs to the Create path only.
    @Test("choosing a declared name with surrounding spaces references it exactly")
    func declaredNameIsNotTrimmed() {
        let loaded = Self.program(variables: [Variable(name: " Side ", value: 7)])
        let editor = EditorViewModel(program: loaded)
        editor.beginParameterEdit(at: 0)

        editor.chooseVariable(named: " Side ", for: .steps)

        var bricks = Self.bricks
        bricks[0] = .moveNSteps(.variable(" Side "))
        #expect(editor.program == Self.program(bricks, variables: [Variable(name: " Side ", value: 7)]))
    }

    // MARK: Codex round 2 — the menu and the Create field are two operations

    /// Typing a name into Create always means the trimmed name, even when the untrimmed text
    /// happens to equal a declared variable: `" Side "` typed while `" Side "` is declared
    /// creates `"Side"`.
    @Test("Create trims even when the untrimmed text is declared")
    func createTrimsAlways() {
        let loaded = Self.program(variables: [Variable(name: " Side ")])
        let editor = EditorViewModel(program: loaded)
        editor.beginParameterEdit(at: 0)

        editor.createVariable(named: " Side ", for: .steps)

        var bricks = Self.bricks
        bricks[0] = .moveNSteps(.variable("Side"))
        #expect(editor.program == Self.program(bricks, variables: [Variable(name: " Side "), Variable(name: "Side")]))
    }

    /// Creating a name that is already declared references it rather than refusing it as a
    /// duplicate: the user asked for that variable, and it exists.
    @Test("Create with a name already declared references it, declaring nothing")
    func createExistingReferences() {
        let loaded = Self.program(variables: [Variable(name: "Side", value: 3)])
        let editor = EditorViewModel(program: loaded)
        editor.beginParameterEdit(at: 0)

        editor.createVariable(named: " Side ", for: .steps)

        var bricks = Self.bricks
        bricks[0] = .moveNSteps(.variable("Side"))
        #expect(editor.program == Self.program(bricks, variables: [Variable(name: "Side", value: 3)]))
        #expect(editor.undoStack.undoDepth == 1)
    }

    /// The menu offers only what is declared, so choosing anything else is no edit at all — in
    /// particular, never a declaration.
    @Test("choosing an undeclared name changes nothing")
    func chooseUndeclared() {
        let editor = EditorViewModel(program: Self.program())
        editor.beginParameterEdit(at: 0)

        #expect(editor.chooseVariable(named: "Side", for: .steps) == nil)

        #expect(editor.program == Self.program())
    }

    /// File names are not restricted (ADR-040): written exactly as typed, surrounding spaces and
    /// all. Only an empty or blank name is refused, so the row never needs its placeholder.
    @Test("a file name is written exactly as typed; a blank one not at all")
    func fileNameIsExact() {
        let editor = EditorViewModel(program: Self.program([.writeEmbroideryToFile(name: "old")]))
        editor.beginParameterEdit(at: 0)

        editor.setFileName("   ")
        #expect(editor.program == Self.program([.writeEmbroideryToFile(name: "old")]))
        editor.setFileName(" report ")
        #expect(editor.program == Self.program([.writeEmbroideryToFile(name: " report ")]))
    }
}
