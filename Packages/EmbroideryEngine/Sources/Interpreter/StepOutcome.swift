/// The result of one `Interpreter.step()`: either the program advanced one tick
/// (carrying the events produced, possibly none) or every runnable thread has
/// finished. `run(maxTicks:)` is the concatenation of the `.ticked` batches, so
/// consuming step-by-step and consuming in one batch agree (M2 exit criterion).
public enum StepOutcome: Equatable, Sendable {
    /// The program advanced one tick, producing these events in execution order.
    case ticked([InterpreterEvent])
    /// No runnable thread remains; further `step()` calls stay `.finished`.
    case finished
}
