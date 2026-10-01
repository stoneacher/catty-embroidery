import EditorCore
import Observation
import ProgramModel

/// The working program, its history, and the one door every edit goes through (US-405).
///
/// **No view mutates the program** (ADR-006 pattern 1): the only writers are `apply(_:)`,
/// `undo()`, `redo()` and `load(_:)`, and all four go through the `UndoStack`, which is the
/// truth (ADR-036). There is no second stored copy — `program` *reads* `undoStack.current` —
/// so the history and what is on screen cannot drift apart.
///
/// Owned by `AppModel`, one per window, for the ADR-023 reason every other piece of this
/// window's state is: `RootView` tears down a navigation container on a size-class change,
/// and an editor held inside one would lose the user's work on an iPad resize.
///
/// Three doors change the program, and all three announce through `onProgramChanged`: `apply`,
/// and since US-408 the toolbar's `undo()` and `redo()`. US-410 adds the coalescing sessions
/// and US-411 the `UndoManager` bridge, both routing through the same doors.
@MainActor
@Observable
final class EditorViewModel {
    /// The history, and through `current` the working program. `private(set)`: a caller that
    /// could assign it could replace the program without the announcement firing.
    private(set) var undoStack: UndoStack

    /// The working program — what `AppModel.play()` runs and what every later editor view
    /// reads.
    var program: Program {
        undoStack.current
    }

    /// Called once for every edit that **applied and changed the program**, and for every
    /// successful undo and redo (US-408) — never for a rejected edit, an empty undo or redo, or
    /// a `load`.
    ///
    /// Renamed from `onEditApplied` in US-408: an undo is not an applied edit, and it needs the
    /// same consequences (ADR-038's 2026-09-29 amendment).
    ///
    /// A callback on the one door rather than a facade on `AppModel`, for the reason ADR-027
    /// hung the file discard on `RunViewModel.onRunDiscarded`: later views (US-408…US-410) will
    /// call `model.editor.apply` directly, so the invariant "an edit voids the run" has to live
    /// at the chokepoint every path passes through, not at a convenience one path might skip.
    ///
    /// **"Changed", not merely "applied"** (decided 2026-09-27, ADR-038): `EditorCore.apply`
    /// reports a rename to the current name as `.applied`, and `UndoStack` already records
    /// nothing for it. Voiding a finished design over an edit that did not happen would be the
    /// same mistake one layer up.
    @ObservationIgnored var onProgramChanged: (() -> Void)?

    init(program: Program = .blank) {
        undoStack = UndoStack(program: program)
    }

    /// Applies `action` to the working program, recording it for undo.
    ///
    /// Returns the result rather than a `Bool` so a caller can say *why* an edit was refused
    /// — the reason ADR-033 made `apply` total and non-throwing in the first place.
    @discardableResult
    func apply(_ action: EditAction) -> EditResult {
        let before = undoStack.current
        let result = undoStack.apply(action)
        if case .applied = result, undoStack.current != before {
            onProgramChanged?()
        }
        return result
    }

    // MARK: History (US-408)

    /// Whether the toolbar's undo button is enabled.
    var canUndo: Bool {
        undoStack.canUndo
    }

    /// Whether the toolbar's redo button is enabled.
    var canRedo: Bool {
        undoStack.canRedo
    }

    /// Steps the working program back one entry; `false`, changing nothing, with none to undo.
    ///
    /// **Announces through `onProgramChanged`**, and that is the load-bearing line: undo
    /// restores a snapshot from outside the `EditAction` vocabulary, so nothing that hangs off
    /// `apply` — the run's void, the prepared file's discard, the autosave (ADR-038) — would
    /// otherwise follow it. Undoing back to P after running Q would leave Q's preview and its
    /// `.dst` offered beside P's script. The announcement records nothing: the stack moved
    /// itself, and the listener only saves and voids.
    ///
    /// US-411 puts the `UndoManager` bridge, the spoken announcements and the totality proof
    /// on top of this; the consequences live here so that every path reaches them.
    @discardableResult
    func undo() -> Bool {
        guard undoStack.undo() != nil else { return false }
        onProgramChanged?()
        return true
    }

    /// Steps the working program forward one undone entry; `false`, changing nothing, with none
    /// to redo. Announces for `undo()`'s reason.
    @discardableResult
    func redo() -> Bool {
        guard undoStack.redo() != nil else { return false }
        onProgramChanged?()
        return true
    }

    // MARK: Selection and the palette (US-409)

    /// The row the script list has selected, by index into the first script.
    var selectedBrickIndex: Int?

    /// Inserts `kind` where a palette tap means, returning the inserted head's index.
    @discardableResult
    func insert(_ kind: BrickKind) -> Int? {
        nil
    }

    // MARK: The list's gestures (US-408)

    /// The list's `.onMove`, converted by `Script.moveAction(fromOffsets:toOffset:in:)` and then
    /// applied through the one door. `nil` when the gesture is no edit — several rows, or a
    /// block dropped back where it was.
    ///
    /// The first script, which is the only one M4 edits and the one the list shows.
    @discardableResult
    func moveRows(fromOffsets source: some Collection<Int>, toOffset: Int) -> EditResult? {
        guard let script = program.scenes.first?.objects.first?.scripts.first,
              let action = script.moveAction(fromOffsets: source, toOffset: toOffset, in: ScriptAddress())
        else { return nil }
        return apply(action)
    }

    /// The list's `.onDelete`, through the one door. `nil` for several rows or none.
    @discardableResult
    func deleteRows(atOffsets offsets: some Collection<Int>) -> EditResult? {
        guard let script = program.scenes.first?.objects.first?.scripts.first,
              let action = script.deleteAction(atOffsets: offsets, in: ScriptAddress())
        else { return nil }
        return apply(action)
    }

    /// Replaces the working program wholesale — a picked sample today, a program loaded from
    /// disk in US-406 — discarding both directions of history.
    ///
    /// `reset(to:)` on the existing stack, never a new `UndoStack`: ADR-036's key serial keeps
    /// counting through a reset, and a fresh stack would restart it — so a coalescing key minted
    /// before the load could equal the first one minted after it and fold into an unrelated
    /// session. Announces nothing: a load is not an edit, and its caller already decides what
    /// happens to the run.
    func load(_ program: Program) {
        undoStack.reset(to: program)
    }
}
