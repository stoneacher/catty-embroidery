import EmbroideryEngine
import Interpreter
import ProgramModel

// Shared machinery for the M2 exit-criterion golden programs (US-207 square,
// US-208 star): program builders plus the differential replay. Nothing here is a
// suite member, so none of it counts toward a suite's type_body_length. The
// *independent* hand-derived half lives in GoldenSquareLiterals.swift, kept apart
// on purpose.

// MARK: - Program builders

/// The shape of a closed regular-polygon embroidery program: `sides: 4, turn: 90`
/// is US-207's square, `sides: 5, turn: 144` US-208's star.
struct PolygonSpec {
    var sides: Int
    var side: Double
    var turn: Double
    /// The pattern activator — `runningStitch` here, zigzag or triple in US-208.
    ///
    /// This and the pattern handed to `polygonOps(_:pattern:)` are two unlinked
    /// expressions of one fact. A mismatch shows up as a red differential test
    /// here, but US-208 must be careful: if the interpreter's `zigZagStitch`
    /// dispatch transposed length and width *and* the oracle's pattern was
    /// constructed with the same transposition, both halves would agree and only
    /// the hand-derived literals would catch it (swift-code-reviewer US-207).
    var patternBrick: Brick
    var hex: String
    /// The DST design name (≤15 chars, ADR-012).
    var designName: String
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
/// US-208 needs a *differing* `setThreadColor` mid-program; that will want an
/// insertion point here and in `polygonOps` (this shape has none).
func polygonProgram(_ spec: PolygonSpec) -> Program {
    let script = Script(header: .whenStarted, bricks: [
        .setThreadColor(hex: spec.hex),
        spec.patternBrick,
        .repeatLoop(times: .number(Double(spec.sides))),
        .moveNSteps(.number(spec.side)),
        .turnRight(.number(spec.turn)),
        .loopEnd,
        .sewUp,
        .writeEmbroideryToFile(name: spec.designName)
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

// MARK: - US-207: the square

/// US-207's square: side 20 stage units at stitch length 5 — exactly four stitch
/// intervals per side, so every interpolant lands on a whole stage unit — sewn in
/// green, tied off, finalized as "square".
enum GoldenSquare {
    static let length = 5.0
    static let hex = "#00ff00"
    static let designName = "square"
    static let color = ThreadColor(red: 0, green: 255, blue: 0)
    static let actor = ActorID(0)
    static let layer = 0

    static let spec = PolygonSpec(
        sides: 4,
        side: 20,
        turn: 90,
        patternBrick: .runningStitch(length: .number(length)),
        hex: hex,
        designName: designName
    )

    /// The program as the golden runs it: object at the stage origin, heading 0.
    static var program: Program {
        polygonProgram(spec)
    }

    /// The same square sewn by an object with a non-default start state. Used to
    /// pin the `Object` → `ObjectRuntime` seam (`startX`/`startY`/`startHeading` →
    /// `VirtualNeedle`, `zIndex` → layer) and the claim that a pattern activates at
    /// the *current* needle position: none of that is observable from a program
    /// that begins at the origin facing up on layer 0 (swift-code-reviewer US-207
    /// proved `startHeading` had no killing test anywhere in the package).
    static let displacedStart = StagePoint(x: -20, y: -20)
    static let displacedHeading = 90.0
    static let displacedLayer = 3

    static var displacedProgram: Program {
        var program = polygonProgram(spec)
        program.scenes[0].objects[0].startX = displacedStart.x
        program.scenes[0].objects[0].startY = displacedStart.y
        program.scenes[0].objects[0].startHeading = displacedHeading
        program.scenes[0].objects[0].zIndex = displacedLayer
        return program
    }

    /// Recomputed per access (a `static var`, not a `let`): parallel Swift Testing
    /// runs must not share the replay's mutable pattern state.
    static var oracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: actor, layer: layer)
    }

    /// The square sewn by the **second** object of a scene, the first being inert.
    /// `ActorID` is the global object index (ADR-018), so every event must carry
    /// `ActorID(1)` while the assembled stream is unchanged — the discriminator for
    /// an interpreter that hardcodes actor 0 into its events (Codex US-207 round 2).
    static let secondActor = ActorID(1)

    static var secondObjectProgram: Program {
        let stitcher = polygonProgram(spec).scenes[0].objects[0]
        return Program(scenes: [Scene(objects: [Object(name: "inert"), stitcher])])
    }

    static var secondObjectOracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: StagePoint(x: 0, y: 0))
        return replayGoldenProgram(polygonOps(spec, pattern: pattern), actor: secondActor, layer: layer)
    }

    static var displacedOracle: GoldenReplay {
        let pattern = RunningStitchPattern(length: length, start: displacedStart)
        return replayGoldenProgram(
            polygonOps(spec, pattern: pattern),
            start: displacedStart,
            heading: displacedHeading,
            actor: actor,
            layer: displacedLayer
        )
    }
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
/// the pattern activation, `sides × [move, turn]`, the tack, the finalize marker.
/// `repeatLoop` and `loopEnd` are excluded because they are zero-tick (ADR-018) —
/// so this is also the program's tick count, which is what makes the zero-tick
/// bookkeeping self-documenting rather than a bare literal.
func actionBrickCount(_ spec: PolygonSpec) -> Int {
    // setThreadColor, the pattern activation, sewUp, writeEmbroideryToFile.
    let fixed = 4
    return fixed + 2 * spec.sides // move + turn per side
}
