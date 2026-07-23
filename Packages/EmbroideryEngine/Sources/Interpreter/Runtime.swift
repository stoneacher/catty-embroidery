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
    var finished = false
}
