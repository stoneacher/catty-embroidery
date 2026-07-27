import EmbroideryEngine
import Interpreter
import ProgramModel

// Shared machinery for the M2 exit-criterion golden programs (US-207 square,
// US-208 star): program builders plus the differential replay. Nothing here is a
// suite member, so none of it counts toward a suite's type_body_length.
//
// Each program contributes two more files, kept apart on purpose:
// `Golden<Name>Oracle` binds this machinery to that program's parameters, and
// `Golden<Name>Literals` holds the hand-derived expectations that owe nothing to
// this replay. Collapsing a literals file into its oracle would turn a
// two-sided golden into a one-sided one.

// MARK: - Program builders

/// A second `setThreadColor` executed partway through the walk (US-208). It sits
/// *between* two `repeatLoop`s rather than inside one body, so it executes
/// exactly once and the colour partition of the stream is unambiguous.
/// Both fields carry invariants `polygonProgram` asserts: the hex must differ
/// from `PolygonSpec.hex` (ADR-015 makes a same-colour set a no-op that arms
/// nothing), and `afterSides` must fall strictly inside the walk — 0 would put
/// the set before any emission, where ADR-015's silent-start branch swallows it,
/// and `sides` would build an inert `repeatLoop(0)` second loop.
struct MidProgramColor {
    var hex: String
    /// How many sides the first loop walks; the second loop walks the rest.
    var afterSides: Int
}

/// The shape of a closed regular-polygon embroidery program: `sides: 4, turn: 90`
/// is US-207's square, `sides: 5, turn: 144` US-208's star.
struct PolygonSpec {
    var sides: Int
    var side: Double
    var turn: Double
    /// The pattern activator — `runningStitch` for the square, `zigZagStitch`
    /// for the star.
    ///
    /// This and the pattern handed to `polygonOps(_:pattern:)` are two unlinked
    /// expressions of one fact, so a mismatch between them shows up as a red
    /// differential test here. US-208 keeps `length != width` so that a
    /// length/width transposition in the `zigZagStitch` dispatch is observable
    /// at all — with equal values it would be invisible everywhere.
    ///
    /// Note what the unlinking does *not* uniquely buy, since two drafts
    /// overstated it (Codex US-208 rounds 2–3): a transposition in the dispatch
    /// alone is caught by the differential half too, and even a *coordinated*
    /// one — dispatch and oracle constructor together — is caught by the
    /// structural assertions, because 20/4 and 20/5 are different interval
    /// counts, so the per-side and event totals move. What the hand-derived
    /// literals uniquely caught, mutation-measured in US-208, are the four
    /// pattern-internal errors the differential half mirrors: anchor emitted raw
    /// instead of offset, `direction` reset per update, interior midpoints not
    /// `javaRound`ed, and the final clamp rounded instead of raw.
    var patternBrick: Brick
    var hex: String
    /// The DST design name (≤15 chars, ADR-012).
    var designName: String
    /// Absent for a single-colour, single-loop walk (US-207's square).
    var midColor: MidProgramColor?
}

/// Builds the program: set a thread color, activate the pattern, walk the edges
/// in a **compiled** `repeatLoop` (`moveNSteps` / `turnRight` per iteration), tie
/// off with `sewUp`, request finalization.
///
/// The loop is deliberately expressed as `repeatLoop`/`loopEnd` (ADR-008 paired
/// control) rather than an unrolled brick list — the golden then proves loop
/// *compilation*, since the oracle below walks a plain Swift `for` instead.
///
/// `header: .whenStarted` is passed explicitly rather than relying on `Script`'s
/// default: the hat brick is named in the story's AC, so it should be visible.
///
/// A `spec.midColor` splits the walk into **two** compiled loops with the colour
/// brick between them (US-208), which is the only shape that executes the brick
/// exactly once and so partitions the stream unambiguously by colour. It gives
/// the compiler a second, independently counted loop, but claim nothing more
/// than that: the two loops are *sequential* and `enterRepeat` clears a counter
/// on exhaustion, so keying `loopCounters` globally instead of per loop pointer
/// behaves identically here. Only *nesting* discriminates the keying, and
/// `StepperLoopTests` owns that (swift-code-reviewer US-208, mutation-proven).
func polygonProgram(_ spec: PolygonSpec) -> Program {
    var bricks: [Brick] = [.setThreadColor(hex: spec.hex), spec.patternBrick]
    if let midColor = spec.midColor {
        // Both invariants below are load-bearing for ADR-015; nothing downstream
        // would fail loudly if they were violated, so fail here instead.
        //
        // Compared as parsed colours, not as strings: "#ff0000" and "#FF0000"
        // differ as text but are the same `ThreadColor`, so a string comparison
        // would pass while ADR-015 armed nothing. A hex that fails to parse is
        // the same failure by another route — malformed input is a full no-op
        // (ADR-015) (Codex US-208 round 3).
        let midThreadColor = ThreadColor(hexString: midColor.hex)
        precondition(midThreadColor != nil, "a malformed hex is an ADR-015 no-op and arms nothing")
        precondition(
            midThreadColor != ThreadColor(hexString: spec.hex),
            "a same-colour set is an ADR-015 no-op and arms nothing"
        )
        precondition((1 ..< spec.sides).contains(midColor.afterSides), "the colour set must fall between sides")
        bricks += walkLoop(sides: midColor.afterSides, spec: spec)
        bricks.append(.setThreadColor(hex: midColor.hex))
        bricks += walkLoop(sides: spec.sides - midColor.afterSides, spec: spec)
    } else {
        bricks += walkLoop(sides: spec.sides, spec: spec)
    }
    bricks += [.sewUp, .writeEmbroideryToFile(name: spec.designName)]
    return Program(scenes: [Scene(objects: [Object(scripts: [Script(header: .whenStarted, bricks: bricks)])])])
}

/// One `repeatLoop`/`loopEnd` pair walking `sides` edges (ADR-008 paired control,
/// deliberately not an unrolled brick list — the golden then proves loop
/// *compilation*, since the oracle walks a plain Swift `for` instead).
private func walkLoop(sides: Int, spec: PolygonSpec) -> [Brick] {
    [
        .repeatLoop(times: .number(Double(sides))),
        .moveNSteps(.number(spec.side)),
        .turnRight(.number(spec.turn)),
        .loopEnd
    ]
}

/// The matching `GoldenOp` script — the same walk, minus every interpreter
/// concern: no compiled loop, just a Swift `for`, and the mid-program colour
/// dropped in by counting sides rather than by compiling a second loop.
func polygonOps(_ spec: PolygonSpec, pattern: any StitchPattern) -> [GoldenOp] {
    var ops: [GoldenOp] = [.setColor(spec.hex), .activate(pattern)]
    for side in 0 ..< spec.sides {
        if let midColor = spec.midColor, side == midColor.afterSides {
            ops.append(.setColor(midColor.hex))
        }
        ops.append(.move(spec.side))
        ops.append(.turn(spec.turn))
    }
    ops.append(.sewUp)
    ops.append(.finalize(spec.designName))
    return ops
}

// MARK: - Differential oracle

/// What a replay produces: the stitch points in emission order, the full expected
/// event stream, and the assembled stream. A struct rather than a tuple so the
/// three members stay named at every call site.
struct GoldenReplay {
    var points: [StagePoint]
    var events: [InterpreterEvent]
    var stream: EmbroideryStream
}

/// One step of a golden program, in the order the interpreter executes it.
enum GoldenOp {
    case activate(any StitchPattern)
    case move(Double)
    case turn(Double)
    case setColor(String)
    case sewUp
    case finalize(String)
}

/// Replays `ops` straight through the engine primitives — `VirtualNeedle`
/// (US-204), the `RunningStitch` lifecycle wrapper and its pattern (US-107/108/
/// 109), `SewUp` (US-109) and `EmbroideryPatternManager` (US-110) — and returns
/// the stitch points in emission order, the **full expected event stream with
/// every payload** (so a wrong `actor` or `layer` on a `.stitch` cannot slip
/// through a positions-only comparison), and the assembled stream.
///
/// This is a **differential** oracle, not an independent model: it shares the
/// engine code with the interpreter, so it cannot catch a bug *inside* those
/// primitives. What it does catch is everything the interpreter adds on top —
/// script compilation, loop counting, tick scheduling, brick dispatch, and the
/// model↔engine conversions — because the replay has **no compiler, no
/// scheduler and no loop counter**: a miscompiled `repeatLoop` cannot be
/// mirrored into the expectation. The hand-derived literals in the suites are
/// the independent half of the golden.
///
/// Faithfulness details that matter and are easy to lose:
/// - the pattern is fed after **every** motion, turns included (US-206 pinned
///   the feed as per motion brick, not per `moveNSteps`) — a turn's
///   zero-distance update must produce nothing;
/// - `NeedleUpdate` carries the heading as well as the position, because
///   `ZigzagStitchPattern` consumes it (US-208);
/// - `sewUp` goes through the real `SewUp.perform(at:heading:runningStitch:)`
///   rather than a simulated 5-point list. Note what that does *not* buy: in a
///   program whose tack is the last stitching brick, the re-anchor is a no-op
///   (the centre already equals the pattern anchor) and `resume()` has no
///   following motion to affect — deleting either from `SewUp` leaves US-207
///   green, and only `SewUpTests` catches it (swift-code-reviewer US-207,
///   mutation-proven). Making the seam observable would need a motion brick
///   after `sewUp`, which the story's program does not have.
func replayGoldenProgram(
    _ ops: [GoldenOp],
    start: StagePoint = StagePoint(x: 0, y: 0),
    heading: Double = 0,
    actor: ActorID = ActorID(0),
    layer: Int = 0
) -> GoldenReplay {
    var needle = VirtualNeedle(position: start, heading: heading)
    var wrapper = RunningStitch()
    var manager = EmbroideryPatternManager()
    var points: [StagePoint] = []
    var events: [InterpreterEvent] = []

    func emit(_ produced: [StagePoint]) {
        for point in produced {
            points.append(point)
            events.append(.stitch(actor: actor, position: point, layer: layer))
            manager.addStitch(at: point, layer: layer, actor: actor)
        }
    }
    /// A motion brick emits its one `needleMoved` first, then whatever the
    /// pattern produced from that update (`Interpreter+Step.perform`).
    func moveAndFeed(_ mutate: (inout VirtualNeedle) -> Void) {
        mutate(&needle)
        let update = NeedleUpdate(position: needle.position, heading: needle.heading)
        events.append(.needleMoved(actor: actor, update: update))
        emit(wrapper.update(update))
    }

    for operation in ops {
        switch operation {
        case let .activate(pattern):
            wrapper.activate(pattern)
        case let .move(steps):
            moveAndFeed { $0.moveNSteps(steps) }
        case let .turn(degrees):
            moveAndFeed { $0.turnRight(degrees) }
        case let .setColor(hex):
            manager.setThreadColor(hexString: hex, for: actor)
            events.append(.colorArmed(actor: actor, hex: hex))
        case .sewUp:
            emit(SewUp.perform(at: needle.position, heading: needle.heading, runningStitch: &wrapper))
        case let .finalize(name):
            events.append(.finalizeRequested(name: name))
        }
    }
    return GoldenReplay(points: points, events: events, stream: manager.assembled())
}

// MARK: - Consumer-side reconstruction

/// Rebuilds an embroidery stream from an event sequence **alone**, the way a
/// downstream consumer (M3's live preview, an exporter) has to: replay each
/// `colorArmed` and `stitch` event's own payload into a fresh manager, using the
/// actor and layer the event carries rather than any outside knowledge.
///
/// This is what makes the events a *sufficient* description of the stitch output
/// rather than a mere side channel (Codex US-207 round 1).
///
/// What it does **not** discriminate, corrected in round 2: a *uniform* payload
/// relabelling. `EmbroideryStream` keeps no absolute layer numbers, so moving every
/// stitch event from layer 0 to layer −1 rebuilds byte-identically (one layer is
/// still one layer), and relabelling every actor consistently keeps a one-actor
/// stream one-actor. Those are the whole-event comparison's job. This test pins
/// that the event stream is *sufficient*; the oracle pins that each payload is
/// *right*.
func streamRebuiltFromEvents(_ events: [InterpreterEvent]) -> EmbroideryStream {
    var manager = EmbroideryPatternManager()
    for event in events {
        switch event {
        case let .colorArmed(actor, hex):
            manager.setThreadColor(hexString: hex, for: actor)
        case let .stitch(actor, position, layer):
            manager.addStitch(at: position, layer: layer, actor: actor)
        case .needleMoved, .waited, .finalizeRequested:
            continue // carry no stream effect of their own
        }
    }
    return manager.assembled()
}

/// The number of *action-producing* bricks in a polygon program: the colour set,
/// the pattern activation, `sides × [move, turn]`, the tack, the finalize marker,
/// plus the mid-program colour set when there is one. `repeatLoop` and `loopEnd`
/// are excluded because they are zero-tick (ADR-018) — so this is also the
/// program's tick count, which is what makes the zero-tick bookkeeping
/// self-documenting rather than a bare literal, and it stays true across the
/// star's *two* loops.
func actionBrickCount(_ spec: PolygonSpec) -> Int {
    // setThreadColor, the pattern activation, sewUp, writeEmbroideryToFile.
    let fixed = 4 + (spec.midColor == nil ? 0 : 1)
    return fixed + 2 * spec.sides // move + turn per side
}
