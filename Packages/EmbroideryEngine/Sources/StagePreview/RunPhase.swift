import EmbroideryEngine

/// Everything that may change **only** when the run changes state: where the run is, and
/// the summary of what the stage holds.
///
/// **A separate type, because Swift has no intra-type access control.** US-307's headline
/// requirement is that the accessibility summary is rebuilt on run-state transitions and
/// never per batch — a value changing sixty times a second makes VoiceOver unusable. Two
/// `private(set)` properties on `PreviewRunState` would leave `apply(_:)` free to assign
/// the summary every frame, since `private` there means "within this type". Here it means
/// "within `RunPhase`", so `apply(_:)` **cannot** touch the summary at all: the only way in
/// is `enter(_:summarising:exportModel:)`, which always sets a state alongside it.
///
/// **What that does and does not prove, stated precisely**, because the neighbouring
/// invariant in ADR-027 had the word "unrepresentable" retracted three times. This is a
/// *chokepoint*, not an impossibility: calling `enter` once per batch is still
/// representable, and that is exactly why the counter test below is not vacuous. Putting
/// the summary inside `RunState`'s payload *would* make it impossible — and would make the
/// test tautological, since the transition count would then equal the summary-change count
/// by definition. That is the "five tests that could not fail" pattern this repo has now
/// hit nine times across two stories, and it is declined here on purpose.
public struct RunPhase: Equatable, Sendable {
    public private(set) var state: RunState = .idle

    /// Rebuilt only by `enter`. See the type's doc comment.
    public private(set) var summary: StageSummary = .empty

    /// How many transitions this phase has been through — i.e. how many times the summary
    /// was rebuilt.
    ///
    /// The same device as `PreviewRunState.revision`, and it is meant to be compared
    /// against it: a correct run gives 2 (idle → running → finished) against 139 batches
    /// for `octagonRosette`, two orders of magnitude apart, so an implementation that
    /// rebuilt per batch fails loudly rather than marginally.
    public private(set) var revision = 0

    public init() {}

    /// Enters `state`, rebuilding the summary from the run as it stands.
    ///
    /// Callers must append the batch **before** entering a terminal state, or the terminal
    /// summary undercounts by one frame. That ordering is pinned by
    /// `PreviewRunStateTests.theTerminalSummaryIncludesTheTerminalBatch` rather than left
    /// to this comment.
    public mutating func enter(
        _ state: RunState,
        summarising display: StitchDisplayList,
        exportModel: EmbroideryStream?
    ) {
        let rebuilt = StageSummary(display: display, exportModel: exportModel)

        // **Nothing observable changed, so nothing is recorded as having changed.**
        //
        // `reset()` is called on an already-idle run in ordinary use — `AppModel.select(_:)`
        // does it for the first selection — and unconditionally entering `.idle` from `.idle`
        // bumped `revision` for a transition that did not happen, making the count this story
        // asserts on literally false (Codex round 1).
        //
        // The guard is on the **pair** rather than the state alone so that it means "nothing
        // observable changed" rather than "the state repeated". Those coincide today — a
        // restart mid-run leaves both `.running` and `.empty`, because a running summary
        // carries no counts — and the pair is what stays correct if that ever stops being
        // true. An earlier version of this comment claimed the opposite, that a mid-run
        // restart "must still rebuild"; the test written to pin that claim failed against it,
        // which is how the claim was caught.
        guard state != self.state || rebuilt != summary else { return }

        self.state = state
        summary = rebuilt
        revision += 1
    }
}
