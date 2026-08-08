import EmbroideryEngine
import Foundation
import Interpreter
import Samples

// ADR-019 screening machinery. Non-suite by design (the GoldenProgramOracle
// arrangement), so none of it counts toward a suite's type_body_length.
//
// What is being measured, and why it is not ADR-014's 1e-9 coordinate tolerance:
// a stitch pattern decides *how many* points an update emits with
// `floor(distance / length)`. When the exact distance is a whole multiple of
// `length`, one ulp of `hypot` changes the emission **structure** — the count,
// the anchor's resting place, and every point after it. That is a discrete
// outcome with no tolerance. ADR-019's rule: the screening question is "is the
// nominal ratio integral", the *deciding* question is "how far is the exact
// distance from the boundary, in ulps, along the direction of motion".

/// One pattern update, as the engine actually performed it.
struct BoundaryProbe {
    /// Index of the move that produced this update, in execution order.
    var moveIndex: Int
    /// The distance the pattern measured — computed the way the pattern computes
    /// it, with libm's `hypot`.
    var distance: Double
    /// `floor(distance / length)`: the structural outcome.
    var intervals: Int
    /// Signed distance from the nearest whole multiple of `length`, in ulps of
    /// that multiple. Inside ±0.5 the outcome is decided by libm, not geometry.
    var ulpsFromBoundary: Double
    /// The same quantity in stage points, before the ulp conversion. Carried so a
    /// test can check the decomposition without having to reconstruct it from
    /// `ulpsFromBoundary` — that needs the *boundary's* ulp, and using the
    /// distance's instead is wrong whenever the two land in different binades.
    var residual: Double
    /// The residue's component **along** the direction of motion. Only this moves
    /// the distance to first order (ADR-019); the perpendicular part enters
    /// quadratically.
    var alongComponent: Double
    /// The quadratic contribution of the perpendicular residue. When this
    /// dominates `alongComponent` the update is safe for US-207's reason.
    var perpendicularContribution: Double

    /// Whether libm's rounding, rather than the geometry, decides this update's
    /// emission count.
    ///
    /// The band is ±1.5 ulp, not ADR-019's literal 0.5. 0.5 answers "what does a
    /// *correctly rounded* `hypot` return"; but ADR-019 measured Darwin's error at
    /// ~0.53 ulp on exactly these operands, so the band that predicts a
    /// *disagreement between implementations* is wider. Erring wide is the safe
    /// direction for a tripwire.
    var isDecidedByLibm: Bool {
        abs(ulpsFromBoundary) < 1.5 && !distanceIsExactlyOnBoundary
    }

    /// The exact distance is representable and lands exactly on the boundary.
    /// Safe, not at risk: returning the neighbouring `Double` would take a full
    /// ulp of error. US-207's square is this case, and so are several of the
    /// rosette's sides.
    var distanceIsExactlyOnBoundary: Bool {
        ulpsFromBoundary == 0
    }
}

/// The screening result for one sample.
struct Screening {
    var probes: [BoundaryProbe]

    /// How many stitch points the mirror says each needle-move tick emitted, in
    /// tick order and **including the zeros** — turns that moved the anchor
    /// nowhere still occupy a tick, and dropping them would let the comparison in
    /// `mirrorIsFaithful` line up two differently-shaped sequences by accident.
    var predictedEmissions: [Int] = []

    /// Updates whose emission count libm decides.
    var atRisk: [BoundaryProbe] {
        probes.filter(\.isDecidedByLibm)
    }

    /// The smallest margin any update has, in ulps.
    var minimumUlpsFromBoundary: Double {
        probes.filter { !$0.distanceIsExactlyOnBoundary }
            .map { abs($0.ulpsFromBoundary) }
            .min() ?? .infinity
    }

    /// The per-move interval counts, in execution order — the observable
    /// consequence a tripwire pins.
    var intervalCounts: [Int] {
        probes.map(\.intervals)
    }
}

// MARK: - Compensated arithmetic

/// `√(dx² + dy²)` as an unevaluated `head + tail`, using only operations IEEE-754
/// requires to be correctly rounded — `fma` (via `addingProduct`) and
/// `squareRoot()`.
///
/// `hypot` is deliberately **not** used: it is the quantity under test, and
/// measuring libm's error with libm would answer nothing. ADR-019's other lesson
/// applies too — US-208's first screen ran in Python, whose `hypot` is correctly
/// rounded where Darwin's is not, so it recommended parameters the engine
/// rejects. This runs in-process, against the same `Double`s the engine used.
func compensatedMagnitude(_ dx: Double, _ dy: Double) -> (head: Double, tail: Double) {
    let firstSquare = dx * dx
    let firstError = (-firstSquare).addingProduct(dx, dx) // exact error of dx*dx
    let secondSquare = dy * dy
    let secondError = (-secondSquare).addingProduct(dy, dy)

    let sum = firstSquare + secondSquare
    let bridge = sum - firstSquare
    // two-sum: sum + sumError == firstSquare + secondSquare exactly
    let sumError = ((firstSquare - (sum - bridge)) + (secondSquare - bridge)) + firstError + secondError

    let root = sum.squareRoot()
    guard root > 0 else { return (0, 0) }
    // sum.addingProduct(-root, root) is (sum - root²), exact via fma.
    return (root, (sum.addingProduct(-root, root) + sumError) / (2 * root))
}

/// ADR-019's deciding quantity for one move.
///
/// `head` and `boundary` are within a factor of two, so Sterbenz makes their
/// difference exact and the catastrophic cancellation is carried losslessly by
/// `tail`.
/// `intervals` is computed here rather than passed in, with the pattern's own
/// expression, so the probe and the emission it describes cannot disagree.
func boundaryProbe(
    moveIndex: Int,
    from anchor: StagePoint,
    to target: StagePoint,
    heading: Double,
    length: Double
) -> BoundaryProbe {
    let dx = target.x - anchor.x
    let dy = target.y - anchor.y
    let (head, tail) = compensatedMagnitude(dx, dy)

    let distance = hypot(dx, dy)
    let remainder = distance.truncatingRemainder(dividingBy: length)
    let intervals = Int(((distance - remainder) / length).rounded(.down))

    let multiple = Swift.max(1, (head / length).rounded())
    let boundary = length * multiple
    let residual = (head - boundary) + tail

    // Decompose against the nominal unit direction (ADR-007: x via sin, y via
    // cos, 0 degrees = up). Only the along part moves the distance to first order;
    // the perpendicular part enters quadratically.
    //
    // The along component is the *projection* minus the boundary, computed
    // directly. It is deliberately not inferred as `residual − perp²/(2·boundary)`:
    // that quadratic term is a small-angle approximation, and it is wrong as soon
    // as the perpendicular part is not small. Codex round 1's counterexample —
    // (0,0) → (3,4) at heading 0 against boundary 5 — has a true along component
    // of 4 − 5 = −1, where the approximation reports −0.9. The samples never leave
    // the small-angle regime, so no reported figure changes, but a screen whose
    // decomposition only works for the inputs it has seen is not a screen.
    let radians = heading.truncatingRemainder(dividingBy: 360) * .pi / 180
    let projection = dx * sin(radians) + dy * cos(radians)
    let alongComponent = projection - boundary

    return BoundaryProbe(
        moveIndex: moveIndex,
        distance: distance,
        intervals: intervals,
        ulpsFromBoundary: residual / boundary.ulp,
        residual: residual,
        alongComponent: alongComponent,
        // Whatever the along term does not account for. Defined as the remainder
        // so the two provably sum to the residual instead of nearly doing so.
        perpendicularContribution: residual - alongComponent
    )
}

// MARK: - Screening a sample

/// Screens every pattern update in `sample`.
///
/// **The operands come from the engine, not from a model of it** (ADR-019). The
/// walk is the real `Interpreter` driving the real `VirtualNeedle`; the emission
/// counts are the real `.stitch` events. Only the anchor is tracked here, using
/// the pattern's own surplus-strip expression — and `mirrorIsFaithful` proves
/// that tracking is right by checking the mirrored counts against the engine's
/// own, update for update. Without that check this would be exactly the
/// re-implementation ADR-019 warns about.
///
/// The premise US-208's tripwire relied on — that the anchor tracks the vertices,
/// so the needle's step length *is* the pattern's distance — **fails here**: once
/// a side emits one interval short, the anchor lags and the next distance is a
/// dogleg. Measuring `hypot` of the nominal step would find all 64 sides clean
/// and issue a false clean bill of health.
///
/// `pointsPerInterval` is the pattern's emission multiplier: 1 for the zigzag
/// (one offset point per interval) and 3 for the triple stitch (`point, previous,
/// point` per segment). It is what makes `predictedEmissions` comparable against
/// the engine's own per-tick counts.
///
/// **Known limitation, stated because it is currently invisible**: the mirror
/// models the pattern's *motion* anchor only. It does not model a re-anchor from
/// `sewUp` (which pauses the running stitch, calls `setStartPosition` on the tack
/// centre, and resumes) or from `stitch` / `stopRunningStitch`. That costs
/// nothing today — `sewUp` is a non-motion brick, so it emits no `.needleMoved`
/// and both sides of the comparison skip its tick, and in sample 2 it is the last
/// brick anyway, so its re-anchor has no successor to affect.
///
/// A future sample with a **mid-program** `sewUp` would break that, and the right
/// thing happens: `mirrorIsFaithful` compares every tick element by element, so
/// the divergence surfaces as a named red test rather than as a quietly wrong ulp
/// figure. If that happens, teach this function about the re-anchor — do not
/// relax the assertion.
func screen(_ sample: SampleProgram, patternLength: Double, pointsPerInterval: Int) -> Screening {
    let measured = run(sample)
    var probes: [BoundaryProbe] = []
    var predicted: [Int] = []
    var moveIndex = 0
    var isFirstEmission = true

    // Seed the anchor where the *engine* seeded it. Both samples activate their
    // pattern before any motion, and `performEmbroidery` hands the pattern the
    // needle's current position as its `start` — which at activation is still the
    // object's declared start. Taking the first `.needleMoved` as the anchor
    // instead drops the first side and leaves the anchor one move behind for the
    // rest of the run (it did, on the first version of this screen: 65 probes for
    // 64 sides, one of them a spurious dogleg).
    guard let origin = sample.program.scenes.first?.objects.first else {
        return Screening(probes: [])
    }
    var anchor = StagePoint(x: origin.startX, y: origin.startY)

    for batch in measured.batches {
        guard let move = batch.compactMap(needleMove(in:)).first else { continue }

        let target = move.position
        let current = anchor
        let dx = target.x - current.x
        let dy = target.y - current.y
        let distance = hypot(dx, dy)
        guard distance >= patternLength else {
            // A tick that moved the needle but not far enough to emit. Recorded
            // as a zero rather than skipped, so the predicted sequence stays
            // aligned with the engine's tick-by-tick counts.
            predicted.append(0)
            continue
        }

        let remainder = distance.truncatingRemainder(dividingBy: patternLength)
        probes.append(boundaryProbe(
            moveIndex: moveIndex,
            from: current,
            to: target,
            heading: move.heading,
            length: patternLength
        ))
        // Both patterns emit their anchor point once, on the first update that
        // passes the distance guard — the zigzag offset, the triple stitch raw.
        let intervals = probes[probes.count - 1].intervals
        predicted.append(pointsPerInterval * intervals + (isFirstEmission ? 1 : 0))
        isFirstEmission = false
        moveIndex += 1

        // The pattern's own clamp: the anchor advances to the surplus-stripped
        // point, not to the needle (ZigzagStitchPattern / TripleStitchPattern).
        let surplus = (distance - remainder) / distance
        anchor = StagePoint(x: current.x + surplus * dx, y: current.y + surplus * dy)
    }

    return Screening(probes: probes, predictedEmissions: predicted)
}

/// The `NeedleUpdate` carried by a `.needleMoved` event, if this is one.
func needleMove(in event: InterpreterEvent) -> NeedleUpdate? {
    if case let .needleMoved(_, update) = event {
        update
    } else {
        nil
    }
}

/// The per-tick emitted-stitch counts, restricted to the ticks that actually
/// moved the needle — the sequence `mirrorIsFaithful` compares against.
func emissionCountsPerMove(_ measured: SampleRun) -> [Int] {
    measured.batches.compactMap { batch in
        guard batch.contains(where: { needleMove(in: $0) != nil }) else { return nil }
        return batch.count {
            if case .stitch = $0 {
                true
            } else {
                false
            }
        }
    }
}
