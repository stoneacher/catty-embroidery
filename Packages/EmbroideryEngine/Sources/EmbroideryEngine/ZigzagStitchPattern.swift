import Foundation

/// Port of Catroid `ZigZagRunningStitch` (AGPL-3.0, org.catrobat.catroid.
/// embroidery): stitches alternate perpendicular to the needle's heading,
/// offset ±width/2, spaced `length` apart along the path.
///
/// Deliberate divergences from the reference:
/// - `Double` throughout where Catroid computes in `float` (ADR-014) — the
///   sub-resolution drift is absorbed by `javaRound` at unit conversion.
/// - The anchor arrives via the explicit `start` parameter instead of a
///   sprite-position read (platform-independent engine).
/// - Degenerate inputs (length <= 0, non-finite width/heading/positions)
///   emit nothing instead of NaN-poisoning the anchor as Catroid does.
///   Width 0 and negative widths are *not* guarded: both are well-defined
///   in the reference (zero offset / phase-flipped zigzag) and preserved.
public struct ZigzagStitchPattern: StitchPattern {
    /// Stitch spacing along the path in stage units.
    public let length: Double
    /// Full zigzag amplitude in stage units; points offset ±width/2.
    public let width: Double

    private var anchor: StagePoint
    private var first = true
    /// The alternation sign (Catroid `direction`): flips on every emitted
    /// point and persists across update calls — never reset, so a zigzag
    /// resumes on the opposite side after any pause or re-anchor.
    private var direction: Double = 1

    /// Catroid's constructor reads the sprite's current position; the
    /// platform-independent engine receives the anchor explicitly.
    public init(length: Double, width: Double, start: StagePoint) {
        self.length = length
        self.width = width
        anchor = start
    }

    public mutating func setStartPosition(_ position: StagePoint) {
        anchor = position
    }

    public mutating func update(_ needle: NeedleUpdate) -> [StagePoint] {
        let current = needle.position
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        let distance = hypot(dx, dy)
        // Single guard before any state mutation, mirroring
        // RunningStitchPattern's documented divergence from Catroid's
        // NaN-poisoning: degenerate inputs emit nothing and leave anchor,
        // first flag, and direction untouched. Width is only checked for
        // finiteness — 0 and negative widths stay unguarded (well-defined
        // Catroid behavior, see the type doc comment).
        guard length > 0, width.isFinite, needle.heading.isFinite,
              distance.isFinite, distance >= length else { return [] }

        let remainder = distance.truncatingRemainder(dividingBy: length)
        // Fraction of the move retained after stripping the sub-length
        // surplus (Catroid `surplusPercentage`).
        let surplus = (distance - remainder) / distance
        let clamped = StagePoint(x: anchor.x + surplus * dx, y: anchor.y + surplus * dy)
        let wholeLengths = ((distance - remainder) / length).rounded(.down)
        // Astronomical counts (needle at 1e19, subnormal lengths) pass the
        // finiteness guards but would trap the Int conversion; rejected per
        // ADR-014 rather than porting Java's saturate-and-hang.
        guard wholeLengths <= maxStitchesPerUpdate else { return [] }
        let count = Int(wholeLengths)
        // Sampled once per update (Catroid reads the sprite's degrees once
        // per interpolateStitches): every offset of this call — including
        // corner-adjacent midpoints — uses the same heading.
        let heading = needle.heading

        var stitches: [StagePoint] = []
        if first {
            first = false
            // Unlike RunningStitchPattern, the anchor stitch is offset, not
            // emitted raw — Catroid runs its first point through
            // addPointInDirection like every other.
            stitches.append(offsetPoint(anchor, heading: heading))
        }
        // Exclusive upper bound, unlike RunningStitchPattern's `1 ..< count
        // + 1`: Catroid's zigzag loops `count = 1; count < interpolationCount`
        // and emits the final point separately (below) at the raw clamp.
        // Guarded because a last-ulp float edge can make count 0 even past
        // the distance guard, and `1 ..< 0` would trap.
        if count > 1 {
            for index in 1 ..< count {
                let factor = Double(index) / Double(count)
                // Interior midpoints javaRound the base *before* the offset
                // (Catroid rounds interpolated coordinates, then calls
                // addPointInDirection on the rounded values).
                stitches.append(offsetPoint(
                    StagePoint(
                        x: javaRound(anchor.x + factor * (clamped.x - anchor.x)),
                        y: javaRound(anchor.y + factor * (clamped.y - anchor.y))
                    ),
                    heading: heading
                ))
            }
        }
        // The final point offsets the raw, unrounded clamp — Catroid passes
        // currentX/currentY straight through — and is emitted unconditionally.
        stitches.append(offsetPoint(clamped, heading: heading))
        anchor = clamped
        return stitches
    }

    /// Catroid `addPointInDirection`, 1:1. ADR-007 angle mapping: `heading`
    /// in degrees, 0° = up, x via sin, y via cos; the +90° turns the heading
    /// into its perpendicular. Mutates `direction` on every call — the
    /// alternation is the pattern's defining invariant, so every emitted
    /// point must pass through here exactly once.
    private mutating func offsetPoint(_ base: StagePoint, heading: Double) -> StagePoint {
        let radians = (heading + 90) * .pi / 180
        let half = width / 2
        let point = StagePoint(
            x: base.x - half * sin(radians) * direction,
            y: base.y - half * cos(radians) * direction
        )
        direction *= -1
        return point
    }
}
