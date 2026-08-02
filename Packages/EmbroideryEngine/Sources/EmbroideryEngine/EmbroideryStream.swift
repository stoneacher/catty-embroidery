/// Longest move `EmbroideryStream` will interpolate, in embroidery units
/// (ADR-020): 1,000,000 splits at `DSTStitchRecord.maxDelta` units each. The
/// split count, not the distance, is what the bound is really about — it is
/// the same 1,000,000 as ADR-014's `maxStitchesPerUpdate`, for the same
/// reason, and 12.1 metres is three orders of magnitude past the 500-point
/// stage. A longer move emits nothing at all.
let maxInterpolatedMoveInUnits = 1_000_000 * DSTStitchRecord.maxDelta

/// Ordered stitch stream shared by the pattern generators and the DST
/// writer. Mirrors Catroid's `DSTStream` flag semantics: `addJump()` and
/// `addColorChange()` arm a pending flag that the next appended stitch
/// carries, and the color-change count increments at `addColorChange()`
/// time. A plain value type by design (ADR/US-102) — Catty's class +
/// `SynchronizedArray` + draw-queue construction is deliberately not ported.
public struct EmbroideryStream: Hashable, Sendable {
    /// Min/max corners of the stitched area in embroidery units; the header
    /// writer (US-104) derives +X/−X/+Y/−Y extents from these.
    public struct BoundingBox: Hashable, Sendable {
        public var min: EmbroideryPoint
        public var max: EmbroideryPoint
    }

    public private(set) var stitches: [Stitch] = []
    /// Number of color-change records signaled so far. The DST `CO` header
    /// field counts color *blocks* = this + 1 (US-104, ADR-012).
    public private(set) var colorChangeCount = 0

    private var nextIsJump = false
    private var nextIsColorChange = false
    /// Stage-space position of the last appended stitch. Interpolation must
    /// compute and round intermediates in stage coordinates *before* the ×2
    /// unit conversion (ADR-012), and `Stitch` only keeps converted units.
    private var lastStagePosition: StagePoint?

    public init() {}

    public var count: Int {
        stitches.count
    }

    public var firstStitchPosition: EmbroideryPoint? {
        stitches.first?.position
    }

    public var lastStitchPosition: EmbroideryPoint? {
        stitches.last?.position
    }

    /// Spans every stitch including jumps — Catroid updates its header
    /// extents for each appended point regardless of flags.
    public var boundingBox: BoundingBox? {
        guard let first = stitches.first else { return nil }
        var box = BoundingBox(min: first.position, max: first.position)
        for stitch in stitches.dropFirst() {
            box.min.x = min(box.min.x, stitch.position.x)
            box.min.y = min(box.min.y, stitch.position.y)
            box.max.x = max(box.max.x, stitch.position.x)
            box.max.y = max(box.max.y, stitch.position.y)
        }
        return box
    }

    /// Arms the jump flag; the next appended stitch becomes a jump record.
    public mutating func addJump() {
        nextIsJump = true
    }

    /// Signals a color change: counts immediately and arms the flag the
    /// next appended stitch carries, matching `DSTStream.addColorChange`.
    public mutating func addColorChange() {
        colorChangeCount += 1
        nextIsColorChange = true
    }

    /// Appends a stitch at a stage-space position, converting to embroidery
    /// units and consuming any pending jump/color-change flags. Moves longer
    /// than ±121 units on either axis are first split into jump stitches
    /// (US-105); the pending flags are captured before interpolation runs and
    /// land on the final stitch, as in Catroid `DSTStream.addStitchPoint`.
    ///
    /// Workspace dedup, single-actor slice (ADR-012; US-110 owns the actor,
    /// layer, and color dimensions): a stitch at the last appended stage
    /// position is dropped before flags are consumed or interpolation runs,
    /// like Catroid `DSTStitchCommand.act`'s early return — armed flags stay
    /// pending for the next surviving stitch. Compared in stage space on raw
    /// `Double`s (the reference compares raw floats), so two distinct stage
    /// points that round to the same embroidery unit both survive. Only this
    /// public seam dedups: interpolation appends through `append(stitchAt:)`
    /// because its duplicate-of-previous jump emission is byte-pinned.
    public mutating func addStitch(at stagePoint: StagePoint, color: ThreadColor = .black) {
        if let last = lastStagePosition, stagePoint == last {
            return
        }
        append(stitchAt: stagePoint, color: color)
    }

    /// Dedup-free append seam: consumes the armed flags, interpolates long
    /// moves, and records the stage position. Internal so the pattern
    /// manager's layer replay (US-110) can emit its byte-pinned consecutive
    /// duplicates — like interpolation, it must bypass `addStitch`'s dedup.
    ///
    /// Also the engine's coordinate chokepoint (ADR-020). Two guards run
    /// *above* the flag reads, so a rejected stitch is a true no-op: armed
    /// flags stay pending for the next surviving stitch and `lastStagePosition`
    /// keeps pointing at a coordinate that was actually stitched, exactly like
    /// `addStitch`'s dedup. Both take the ADR-014 shape — emit nothing, leave
    /// state untouched — rather than clamping, which would silently move the
    /// needle somewhere the program never asked for and leave it there.
    mutating func append(stitchAt stagePoint: StagePoint, color: ThreadColor) {
        guard canAppend(stitchAt: stagePoint),
              let position = EmbroideryPoint(converting: stagePoint)
        else { return }

        let isJump = nextIsJump
        let isColorChange = nextIsColorChange
        nextIsJump = false
        nextIsColorChange = false

        if let previous = lastStagePosition {
            addInterpolatedStitches(
                from: previous, to: stagePoint, targetPosition: position, color: color
            )
        }
        stitches.append(Stitch(
            position: position,
            color: color,
            isJump: isJump,
            isColorChange: isColorChange
        ))
        lastStagePosition = stagePoint
    }

    /// Whether `append` would emit for this point — the ADR-020 guards without
    /// the emission. Internal because the pattern manager's replay has to ask
    /// *before* arming a color change: the manager arms flags at command time
    /// and the stream converts at replay time, so a flag armed for an emission
    /// the stream then rejects would ride the next surviving append, which in
    /// an interleaved multi-actor replay can belong to a different actor
    /// (Codex US-210 round 1).
    func canAppend(stitchAt stagePoint: StagePoint) -> Bool {
        // Non-finite, or past the ×2 conversion's `Int` range.
        guard EmbroideryPoint(converting: stagePoint) != nil else { return false }
        // Representable, but unreachable from the last stitch by interpolation.
        guard let previous = lastStagePosition else { return true }
        return canInterpolate(from: previous, to: stagePoint)
    }

    /// Whether a move can be split into a bounded number of encodable jump
    /// stitches (ADR-020). Two ways it cannot, both ending in an unbounded
    /// emission rather than a trap — no better for a caller than the crash
    /// this chokepoint closes:
    ///
    /// - **Too long.** Beyond 1,000,000 splits `addInterpolatedStitches` would
    ///   append until it exhausted memory. Same policy and same bound as
    ///   ADR-014's `maxStitchesPerUpdate`. Checking it before the interpolation
    ///   arithmetic is also what keeps that arithmetic in `Int` range, since
    ///   both endpoints are already known convertible.
    /// - **Too coarse.** Above ~2^58 stage points the gap between adjacent
    ///   `Double`s exceeds ±121 units, so *no* encodable non-zero move exists
    ///   there: a subdivided midpoint rounds back onto an endpoint and the
    ///   recursion re-enters with the same pair forever (Codex US-210 round 1,
    ///   reproduced as a stack overflow at 2^58 → 2^58 + 64). Requiring the
    ///   lattice step to stay within ±121 units is also exactly what makes the
    ///   recursion's progress argument true: every hop is a multiple of that
    ///   step, so a hop over ±121 is at least two steps and its subdivision
    ///   cannot collapse onto an endpoint.
    private func canInterpolate(from previous: StagePoint, to target: StagePoint) -> Bool {
        let latticeStep = max(previous.x.ulp, previous.y.ulp, target.x.ulp, target.y.ulp)
        guard latticeStep * EmbroideryPoint.stitchPointUnitFactor <= Double(DSTStitchRecord.maxDelta)
        else { return false }
        return EmbroideryPoint.distanceInUnits(dx: target.x - previous.x, dy: target.y - previous.y)
            <= maxInterpolatedMoveInUnits
    }

    /// Port of Catroid `DSTStream.addInterpolatedPoints` (ADR-012, byte-pinned
    /// for the US-106 golden test): when the move exceeds ±121 units, emit a
    /// duplicate of the previous point, `splitCount − 1` evenly spaced
    /// intermediates (rounded in stage coordinates), and the target — all as
    /// jumps — before the caller appends the target again as a plain stitch.
    /// Emission recurses through `append(stitchAt:)` exactly like the
    /// reference, so each emitted point re-checks its own distance — not
    /// through `addStitch`, whose dedup would swallow the duplicate-of-
    /// previous emission. The duplicate and the intermediates keep the
    /// previous stitch's color; the target jump already carries the new one.
    private mutating func addInterpolatedStitches(
        from previous: StagePoint,
        to target: StagePoint,
        targetPosition: EmbroideryPoint,
        color: ThreadColor
    ) {
        // Catroid's measure: the stage difference, rounded.
        let differenceDistance = EmbroideryPoint.distanceInUnits(
            dx: target.x - previous.x, dy: target.y - previous.y
        )
        // And the delta `DSTFile` will actually encode, which ADR-012 builds
        // by subtracting individually rounded positions. Both roundings sit
        // within half a unit of the exact value, so the two measures differ by
        // at most one per axis — which is what keeps this subtraction inside
        // `Int` (`append`'s cap has already bounded the difference measure,
        // and both endpoints are known convertible). Where the difference
        // reads 121 while the encoded delta is 122, this used to skip the
        // split and hand `DSTStitchRecord` an unencodable record. Catroid has
        // the same disagreement and emits a corrupt record; ADR-012 calls that
        // a reference accident, so we split instead (ADR-020).
        let encodedDistance = stitches.last.map {
            max(
                abs(targetPosition.x - $0.position.x),
                abs(targetPosition.y - $0.position.y)
            )
        } ?? 0

        // The encoded delta widens the *trigger*, never the count. Where the
        // difference already exceeds ±121 Catroid's count is sound — its own
        // recursion re-splits any over-long hop — so raising it there would
        // change bytes the reference gets right: at difference 242 / encoded
        // 243 (stage 0.125 → 121.25) a count taken from the maximum emits six
        // stitches where the reference emits eight. Where only the encoded
        // delta triggers, the count is two, not `ceil(121/121)` = 1: a
        // one-way split emits no intermediates and re-enters this decision
        // with the same pair, which would never terminate.
        let splitCount: Int
        if differenceDistance > DSTStitchRecord.maxDelta {
            splitCount = Int(
                (Double(differenceDistance) / Double(DSTStitchRecord.maxDelta)).rounded(.up)
            )
        } else if encodedDistance > DSTStitchRecord.maxDelta {
            splitCount = 2
        } else {
            return
        }
        let previousColor = stitches.last?.color ?? color

        addJump()
        append(stitchAt: previous, color: previousColor)

        for count in 1 ..< splitCount {
            let factor = Double(count) / Double(splitCount)
            let intermediate = StagePoint(
                x: javaRound(previous.x + factor * (target.x - previous.x)),
                y: javaRound(previous.y + factor * (target.y - previous.y))
            )
            addJump()
            append(stitchAt: intermediate, color: previousColor)
        }

        addJump()
        append(stitchAt: target, color: color)
    }
}
