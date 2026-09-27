import EditorCore
import Observation
import ProgramModel

/// The working program, its history, and the one door every edit goes through (US-405).
///
/// **No view mutates the program** (ADR-006 pattern 1): the only writers are `apply(_:)` and
/// `load(_:)`, and both go through the `UndoStack`, which is the truth (ADR-036). There is no
/// second stored copy — `program` *reads* `undoStack.current` — so the history and what is on
/// screen cannot drift apart.
///
/// Owned by `AppModel`, one per window, for the ADR-023 reason every other piece of this
/// window's state is: `RootView` tears down a navigation container on a size-class change,
/// and an editor held inside one would lose the user's work on an iPad resize.
///
/// Undo and redo are not surfaced yet — US-408 adds the toolbar pair, US-410 the coalescing
/// sessions, and each will route through the same announcement below.
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

    /// Called once for every edit that **applied and changed the program**, and never for a
    /// rejected one or a `load`.
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
    @ObservationIgnored var onEditApplied: (() -> Void)?

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
            onEditApplied?()
        }
        return result
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
