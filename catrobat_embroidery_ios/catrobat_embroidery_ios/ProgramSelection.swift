import Foundation
import Samples

/// What the stage is showing, where it came from, and *which time* it was chosen.
///
/// Was `SampleSelection` until US-405, which wrapped a `SampleProgram`. An edited program has
/// no `SampleID`, so the selection no longer carries the program at all — `EditorViewModel`
/// owns that, and there is one copy of it rather than two able to disagree. What is left here
/// is what the *chrome* needs: a title, an origin, and a generation.
///
/// The generation is the reason this type exists instead of a bare optional. US-304 requires
/// that re-selecting the sample already selected re-publishes it rather than being a no-op,
/// so that a later consumer can treat a selection as "start over". Under Observation the
/// setter does fire on every assignment regardless of equality — but that notification is
/// swallowed one layer up, because the natural spellings on the consumer side
/// (`.onChange(of:)`, `.task(id:)`) compare `Equatable` values and dedupe. A counter that
/// changes makes the second selection a genuinely different value, so the restart survives
/// the consumer. It is also what makes the property *testable*: without it the model's before
/// and after states are identical and no expectation can tell them apart.
///
/// Deliberately **not** `Identifiable`. A `var id` would make `.task(id: selection.id)`
/// compile and silently stop re-firing on re-selection — the exact defect the generation
/// exists to prevent, in the spelling a later author is most likely to reach for.
///
/// It closes that spelling, **not the trap**. `.task(id: selection.provenance)` still compiles
/// and still dedupes; no type-level trick can prevent that. The defence that actually holds
/// is this comment plus
/// `AppModelTests.reselectingTheSameSamplePublishesAgainRatherThanBeingANoOp`, which states
/// what the id-based spellings would break.
///
/// **The synthesized `==` is back, and cheap.** `SampleSelection` needed a hand-written one
/// because synthesizing it compared the whole `Program` tree on every update pass; with no
/// program in the value there is nothing expensive left to compare. The generation is still
/// part of the comparison, which is the point of the type.
///
/// **Consumers that mean "start over" must key on `generation`, not on the whole value.**
/// Since US-405 an applied edit clears `provenance` without a new generation, so the value
/// changes on the first edit too; a future `.task(id: selection)` would treat that edit as a
/// restart. No such consumer exists today (US-305's drain is gone).
///
/// `nonisolated` although the original reason has gone: `SampleSelection` needed it because
/// the driver's task read `program` off the main actor, and this type holds no program. Kept
/// because a plain `Sendable` value has no reason to be main-actor isolated, and dropping it
/// would make the value unusable from any future off-actor reader for no gain.
nonisolated struct ProgramSelection: Equatable, Sendable {
    /// Monotonically increasing, assigned by `AppModel.select(_:)`. Never displayed; its only
    /// job is to make two selections of the same sample unequal.
    let generation: Int

    /// The sample this program was loaded from, while it still *is* that sample.
    ///
    /// Cleared by the first applied edit (US-405, ADR-038), which is what stops the picker
    /// highlight claiming a program is a bundled sample once it is not. `var` for that one
    /// writer; `AppModel.selection` is `private(set)`, so nothing outside the model reaches it.
    var provenance: SampleID?

    /// The stage's navigation title, captured when the program was loaded.
    ///
    /// **Not cleared by an edit**, unlike `provenance`: "Octagon Rosette, with one brick
    /// changed" is still the design the user is looking at, and a title flipping to "Stage"
    /// on the first nudge would read as the design having been thrown away. `nil` is not
    /// reachable through `select(_:)` and is kept optional so the stage's own `nil` — nothing
    /// picked — has one spelling.
    let title: LocalizedStringResource?
}

extension ProgramSelection {
    /// What a window selects at launch: the blank working program, as an untitled design of
    /// no sample (US-407, ADR-039 — the flip ADR-038 handed that story).
    ///
    /// Until US-407 a window launched with no selection at all, and since `AppModel.play()` is
    /// gated on one, a program built from nothing could never run — M4's exit criterion 1.
    /// `restoreSavedProgram()` replaces it with the saved program's own title; a refused file
    /// leaves it, which is right, because the window holds the blank program either way.
    static func launch(generation: Int) -> ProgramSelection {
        ProgramSelection(generation: generation, provenance: nil, title: .programTitleUntitled)
    }
}
