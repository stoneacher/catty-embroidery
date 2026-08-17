/// Why a run ended. Three cases, and there is deliberately no fourth.
///
/// **There is no `failed`.** ADR-018 guarantees the interpreter never halts:
/// every bad-formula path continues with a per-brick Catroid fallback, and
/// `FormulaError.notANumber` is caught rather than propagated. So nothing in the
/// *run* path can fail, and a `failed` case here would be a case with no
/// producer — unreachable code that every `switch` must nonetheless handle, and
/// that a later reader would try to reach.
///
/// Failure belongs to the *export* lifecycle, which genuinely can fail (disk,
/// and after US-211 a field-width overflow). That is `ExportState`, US-308's.
///
/// This corrects ROADMAP.md's `idle/running/finished/failed` enum rather than
/// shipping what it specified; the milestone README records the deviation.
public enum RunCompletion: Hashable, Sendable {
    /// Every runnable thread finished on its own — `step()` returned `.finished`.
    case programFinished

    /// The user pressed stop, so the producer task was cancelled.
    ///
    /// Reaching this state still delivers an export model, which is the whole
    /// point of `RunTermination`: Catty's `Stage.stopProject()` tears down the
    /// object graph its own `shareDST` reads.
    case stoppedByUser

    /// The run hit `RunBudget.maxStitchesPerRun`.
    ///
    /// Not a failure and not an error — a `forever` program never terminates on
    /// its own, so the app owns the stop. The user is told, because a design that
    /// simply stopped with no explanation is indistinguishable from a bug.
    case stitchLimitReached
}

/// Where a run is. `idle` before the first play, `running` while the producer is
/// yielding, `finished` afterwards — carrying *why*, because all three reasons
/// need different words on screen and different accessibility labels.
///
/// The stage keeps rendering in `.finished`: the design stays on screen and stays
/// exportable. Catroid's precedent is the same — `StageListener.render()` calls
/// `stage.draw()` whenever `!finished`, regardless of pause — and it is what makes
/// "press stop and still have my design" true.
public enum RunState: Hashable, Sendable {
    case idle
    case running
    case finished(RunCompletion)

    /// Whether a run is in flight. Used by the control mapping and by `StageView`
    /// to decide whether to draw the needle at all — a needle parked on a
    /// finished design would imply the machine is still working on it.
    public var isRunning: Bool {
        self == .running
    }
}
