import EmbroideryEngine
import Interpreter
import Testing

// Shared helpers for the embroidery stepper suites. Free functions (not suite
// methods) so they don't count toward any one suite's type_body_length.

/// The stitch positions, in emission order, from an interpreter event stream.
func stitchPositions(_ events: [InterpreterEvent]) -> [StagePoint] {
    events.compactMap {
        if case let .stitch(_, position, _) = $0 {
            position
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

/// Exact `[StagePoint]` comparison with index-level diagnostics. Distinct from
/// `expectApproximates`: used where both sides run the *same* engine calls with
/// the same operands, so trig dust matches bit for bit and a tolerance would
/// erase the very residue a golden may depend on (US-207).
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
