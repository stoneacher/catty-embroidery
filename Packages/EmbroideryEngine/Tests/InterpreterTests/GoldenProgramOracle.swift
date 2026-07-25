import EmbroideryEngine
import Interpreter
import ProgramModel

// Shared machinery for the M2 exit-criterion golden programs (US-207 square,
// US-208 star). Free functions and file-scope constants, like
// EmbroideryStepperTestSupport.swift, so nothing here counts toward a suite's
// type_body_length.

// MARK: - Program builders

/// The shape of a closed regular-polygon embroidery program: `sides: 4, turn: 90`
/// is US-207's square, `sides: 5, turn: 144` US-208's star.
struct PolygonSpec {
    var sides: Int
    var side: Double
    var turn: Double
    /// The pattern activator — `runningStitch` here, zigzag or triple in US-208.
    var patternBrick: Brick
    var hex: String
    var name: String
}

/// Builds the program: set a thread color, activate the pattern, walk the edges
/// in a **compiled** `repeatLoop` (`moveNSteps` / `turnRight` per iteration), tie
/// off with `sewUp`, request finalization.
///
/// The loop is deliberately expressed as `repeatLoop`/`loopEnd` (ADR-008 paired
/// control) rather than an unrolled brick list — the golden then proves loop
/// *compilation*, since the oracle below walks a plain Swift `for` instead.
func polygonProgram(_ spec: PolygonSpec) -> Program {
    let script = Script(bricks: [
        .setThreadColor(hex: spec.hex),
        spec.patternBrick,
        .repeatLoop(times: .number(Double(spec.sides))),
        .moveNSteps(.number(spec.side)),
        .turnRight(.number(spec.turn)),
        .loopEnd,
        .sewUp,
        .writeEmbroideryToFile(name: spec.name)
    ])
    return Program(scenes: [Scene(objects: [Object(scripts: [script])])])
}

/// The matching `GoldenOp` script — the same walk, minus every interpreter
/// concern: no compiled loop, just a Swift `for`.
func polygonOps(_ spec: PolygonSpec, pattern: any StitchPattern) -> [GoldenOp] {
    var ops: [GoldenOp] = [.setColor(spec.hex), .activate(pattern)]
    for _ in 0 ..< spec.sides {
        ops.append(.move(spec.side))
        ops.append(.turn(spec.turn))
    }
    ops.append(.sewUp)
    return ops
}

// MARK: - Differential oracle

/// One step of a golden program, in the order the interpreter executes it.
enum GoldenOp {
    case activate(any StitchPattern)
    case move(Double)
    case turn(Double)
    case setColor(String)
    case sewUp
}

/// Replays `ops` straight through the engine primitives — `VirtualNeedle`
/// (US-204), the `RunningStitch` lifecycle wrapper and its pattern (US-107/108/
/// 109), `SewUp` (US-109) and `EmbroideryPatternManager` (US-110) — and returns
/// both the stitch points in emission order and the assembled stream.
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
/// - `sewUp` goes through the real `SewUp.perform(at:heading:runningStitch:)`,
///   so the pause / re-anchor / resume seam is exercised, not simulated.
func replayGoldenProgram(
    _ ops: [GoldenOp],
    start: StagePoint = StagePoint(x: 0, y: 0),
    heading: Double = 0,
    actor: ActorID = ActorID(0),
    layer: Int = 0
) -> (points: [StagePoint], stream: EmbroideryStream) {
    var needle = VirtualNeedle(position: start, heading: heading)
    var wrapper = RunningStitch()
    var manager = EmbroideryPatternManager()
    var points: [StagePoint] = []

    func emit(_ produced: [StagePoint]) {
        for point in produced {
            points.append(point)
            manager.addStitch(at: point, layer: layer, actor: actor)
        }
    }
    func feedPattern() {
        emit(wrapper.update(NeedleUpdate(position: needle.position, heading: needle.heading)))
    }

    for operation in ops {
        switch operation {
        case let .activate(pattern):
            wrapper.activate(pattern)
        case let .move(steps):
            needle.moveNSteps(steps)
            feedPattern()
        case let .turn(degrees):
            needle.turnRight(degrees)
            feedPattern()
        case let .setColor(hex):
            manager.setThreadColor(hexString: hex, for: actor)
        case .sewUp:
            emit(SewUp.perform(at: needle.position, heading: needle.heading, runningStitch: &wrapper))
        }
    }
    return (points, manager.assembled())
}

// MARK: - US-207: the square

/// US-207's square: side 20 stage units at stitch length 5 — exactly four stitch
/// intervals per side, so every interpolant lands on a whole stage unit — sewn in
/// green, tied off, finalized as "square".
enum GoldenSquare {
    static let length = 5.0
    static let hex = "#00ff00"
    static let name = "square"
    static let color = ThreadColor(red: 0, green: 255, blue: 0)
    static let actor = ActorID(0)
    static let layer = 0

    static let spec = PolygonSpec(
        sides: 4,
        side: 20,
        turn: 90,
        patternBrick: .runningStitch(length: .number(length)),
        hex: hex,
        name: name
    )

    static var program: Program {
        polygonProgram(spec)
    }

    static var oracle: (points: [StagePoint], stream: EmbroideryStream) {
        let pattern = RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: actor, layer: layer)
    }
}

/// The square's stream in embroidery units, derived **by hand** from ADR-007/012
/// geometry — the independent half of the golden, owing nothing to the replay.
///
/// A 20×20 stage square at length 5 is 4 intervals per side, ×2 into embroidery
/// units → a 40×40 square walked clockwise from the origin (heading 0 is +y and
/// `turnRight` adds): up the +y edge, right, down, back left. 17 path points (the
/// lazy anchor plus 4 sides × 4 interpolants) then the 5-point bar tack at the
/// closing corner, ±6 units along heading 0 — hence the y = −6 record.
///
/// The tack's leading centre is **not** deduped, so this list has 22 entries and
/// not 21: see `tackCentreCarriesDust` for why.
let goldenSquareRecords: [EmbroideryPoint] = [
    // Side 1 — the lazy anchor, then up +y.
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 10),
    EmbroideryPoint(x: 0, y: 20), EmbroideryPoint(x: 0, y: 30), EmbroideryPoint(x: 0, y: 40),
    // Side 2 — right, +x.
    EmbroideryPoint(x: 10, y: 40), EmbroideryPoint(x: 20, y: 40),
    EmbroideryPoint(x: 30, y: 40), EmbroideryPoint(x: 40, y: 40),
    // Side 3 — down, −y.
    EmbroideryPoint(x: 40, y: 30), EmbroideryPoint(x: 40, y: 20),
    EmbroideryPoint(x: 40, y: 10), EmbroideryPoint(x: 40, y: 0),
    // Side 4 — left, −x, closing on the origin.
    EmbroideryPoint(x: 30, y: 0), EmbroideryPoint(x: 20, y: 0),
    EmbroideryPoint(x: 10, y: 0), EmbroideryPoint(x: 0, y: 0),
    // Sew-up bar tack: centre / ahead / centre / behind / centre, heading 0.
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: 6),
    EmbroideryPoint(x: 0, y: 0), EmbroideryPoint(x: 0, y: -6), EmbroideryPoint(x: 0, y: 0)
]

/// Events per tick, hand-derived from ADR-018 tick accounting: `setThreadColor`
/// (one `colorArmed`), `runningStitch` (action-consuming but event-free), then
/// eight loop-body ticks alternating move (one `needleMoved` + its stitches) and
/// turn (one `needleMoved`, no stitch), then `sewUp` (5 tack stitches) and
/// `writeEmbroideryToFile` (one `finalizeRequested`).
///
/// Twelve entries, because `repeatLoop` / `loopEnd` are zero-tick and fold into
/// the surrounding tick — the loop's exhaustion folds into tick 10 (the last
/// turn), so `sewUp` runs on tick 11 rather than sharing it.
let goldenSquareTickProfile = [1, 0, 6, 1, 5, 1, 5, 1, 5, 1, 5, 1]

/// The stitch positions from an assembled stream, for golden comparison.
func recordPositions(_ stream: EmbroideryStream) -> [EmbroideryPoint] {
    stream.stitches.map(\.position)
}

/// Event kinds in emission order — pins the *interleaving* of motion, stitches
/// and markers (which `stitchPositions` discards) without spelling out payloads.
/// `needleMoved` precedes the stitches its motion produced, per `perform`.
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

/// The square's event interleaving, hand-derived: the colour intent, then per
/// loop iteration a move carrying its stitches followed by a stitch-free turn,
/// then the bare 5-stitch tack and the finalize marker.
let goldenSquareEventTags: [String] =
    ["color"]
        + ["move"] + Array(repeating: "stitch", count: 5) + ["move"] // side 1 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 2 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 3 + turn
        + ["move"] + Array(repeating: "stitch", count: 4) + ["move"] // side 4 + turn
        + Array(repeating: "stitch", count: 5) // sew-up bar tack
        + ["finalize"]
