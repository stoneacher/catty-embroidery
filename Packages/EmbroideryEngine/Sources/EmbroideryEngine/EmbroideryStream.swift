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

    /// Whether travelling from `previous` to `target` needs a traversal — i.e.
    /// whether `append` would emit **more than one** record for it (ADR-020's
    /// interpolation). `false` when `append` would emit nothing at all.
    ///
    /// M3's renderer draws travel moves distinctly from thread and asks the
    /// engine rather than re-deriving ADR-020: both references draw them as
    /// solid thread, so a machine's travel looks sewn.
    ///
    /// **A predicate over a pair, not over stream state.** ADR-020's
    /// encoded-delta trigger reads `stitches.last` inside
    /// `addInterpolatedStitches`; here that becomes
    /// `EmbroideryPoint(converting: previous)`. The two agree in any real
    /// stream — `lastStagePosition` and `stitches.last` are written together in
    /// the same `append` call and neither is set without the other — but that
    /// is *believed*, not proven, which is why `TraversalPredicateTests` checks
    /// it differentially against real appends instead of asserting it here.
    ///
    /// Reproduces **conversion plus every `canAppend` guard**, not just the two
    /// distance triggers: a move past the split cap, or across a lattice too
    /// coarse to subdivide, emits nothing, and claiming traversal there would
    /// draw a travel line to somewhere the machine never goes.
    public static func requiresTraversal(from previous: StagePoint, to target: StagePoint) -> Bool {
        guard let previousPosition = EmbroideryPoint(converting: previous),
              let targetPosition = EmbroideryPoint(converting: target),
              canAppend(from: previous, to: target)
        else { return false }
        return interpolationSplitCount(
            from: previous,
            to: target,
            targetPosition: targetPosition,
            previousPosition: previousPosition
        ) != nil
    }

    /// Whether `append` would emit for this point — the ADR-020 guards without
    /// the emission. Internal because the pattern manager's replay has to ask
    /// *before* arming a color change: the manager arms flags at command time
    /// and the stream converts at replay time, so a flag armed for an emission
    /// the stream then rejects would ride the next surviving append, which in
    /// an interleaved multi-actor replay can belong to a different actor
    /// (Codex US-210 round 1).
    func canAppend(stitchAt stagePoint: StagePoint) -> Bool {
        Self.canAppend(from: lastStagePosition, to: stagePoint)
    }

    /// The guards themselves, over a pair. One implementation, two entry
    /// points: the instance seam above and `requiresTraversal`. Re-spelling
    /// them in the predicate is exactly the duplication that would let the two
    /// drift apart, and the drift would be invisible until a design drew a
    /// travel line the machine never makes.
    static func canAppend(from previous: StagePoint?, to target: StagePoint) -> Bool {
        // Non-finite, or past the ×2 conversion's `Int` range.
        guard EmbroideryPoint(converting: target) != nil else { return false }
        // Representable, but unreachable from the last stitch by interpolation.
        guard let previous else { return true }
        return canInterpolate(from: previous, to: target)
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
    /// - **Too coarse to subdivide.** Above ~2^58 stage points the gap between
    ///   adjacent `Double`s exceeds ±121 units, so *no* encodable non-zero move
    ///   exists on that axis: a subdivided midpoint rounds back onto an
    ///   endpoint and the recursion re-enters with the same pair forever
    ///   (Codex US-210 round 1, reproduced as a stack overflow at
    ///   2^58 → 2^58 + 64). Checked **per axis, and only for an axis that
    ///   actually has to be split** — a coordinate merely *sitting* at a coarse
    ///   magnitude must not veto a legal move on the other axis (Codex round
    ///   2: `(2^58, 0) → (2^58, 1)` encodes as a plain `(0, 2)` delta).
    private static func canInterpolate(from previous: StagePoint, to target: StagePoint) -> Bool {
        guard axisCanBeSubdivided(from: previous.x, to: target.x),
              axisCanBeSubdivided(from: previous.y, to: target.y)
        else { return false }
        return EmbroideryPoint.distanceInUnits(dx: target.x - previous.x, dy: target.y - previous.y)
            <= maxInterpolatedMoveInUnits
    }

    /// One axis of the coarse-lattice test. An axis whose own hop already fits
    /// a record is carried along whatever its magnitude — stationary or short,
    /// there is nothing on it to subdivide. (A coarse axis cannot be *short*
    /// and non-zero: its hop is a multiple of a lattice step wider than ±121,
    /// so "fits a record" and "does not move" are the same case there.)
    ///
    /// For an axis that must be split, the lattice step decides. This is also
    /// where the recursion's progress argument comes from: the first
    /// intermediate sits about `hop / splitCount` from the start, which is
    /// never below ~60.5 stage points for a hop over ±121, so a step within
    /// ±121 units cannot round it back onto the endpoint.
    ///
    /// The step to measure is the coarsest one *inside* the interval, which is
    /// not `.ulp` of either endpoint: at an exact power of two `.ulp` reports
    /// the spacing going **outward**, twice the spacing a move heading back
    /// toward zero actually lands in. 2^58 → 2^58 − 64 has a representable
    /// midpoint and subdivides; 2^58 → 2^58 + 64 has none (Codex US-210 round
    /// 3). Taking the *finer* endpoint instead would be wrong in the other
    /// direction — 2^58 → 2^58 + 128 subdivides once into a hop that is itself
    /// non-progressing, so it must be refused up front, not one level down.
    private static func axisCanBeSubdivided(from start: Double, to end: Double) -> Bool {
        guard EmbroideryPoint.distanceInUnits(dx: end - start, dy: 0) > DSTStitchRecord.maxDelta
        else { return true }
        let latticeStep = max(abs(start), abs(end)).nextDown.ulp
        return latticeStep * EmbroideryPoint.stitchPointUnitFactor
            <= Double(DSTStitchRecord.maxDelta)
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
        guard let splitCount = Self.interpolationSplitCount(
            from: previous,
            to: target,
            targetPosition: targetPosition,
            previousPosition: stitches.last?.position
        ) else { return }
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

    /// ADR-020's dual trigger and single count, in the one place both the
    /// emitter and `requiresTraversal` read it. `nil` means no split.
    ///
    /// Two measures. Catroid's is the stage *difference*, rounded. The other is
    /// the delta `DSTFile` will actually encode, which ADR-012 builds by
    /// subtracting individually rounded positions. Both roundings sit within
    /// half a unit of the exact value, so the two differ by at most one per
    /// axis — which is what keeps the subtraction below inside `Int`: every
    /// caller has already passed `canAppend`, so the cap has bounded the
    /// difference measure and both endpoints are known convertible. Where the
    /// difference reads 121 while the encoded delta is 122, skipping the split
    /// used to hand `DSTStitchRecord` an unencodable record. Catroid has the
    /// same disagreement and emits a corrupt record; ADR-012 calls that a
    /// reference accident, so we split instead.
    ///
    /// The encoded delta widens the *trigger*, never the count. Where the
    /// difference already exceeds ±121 Catroid's count is sound — its own
    /// recursion re-splits any over-long hop — so raising it there would change
    /// bytes the reference gets right: at difference 242 / encoded 243 (stage
    /// 0.125 → 121.25) a count taken from the maximum emits six stitches where
    /// the reference emits eight. Where only the encoded delta triggers, the
    /// count is two, not `ceil(121/121)` = 1: a one-way split emits no
    /// intermediates and re-enters this decision with the same pair, which
    /// would never terminate.
    ///
    /// `previousPosition` is the encoded anchor. The emitter passes
    /// `stitches.last?.position`; `requiresTraversal`, which holds no stream,
    /// passes the converted `previous`. `nil` — an empty stream — cannot arise
    /// from the emitter, since `lastStagePosition` is only ever set alongside a
    /// `stitches.append`, but is handled rather than asserted.
    static func interpolationSplitCount(
        from previous: StagePoint,
        to target: StagePoint,
        targetPosition: EmbroideryPoint,
        previousPosition: EmbroideryPoint?
    ) -> Int? {
        let differenceDistance = EmbroideryPoint.distanceInUnits(
            dx: target.x - previous.x, dy: target.y - previous.y
        )
        let encodedDistance = previousPosition.map {
            max(
                abs(targetPosition.x - $0.x),
                abs(targetPosition.y - $0.y)
            )
        } ?? 0

        if differenceDistance > DSTStitchRecord.maxDelta {
            return Int(
                (Double(differenceDistance) / Double(DSTStitchRecord.maxDelta)).rounded(.up)
            )
        }
        if encodedDistance > DSTStitchRecord.maxDelta {
            return 2
        }
        return nil
    }
}
