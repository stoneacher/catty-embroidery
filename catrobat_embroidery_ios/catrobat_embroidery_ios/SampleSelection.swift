import ProgramModel
import Samples

/// The sample the user has chosen, and *which time* they chose it.
///
/// The generation is the whole reason this type exists instead of a bare
/// `SampleProgram?`. The story requires that re-selecting the sample already
/// selected re-publishes it rather than being a no-op, so that a later consumer
/// can treat a selection as "start over". Under Observation the setter does fire
/// on every assignment regardless of equality — but that notification is
/// swallowed one layer up, because the natural spellings on the consumer side
/// (`.onChange(of:)`, `.task(id:)`) compare `Equatable` values and dedupe. A
/// counter that changes makes the second selection a genuinely different value,
/// so the restart survives the consumer. It is also what makes the property
/// *testable*: without it the model's before and after states are identical and
/// no expectation can tell them apart.
///
/// Deliberately **not** `Identifiable`. A `var id: SampleID` would make
/// `.task(id: selection.id)` compile and silently stop re-firing on
/// re-selection — the exact defect the generation exists to prevent, in the
/// spelling a later author is most likely to reach for.
///
/// It closes that spelling, **not the trap**. `.task(id: selection.sample.id)`
/// still compiles and still dedupes, because `SampleProgram` is `Identifiable`
/// and its id is one dot away; no type-level trick can prevent that. The
/// defence that actually holds is this comment plus
/// `AppModelTests.reselectingTheSameSamplePublishesAgainRatherThanBeingANoOp`,
/// which states what the id-based spellings would break. (In-loop review — the
/// earlier wording claimed the conformance's absence "removes the trap".)
///
/// `nonisolated` for the reason `AppRunClock` records: the app target builds
/// with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without the keyword this
/// value type would be main-actor isolated and US-306's driver — which must run
/// off the main actor, since one `step()` can emit millions of events — could
/// not read `program` from it. One keyword now, or a cross-story edit later.
nonisolated struct SampleSelection: Equatable, Sendable {
    /// The chosen sample.
    let sample: SampleProgram

    /// Monotonically increasing, assigned by `AppModel.select(_:)`. Never
    /// displayed; its only job is to make two selections of the same sample
    /// unequal.
    let generation: Int

    /// The program to run. What US-306 constructs its `Interpreter` from.
    ///
    /// Exposed here rather than reached through `sample` so that the seam a
    /// later story consumes is the seam this story's tests cover.
    var program: Program {
        sample.program
    }
}
