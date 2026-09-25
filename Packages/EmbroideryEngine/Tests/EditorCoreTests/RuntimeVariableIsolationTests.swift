import EditorCore
import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-404's second route to a non-finite value: `Variable.swift` says the
/// US-202 semantics let ±∞ reach a variable **at runtime**, and input rejection
/// cannot guard that. This suite executes the claim that the runtime value never
/// reaches the document, rather than inheriting it (ADR-032 invariant 4).
///
/// **What this can and cannot discriminate.** The witness — the needle landing
/// at `greatestFiniteMagnitude` — proves the runtime store really held `+∞`, so
/// the route is live and the scenario is not vacuous. The "program unchanged"
/// half cannot fail by construction: `Interpreter.init` takes `Program` by
/// value, copies values into its own `[String: Double]` stores, `Program` has no
/// reference-typed storage, and `Interpreter` has no API that writes a variable
/// back. The test records that proof; it is not counted as a mutation-proved
/// guard (ADR-037).
@Suite("Runtime variables never reach the document")
struct RuntimeVariableIsolationTests {
    /// `x` starts at MAX. `MAX + MAX` is `+∞` in the runtime store (the store is
    /// raw; only formula *leaves* normalize). `∞ − MAX` stays `+∞` — whereas a
    /// store that clamped to MAX would give `0` — and `setY(x)` normalizes the
    /// `+∞` leaf back to MAX. So the needle's `y` tells the two apart.
    static let program = Program(
        name: "overflow",
        scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            .changeVariableBy(name: "x", value: .number(.greatestFiniteMagnitude)),
            .changeVariableBy(name: "x", value: .unaryMinus(.number(.greatestFiniteMagnitude))),
            .setY(.variable("x"))
        ])])])],
        variables: [Variable(name: "x", value: .greatestFiniteMagnitude)]
    )

    @Test("a variable driven to +∞ at runtime leaves the authored program unchanged and encodable")
    func runtimeInfinityDoesNotReachTheDocument() throws {
        var interpreter = Interpreter(program: Self.program, clock: InterpreterClock(tickDelta: 0.05))
        let events = interpreter.run(maxTicks: 100)

        // Witness: the runtime value really was +∞.
        guard case let .needleMoved(_, update) = events.last else {
            Issue.record("expected the run to end on the setY motion, got \(events)")
            return
        }
        #expect(update.position.y == .greatestFiniteMagnitude)

        // The authored value is untouched, and the document still accepts it.
        #expect(Self.program.variables == [Variable(name: "x", value: .greatestFiniteMagnitude)])
        let data = try #require(try? ProgramDocument.encode(Self.program), "the authored program failed to encode")
        #expect(try ProgramDocument.decode(data) == Self.program)
    }
}
