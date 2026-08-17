import EmbroideryEngine

/// A run's last word: why it ended, and the export model as of that moment.
///
/// **`exportModel` is non-optional and has no default**, so terminating a run without *an*
/// export model is unrepresentable. That is what the type buys, and it is worth having: no
/// completion path can be added later that forgets the field exists.
///
/// **It is not the whole criterion, and an earlier version of this comment said it was.**
/// US-306 asks that the terminal carry `assembledStream()` specifically, and no type can
/// promise that — `RunTermination(reason:exportModel:)` compiles with any `EmbroideryStream`,
/// including a sentinel. What delivers the stronger property is that every path funnels
/// through one private `terminal(_:of:batch:)` which calls `assembledStream()`, plus the tests
/// that compare the delivered model against an independently stepped interpreter. Codex round
/// 3 found that the tests had only asserted "non-empty", and round 4 that this comment still
/// claimed the type did the work.
///
/// The hazard it closes is concrete rather than hypothetical. Catty's
/// `Stage.stopProject()` calls `removeAllChildren()` and
/// `frontend.project?.removeReferences()` — destroying exactly the object graph
/// its own `shareDST` reads — so on that platform stopping a run can cost you the
/// design you wanted to export. Here the export model is *part of* the stop.
///
/// `Equatable` but deliberately **not** `Hashable`: `EmbroideryStream` is
/// `Hashable`, so synthesis would succeed and give us an unconditionally O(n)
/// hash over up to 200 000 records — the same trap `StitchDisplayList` declined
/// `Hashable` to avoid. Nothing needs a hash here.
public struct RunTermination: Equatable, Sendable {
    public let reason: RunCompletion

    /// `Interpreter.assembledStream()` at the moment the run ended. Cheap enough
    /// to do unconditionally: 0.84 ms at 50 001 records in release (ADR-021
    /// measured 0.64 ms), and it happens once per run rather than per frame.
    public let exportModel: EmbroideryStream

    public init(reason: RunCompletion, exportModel: EmbroideryStream) {
        self.reason = reason
        self.exportModel = exportModel
    }
}

/// One frame's worth of run output: the stitches to append, and — on the last
/// frame only — why the run ended and what to export.
///
/// **One element type carrying an optional terminal, not two element cases.**
/// The alternative considered and rejected was an enum (`case batch` /
/// `case finished`), which would make the terminal a *second* stream element and
/// therefore a second observable mutation on the final frame. US-306's
/// "exactly one observable mutation per batch" criterion is checked by comparing
/// a mutation count against the batch count; a two-element finish makes that
/// arithmetic off by one for every run, which is precisely the kind of
/// almost-right that a test would then be written to accommodate.
///
/// The terminal also **does not** live on `RunBatch`, whose own doc comment
/// argues against it: `RunBatch` is a pure fold over `InterpreterEvent`s and none
/// of the three completion reasons is an event. It is also `Hashable` and built
/// once per frame, so hanging an `EmbroideryStream` on it would be the O(n)-hash
/// trap again. Keeping the fold pure and the terminal beside it means the
/// per-frame type stays cheap and the reason for its purity stays true.
public struct RunUpdate: Equatable, Sendable {
    public var batch: RunBatch

    /// `nil` while the run continues; non-`nil` exactly once, on the last update.
    public var termination: RunTermination?

    public init(batch: RunBatch, termination: RunTermination? = nil) {
        self.batch = batch
        self.termination = termination
    }
}
