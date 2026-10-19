@testable import catrobat_embroidery_ios
import ProgramModel
import Testing

/// Editor UI slice 4 (ADR-034's 2026-10-15 amendment): **row identity is derived by the editor,
/// not stored in the model.** After every change the IDs follow the bricks: unchanged rows keep
/// theirs, a moved block carries its own, new rows get fresh ones.
///
/// Why it matters: with index identity, a drop that UIKit has already animated arrived as "row 4
/// changed its contents", so for about a third of a second the list showed the wrong brick and an
/// empty gap, then snapped (recorded on the simulator, Sebastian's report of 2026-10-15). Every
/// expectation below is a **whole-array** equality, so an ID attached to the wrong row is a red
/// test, not a plausible-looking list.
struct RowIdentitiesTests {
    private static let sewUp = Brick.sewUp
    private static let opener = Brick.repeatLoop(times: .number(2))
    private static let body = Brick.stitch
    private static let end = Brick.loopEnd
    private static let move = Brick.moveNSteps(.number(10))
    private static let turn = Brick.turnRight(.number(90))

    /// IDs 0…5, in order.
    private static let bricks = [sewUp, opener, body, end, move, turn]

    private static func followed(to new: [Brick], from old: [Brick] = bricks) -> RowIdentities {
        var identities = RowIdentities(count: old.count)
        identities.follow(from: old, to: new)
        return identities
    }

    @Test("a new set of rows has distinct IDs, one per row")
    func initialIDs() {
        #expect(RowIdentities(count: 6).ids == [0, 1, 2, 3, 4, 5])
    }

    /// The case that stuttered: a leaf dragged down past a loop.
    @Test("a dragged leaf carries its ID; every other row keeps its own")
    func leafMove() {
        let identities = Self.followed(to: [Self.opener, Self.body, Self.end, Self.sewUp, Self.move, Self.turn])
        #expect(identities.ids == [1, 2, 3, 0, 4, 5])
    }

    @Test("a dragged loop carries all three of its IDs together")
    func pairMove() {
        let identities = Self.followed(to: [Self.sewUp, Self.move, Self.opener, Self.body, Self.end, Self.turn])
        #expect(identities.ids == [0, 4, 1, 2, 3, 5])
    }

    /// Codex round 1 (Editor UI): every `loopEnd` is the same value, so a greedy suffix scan
    /// paired the *outer* loop's end with the *inner* one and the move went unrecognised —
    /// leaving all five IDs in place, attached to the wrong bricks.
    @Test("a nested loop moved below its parent's end carries its three IDs past it")
    func nestedPairOutOfParent() {
        let outer = Brick.repeatLoop(times: .number(2)), inner = Brick.repeatLoop(times: .number(3))
        var identities = RowIdentities(count: 5)
        identities.follow(
            from: [outer, inner, Self.body, Self.end, Self.end],
            to: [outer, Self.end, inner, Self.body, Self.end]
        )
        #expect(identities.ids == [0, 4, 1, 2, 3])
    }

    @Test("a loop moved into the loop above, across its end, carries its three IDs")
    func pairIntoLoopAcrossItsEnd() {
        let outer = Brick.repeatLoop(times: .number(2)), inner = Brick.repeatLoop(times: .number(3))
        var identities = RowIdentities(count: 5)
        identities.follow(
            from: [outer, Self.end, inner, Self.body, Self.end],
            to: [outer, inner, Self.body, Self.end, Self.end]
        )
        #expect(identities.ids == [0, 2, 3, 4, 1])
    }

    /// Variables slice 2 (Codex slice review: covered only by the soak until now). Equal
    /// conditions and equal markers on both Ifs make every rotation look plausible; only the
    /// block-shaped one may be taken.
    @Test("an If/Else crossing its parent's else carries its three IDs, in both directions")
    func nestedIfAcrossTheElse() {
        let outer = Brick.ifElse(condition: .constant(.true)), inner = outer
        let inThen: [Brick] = [outer, inner, .elseBranch, .ifEnd, .elseBranch, .ifEnd]
        let inElse: [Brick] = [outer, .elseBranch, inner, .elseBranch, .ifEnd, .ifEnd]

        var down = RowIdentities(count: 6)
        down.follow(from: inThen, to: inElse)
        #expect(down.ids == [0, 4, 1, 2, 3, 5])

        var up = RowIdentities(count: 6)
        up.follow(from: inElse, to: inThen)
        #expect(up.ids == [0, 2, 3, 4, 1, 5])
    }

    @Test("an insert keeps every existing ID and gives the new row a fresh one")
    func insert() {
        let identities = Self.followed(
            to: [Self.sewUp, .stopRunningStitch, Self.opener, Self.body, Self.end, Self.move, Self.turn]
        )
        #expect(identities.ids == [0, 6, 1, 2, 3, 4, 5])
    }

    @Test("deleting a loop removes its three IDs and keeps the rest")
    func pairDelete() {
        #expect(Self.followed(to: [Self.sewUp, Self.move, Self.turn]).ids == [0, 4, 5])
    }

    /// A parameter edit changes a row's contents, not which row it is — so the row is not
    /// re-created under the user's finger.
    @Test("a parameter change keeps every ID")
    func parameterChange() {
        let changed = [Self.sewUp, Self.opener, Self.body, Self.end, .moveNSteps(.number(20)), Self.turn]
        #expect(Self.followed(to: changed).ids == [0, 1, 2, 3, 4, 5])
    }

    /// Undo restores a snapshot from outside the edit vocabulary; the IDs must come back with it,
    /// or undoing a drag would animate as a wholesale change.
    @Test("a move followed by its undo restores the original IDs")
    func moveThenUndo() {
        let moved = [Self.opener, Self.body, Self.end, Self.sewUp, Self.move, Self.turn]
        var identities = RowIdentities(count: Self.bricks.count)
        identities.follow(from: Self.bricks, to: moved)
        identities.follow(from: moved, to: Self.bricks)
        #expect(identities.ids == [0, 1, 2, 3, 4, 5])
    }

    /// An ID is never reused, even once its row is gone: SwiftUI would take a reused ID for the
    /// old row coming back.
    @Test("a deleted row's ID is never handed out again")
    func idsAreNeverReused() {
        let deleted = [Self.sewUp, Self.opener, Self.body, Self.end, Self.turn]
        var identities = RowIdentities(count: Self.bricks.count)
        identities.follow(from: Self.bricks, to: deleted)
        identities.follow(from: deleted, to: deleted + [Self.move])

        #expect(identities.ids == [0, 1, 2, 3, 5, 6])
    }

    /// Codex round 2: only a **one-brick** window is a change in place (a parameter edit). An
    /// unrelated program of the same length — a `load` — is a replacement, and gets fresh IDs.
    @Test("an unrelated program of the same length gets fresh IDs")
    func equalLengthReplacement() {
        var identities = RowIdentities(count: 2)
        identities.follow(from: [Self.sewUp, Self.body], to: [Self.turn, Self.move])
        #expect(identities.ids == [2, 3])
    }

    /// The same bricks reordered in a way no single move explains is not a move either.
    @Test("a reorder that is not one move gets fresh IDs")
    func nonMoveReorder() {
        var identities = RowIdentities(count: 4)
        identities.follow(
            from: [Self.sewUp, Self.body, Self.move, Self.turn],
            to: [Self.body, Self.sewUp, Self.turn, Self.move]
        )
        #expect(identities.ids == [4, 5, 6, 7])
    }

    /// A whole-program replacement — a different sample — shares nothing but a matching tail.
    @Test("an unrelated program gets fresh IDs except where rows still match")
    func replacement() {
        let identities = Self.followed(to: [Self.turn, Self.turn, Self.turn])
        #expect(identities.ids == [6, 7, 5])
    }

    // MARK: Through the editor's doors

    /// The IDs live on `EditorViewModel` and follow **every** stack change, so a drag, its undo
    /// and its redo all keep rows stable — not only the doors that build an `EditAction`.
    @MainActor
    @Test("the editor's row IDs follow a drag, its undo and its redo")
    func editorFollowsEveryDoor() {
        let program = Program(name: "p", scenes: [Scene(objects: [Object(scripts: [Script(bricks: Self.bricks)])])])
        let editor = EditorViewModel(program: program, undoManager: nil)
        #expect(editor.rowIDs == [0, 1, 2, 3, 4, 5])

        // The list's own drop: the leaf at 0 dropped after the loop (pre-removal offset 4).
        editor.moveRows(fromOffsets: [0], toOffset: 4)
        #expect(editor.rowIDs == [1, 2, 3, 0, 4, 5])

        editor.undo()
        #expect(editor.rowIDs == [0, 1, 2, 3, 4, 5])
        editor.redo()
        #expect(editor.rowIDs == [1, 2, 3, 0, 4, 5])
    }

    /// `List(selection:)` selects by the `ForEach` identity — an explicit `.tag` did not override
    /// it on iOS 26, so after a drag tapping "Set Side to 9" (row ID 2, index 1) selected index 2
    /// and the palette inserted inside the next loop (found on the simulator, 2026-10-15). The list
    /// therefore binds to `selectedRowID`, which translates to and from `selectedBrickIndex`.
    @MainActor
    @Test("the list's selection translates between row IDs and brick indices")
    func selectionByRowID() {
        let program = Program(name: "p", scenes: [Scene(objects: [Object(scripts: [Script(bricks: Self.bricks)])])])
        let editor = EditorViewModel(program: program, undoManager: nil)
        editor.moveRows(fromOffsets: [0], toOffset: 4) // IDs now [1, 2, 3, 0, 4, 5]

        editor.selectedRowID = 2 // the stitch, now at index 1
        #expect(editor.selectedBrickIndex == 1)

        editor.selectedBrickIndex = 3 // the sew-up, ID 0
        #expect(editor.selectedRowID == 0)

        editor.selectedRowID = nil
        #expect(editor.selectedBrickIndex == nil)
        editor.selectedRowID = 99 // no such row
        #expect(editor.selectedBrickIndex == nil)
    }

    /// Codex round 3: a diff cannot tell a parameter edit from a replacement that differs in one
    /// row, but the editor can — only `load` replaces the whole program — so `load` renews every ID.
    @MainActor
    @Test("loading a program gives every row a fresh ID, even where a row is unchanged")
    func loadRenewsEveryID() {
        func program(_ bricks: [Brick]) -> Program {
            Program(name: "p", scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
        }
        let editor = EditorViewModel(program: program([Self.sewUp, Self.body]), undoManager: nil)
        #expect(editor.rowIDs == [0, 1])

        editor.load(program([Self.sewUp, Self.turn])) // one row differs, one is unchanged
        #expect(editor.rowIDs == [2, 3])

        editor.load(program([Self.move])) // a one-row program replaced by another
        #expect(editor.rowIDs == [4])
    }

    /// Codex round 4: VoiceOver focus is keyed by row ID, decided once — after a move or an
    /// insert — from the row's index, so a later undo, redo or load cannot leave it on whatever
    /// brick then occupies that index.
    @MainActor
    @Test("a row's ID is looked up by index, and an index with no row has none")
    func rowIDAtIndex() {
        let program = Program(name: "p", scenes: [Scene(objects: [Object(scripts: [Script(bricks: Self.bricks)])])])
        let editor = EditorViewModel(program: program, undoManager: nil)
        editor.moveRows(fromOffsets: [0], toOffset: 4) // IDs now [1, 2, 3, 0, 4, 5]

        #expect(editor.rowID(at: 3) == 0, "the moved sew-up keeps its ID at its new index")
        #expect(editor.rowID(at: 0) == 1)
        #expect(editor.rowID(at: 6) == nil)
        #expect(editor.rowID(at: -1) == nil)
    }
}
