import EmbroideryEngine

/// Per-object runtime state — **shared across every one of that object's
/// scripts** (Catroid: all a sprite's scripts steer the same sprite). Keeping the
/// needle and variable store here, not on the thread, is what makes two scripts
/// driving one object interleave brick-by-brick (ADR-018).
struct ObjectRuntime: Sendable {
    var needle: VirtualNeedle
    var variables: [String: Double]
    let actorID: ActorID
    let layer: Int
}

/// Per-script execution state (Catroid: one `ScriptSequenceAction` thread). The
/// instruction pointer and (later) loop/wait bookkeeping are thread-local; the
/// needle and variables it reads and writes live on the shared `ObjectRuntime`.
struct ScriptThread: Sendable {
    let objectIndex: Int
    let instructions: [Instruction]
    var instructionPointer = 0
    /// Remaining iterations per open `repeatLoop`, keyed by the `repeatBegin`'s
    /// instruction index. A missing entry means "not yet initialized"; the entry
    /// is cleared when the loop exits so a nesting outer loop reinitializes it.
    var loopCounters: [Int: Int] = [:]
    /// Non-nil while a `wait` brick is blocking this thread. `nil` means the wait
    /// has not started (its duration is resolved lazily on first arrival).
    var wait: WaitState?
    var finished = false
}

/// A `wait` brick's progress against the logical clock (ADR-018). `duration` is
/// resolved once, on the tick the wait is first reached; `elapsed` accumulates
/// `tickDelta` per tick until it reaches `duration` (Catroid `TemporalAction`).
struct WaitState: Sendable {
    var duration: Double
    var elapsed: Double
}
