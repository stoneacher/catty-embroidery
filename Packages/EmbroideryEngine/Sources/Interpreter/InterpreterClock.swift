/// The interpreter's injected logical clock (ADR-018). The interpreter advances
/// this clock by `tickDelta` once per tick; time-based bricks (`wait`) measure
/// their duration against it. There is **no wall-clock anywhere in the package** —
/// a test injects `InterpreterClock(tickDelta: 0.05)` and every run is
/// deterministic. Modelled as a value (not a protocol): only the delta varies,
/// never the behaviour, so an existential would fight `Sendable`/`Equatable` and
/// the "all state lives in the value" rule for `Interpreter`.
public struct InterpreterClock: Sendable, Equatable {
    /// Logical seconds advanced per tick.
    public let tickDelta: Double

    public init(tickDelta: Double) {
        self.tickDelta = tickDelta
    }
}
