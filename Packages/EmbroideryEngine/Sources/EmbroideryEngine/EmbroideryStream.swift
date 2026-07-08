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
    /// units and consuming any pending jump/color-change flags.
    public mutating func addStitch(at stagePoint: StagePoint, color: ThreadColor = .black) {
        stitches.append(Stitch(
            position: EmbroideryPoint(converting: stagePoint),
            color: color,
            isJump: nextIsJump,
            isColorChange: nextIsColorChange
        ))
        nextIsJump = false
        nextIsColorChange = false
    }
}
