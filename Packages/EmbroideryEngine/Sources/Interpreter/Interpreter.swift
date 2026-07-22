import EmbroideryEngine
import ProgramModel

/// Runs a `Program` headlessly, one tick at a time, against an injected logical
/// clock (ADR-016, ADR-018). The `Interpreter` target is the only place the
/// program model and the embroidery engine meet: it maps `ProgramModel` objects
/// onto engine actors (object → `ActorID`, `zIndex` → layer), converts plain
/// `Double` positions to `StagePoint`, and (from US-206) parses hex colors.
///
/// A pure value type: all execution state — per-object needle and variable
/// store, per-thread program counters, loop counters, wait state, and the clock
/// cursor — lives inside the value. No globals, no reference types, so a caller
/// can snapshot or replay a run by copying the value. `run(maxTicks:)` equals the
/// concatenation of `step()` batches (the M2 exit-criterion equivalence).
public struct Interpreter: Sendable {
    private let clock: InterpreterClock

    public init(program _: Program, clock: InterpreterClock) {
        self.clock = clock
    }

    /// Advances every runnable thread by one tick, returning the events produced
    /// in execution order, or `.finished` once no runnable thread remains.
    public mutating func step() -> StepOutcome {
        .finished
    }

    /// Advances up to `maxTicks` ticks, returning every event produced, in order.
    /// Stops early once finished; `maxTicks <= 0` returns `[]`.
    public mutating func run(maxTicks _: Int) -> [InterpreterEvent] {
        []
    }

    /// `true` once no runnable thread remains.
    public var isFinished: Bool {
        true
    }
}
