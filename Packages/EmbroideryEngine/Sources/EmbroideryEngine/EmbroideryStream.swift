/// Ordered stitch stream shared by the pattern generators and the DST
/// writer. Mirrors Catroid's `DSTStream` flag semantics: `addJump()` and
/// `addColorChange()` arm a pending flag that the next appended stitch
/// carries, and the color-change count increments at `addColorChange()`
/// time. A plain value type by design (ADR/US-102) — Catty's class +
/// `SynchronizedArray` + draw-queue construction is deliberately not ported.
/// Longest move `EmbroideryStream` will interpolate, in embroidery units
/// (ADR-020): 1,000,000 splits at `DSTStitchRecord.maxDelta` units each. The
/// split count, not the distance, is what the bound is really about — it is
/// the same 1,000,000 as ADR-014's `maxStitchesPerUpdate`, for the same
/// reason, and 12.1 metres is three orders of magnitude past the 500-point
/// stage. A longer move emits nothing at all.
let maxInterpolatedMoveInUnits = 1_000_000 * DSTStitchRecord.maxDelta

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
        // Non-finite, or past the ×2 conversion's `Int` range.
        guard let position = EmbroideryPoint(converting: stagePoint) else { return }
        // Representable, but too far from the last stitch to interpolate.
        if let previous = lastStagePosition, !canInterpolate(from: previous, to: stagePoint) {
            return
        }

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

    /// Whether a move is short enough to split into a bounded number of jump
    /// stitches (ADR-020). Beyond the bound `addInterpolatedStitches` would
    /// append until it exhausted memory — Swift does not trap on that, but an
    /// unbounded emission is no better for a caller than the conversion trap
    /// this chokepoint closes. Same policy and same 1,000,000 bound as
    /// ADR-014's `maxStitchesPerUpdate`; running this check *before* the
    /// interpolation arithmetic is also what keeps that arithmetic in `Int`
    /// range, since both endpoints are already known convertible.
    private func canInterpolate(from previous: StagePoint, to target: StagePoint) -> Bool {
        EmbroideryPoint.distanceInUnits(dx: target.x - previous.x, dy: target.y - previous.y)
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
        // by subtracting individually rounded positions. The two disagree by
        // one unit at half-unit stage fractions, and where the difference says
        // 121 while the encoded delta is 122 this used to skip the split and
        // hand `DSTStitchRecord` an unencodable record. Taking the max keeps
        // Catroid's decision wherever it is sound and only *adds* splits —
        // deciding from the encoded delta alone would stop splitting in the
        // mirror case (difference 122, encoded 121), where the reference is
        // correct. Catroid emits a corrupt record at this boundary rather
        // than splitting; ADR-012 calls that a reference accident (ADR-020).
        //
        // Safe in `Int`: `append`'s cap guard has already bounded the
        // separation, and both endpoints are known convertible.
        let encodedDistance = stitches.last.map {
            max(
                abs(targetPosition.x - $0.position.x),
                abs(targetPosition.y - $0.position.y)
            )
        } ?? 0
        let distance = max(differenceDistance, encodedDistance)
        guard distance > DSTStitchRecord.maxDelta else { return }
        let splitCount = Int((Double(distance) / Double(DSTStitchRecord.maxDelta)).rounded(.up))
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
