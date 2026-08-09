import EmbroideryEngine
import Interpreter
import Testing

// Shared helpers for the embroidery stepper suites. Free functions (not suite
// methods) so they don't count toward any one suite's type_body_length.

/// The stitch positions, in emission order, from an interpreter event stream.
func stitchPositions(_ events: [InterpreterEvent]) -> [StagePoint] {
    events.compactMap {
        if case let .stitch(_, position, _, _) = $0 {
            position
        } else {
            nil
        }
    }
}

/// The stitch colors, in emission order — the ADR-021 payload the app renders
/// from, so the app never re-derives ADR-015's rules for itself.
func stitchColors(_ events: [InterpreterEvent]) -> [ThreadColor] {
    events.compactMap {
        if case let .stitch(_, _, _, color) = $0 {
            color
        } else {
            nil
        }
    }
}

/// The stitch positions of an assembled stream, in embroidery units.
func recordPositions(_ stream: EmbroideryStream) -> [EmbroideryPoint] {
    stream.stitches.map(\.position)
}

/// Event kinds in emission order — pins the *interleaving* of motion, stitches
/// and markers (which `stitchPositions` discards) without spelling out payloads.
func eventTags(_ events: [InterpreterEvent]) -> [String] {
    events.map {
        switch $0 {
        case .needleMoved: "move"
        case .waited: "wait"
        case .stitch: "stitch"
        case .colorArmed: "color"
        case .finalizeRequested: "finalize"
        }
    }
}

/// Zero-tolerance `[StagePoint]` comparison with index-level diagnostics. Distinct
/// from `expectApproximates`: used where both sides run the *same* engine calls
/// with the same operands, so trig dust agrees exactly and a tolerance would erase
/// the very residue a golden may depend on (US-207).
///
/// This is `Equatable` equality, not bit-pattern identity (Codex US-207 round 2):
/// `-0.0 == +0.0` passes and two NaNs never compare equal. Neither matters under
/// the pinned semantics — ADR-014 rejects non-finite pattern updates, and
/// signed-zero differences are invisible after the ×2/`javaRound` conversion.
func expectExactlyEqual(
    _ actual: [StagePoint],
    _ expected: [StagePoint],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard actual.count == expected.count else {
        Issue.record(
            "expected \(expected.count) points \(expected), got \(actual)",
            sourceLocation: sourceLocation
        )
        return
    }
    for (index, pair) in zip(actual, expected).enumerated() {
        #expect(pair.0 == pair.1, "point \(index): \(pair.0) != \(pair.1)", sourceLocation: sourceLocation)
    }
}

/// Drives `interpreter` one tick at a time to completion, returning each tick's
/// batch separately so the per-tick profile stays assertable. Program-agnostic,
/// so it is shared by every golden-program consumption suite (US-207, US-208).
func stepToCompletion(_ interpreter: inout Interpreter) -> [[InterpreterEvent]] {
    var batches: [[InterpreterEvent]] = []
    while case let .ticked(batch) = interpreter.step() {
        batches.append(batch)
    }
    return batches
}

/// The `colorArmed` hex intents, in order.
func colorArmedHexes(_ events: [InterpreterEvent]) -> [String] {
    events.compactMap {
        if case let .colorArmed(_, hex) = $0 {
            hex
        } else {
            nil
        }
    }
}

/// Approximate stage-point comparison per ADR-014 — the zigzag/sew-up offsets go
/// through `sin`/`cos`, whose Double results carry transcendental dust, so exact
/// `==` cannot hold (mirrors the engine test helper).
func expectApproximates(
    _ actual: [StagePoint],
    _ expected: [StagePoint],
    tolerance: Double = 1e-9,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    guard actual.count == expected.count else {
        Issue.record(
            "expected \(expected.count) points \(expected), got \(actual)",
            sourceLocation: sourceLocation
        )
        return
    }
    for (index, pair) in zip(actual, expected).enumerated() {
        #expect(
            abs(pair.0.x - pair.1.x) <= tolerance && abs(pair.0.y - pair.1.y) <= tolerance,
            "point \(index): \(pair.0) !≈ \(pair.1)",
            sourceLocation: sourceLocation
        )
    }
}
