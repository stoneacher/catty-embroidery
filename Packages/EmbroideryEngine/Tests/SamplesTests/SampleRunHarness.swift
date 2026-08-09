import EmbroideryEngine
import Interpreter
import ProgramModel
import Samples

// Shared machinery for the US-301 sample suites: run a sample to completion and
// report everything the story's acceptance criteria measure. Nothing here is a
// suite member, so none of it counts toward a suite's type_body_length — the
// same arrangement, and the same reason, as InterpreterTests' GoldenProgramOracle.

/// ADR-018's M3 clock: one tick per frame at 60 fps, so a `wait(1)` brick
/// occupies 60 ticks. Every sample measurement in this target uses it, so the
/// tick counts the story pins are the ones the app will see.
let sampleClock = InterpreterClock(tickDelta: 1.0 / 60.0)

/// Everything one full run of a sample yields, measured once and shared.
struct SampleRun {
    /// Ticks consumed before `step()` reported `.finished`.
    var ticks: Int
    /// Every event, in emission order.
    var events: [InterpreterEvent]
    /// The per-tick event batches, kept separately because the story's per-tick
    /// stitch maximum is a property of the batching, not of the flat stream.
    var batches: [[InterpreterEvent]]
    /// The assembled stream — colour, dedup, interpolation and layer replay all
    /// applied by the engine (ADR-012/013/015/020).
    var stream: EmbroideryStream

    /// Total `.stitch` events. This counts *calls* to the pattern manager, which
    /// is what the story's "stitch-event count" means; the stream's own dedup may
    /// collapse consecutive duplicates, so `stream.count` can be smaller.
    var stitchEventCount: Int {
        events.count {
            if case .stitch = $0 {
                true
            } else {
                false
            }
        }
    }

    /// `.stitch` events per tick.
    var perTickStitchCounts: [Int] {
        batches.map { batch in
            batch.count {
                if case .stitch = $0 {
                    true
                } else {
                    false
                }
            }
        }
    }

    /// The number US-306's per-frame stitch budget is sized against.
    var perTickStitchMaximum: Int {
        perTickStitchCounts.max() ?? 0
    }

    /// The stitch positions in emission order, as the display list will see them
    /// (US-302 consumes exactly this projection).
    var stitchPositions: [StagePoint] {
        events.compactMap { event in
            if case let .stitch(_, position, _, _) = event {
                position
            } else {
                nil
            }
        }
    }
}

/// Steps `sample` to completion with the M3 clock.
///
/// `tickCap` is an assertion, not a policy: every sample is a bounded program, so
/// hitting the cap means the sample is wrong, not that it is long. Returning a
/// truncated run instead would let a runaway sample masquerade as a slow one.
func run(_ sample: SampleProgram, tickCap: Int = 10000) -> SampleRun {
    var interpreter = Interpreter(program: sample.program, clock: sampleClock)
    var batches: [[InterpreterEvent]] = []
    var ticks = 0

    while ticks < tickCap {
        switch interpreter.step() {
        case .finished:
            return SampleRun(
                ticks: ticks,
                events: batches.flatMap(\.self),
                batches: batches,
                stream: interpreter.assembledStream()
            )
        case let .ticked(batch):
            batches.append(batch)
            ticks += 1
        }
    }

    // Deliberately returns the truncated run rather than trapping: the caller is
    // a test, and a `ticks == tickCap` failure reads better than a crashed suite.
    return SampleRun(
        ticks: ticks,
        events: batches.flatMap(\.self),
        batches: batches,
        stream: interpreter.assembledStream()
    )
}

/// A design's extent in **stage points** — the unit ADR-007's 500 × 500 stage and
/// the story's ±250 criterion are stated in.
struct StageBounds {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double

    /// The largest absolute coordinate on either axis: the quantity the ±250
    /// criterion actually bounds.
    var extreme: Double {
        max(abs(minX), abs(maxX), abs(minY), abs(maxY))
    }
}

/// The design's bounding box in stage points. The stream holds machine units, so
/// this divides by the engine's own conversion factor rather than a re-typed 2.0.
func stageBounds(of stream: EmbroideryStream) -> StageBounds? {
    guard let box = stream.boundingBox else { return nil }
    let factor = EmbroideryPoint.stitchPointUnitFactor
    return StageBounds(
        minX: Double(box.min.x) / factor,
        maxX: Double(box.max.x) / factor,
        minY: Double(box.min.y) / factor,
        maxY: Double(box.max.y) / factor
    )
}

/// The design's extent in millimetres. One DST unit is 0.1 mm (ADR-005/ADR-007).
func extentInMillimetres(of stream: EmbroideryStream) -> (width: Double, height: Double)? {
    guard let box = stream.boundingBox else { return nil }
    return (
        width: Double(box.max.x - box.min.x) / 10.0,
        height: Double(box.max.y - box.min.y) / 10.0
    )
}
