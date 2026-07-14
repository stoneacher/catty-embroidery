import Foundation

/// Port of Catroid `TripleRunningStitch` (AGPL-3.0, org.catrobat.catroid.
/// embroidery): steps along the needle's path like the simple running
/// stitch, but sews every segment three times — forward to the new point,
/// back to the previous one, forward again — for a reinforced seam. The
/// anchor stitch is emitted lazily on the first update that crosses the
/// length threshold, and the heading is ignored, both like the reference.
public struct TripleStitchPattern: StitchPattern {
    /// Stitch spacing in stage units (Catroid's `steps`; the story text
    /// names the parameter accordingly, but the engine keeps the label
    /// `length` shared by all patterns — see the US-109 PR notes).
    public let length: Double

    private var anchor: StagePoint
    private var first = true

    /// Catroid's constructor reads the sprite's current position; the
    /// platform-independent engine receives the anchor explicitly.
    public init(length: Double, start: StagePoint) {
        self.length = length
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
        // Degenerate inputs emit nothing and leave the anchor untouched —
        // the same deliberate divergence from the reference's NaN-poisoning
        // as RunningStitchPattern (ADR-014).
        guard length > 0, distance.isFinite, distance >= length else { return [] }

        let remainder = distance.truncatingRemainder(dividingBy: length)
        // Fraction of the move retained after stripping the sub-length
        // surplus (Catroid `surplusPercentage`).
        let surplus = (distance - remainder) / distance
        let clamped = StagePoint(x: anchor.x + surplus * dx, y: anchor.y + surplus * dy)
        let wholeLengths = ((distance - remainder) / length).rounded(.down)
        // Rejected per ADR-014 rather than porting Java's saturate-and-hang;
        // bounds the segment count, so at most 3× that many stitches.
        guard wholeLengths <= maxStitchesPerUpdate else { return [] }
        let count = Int(wholeLengths)

        var stitches: [StagePoint] = []
        if first {
            first = false
            stitches.append(anchor)
        }
        // Segment 1 stitches back to the raw anchor; later segments to the
        // previous *rounded* point — Catroid seeds `previousX = firstX`
        // un-rounded and advances it with the `Math.round`-ed interpolant.
        var previous = anchor
        // Half-open like the reference's trap-free loop: a last-ulp float
        // edge can make count 0 even past the guard, and 1...0 would trap.
        for index in 1 ..< count + 1 {
            let factor = Double(index) / Double(count)
            let point = StagePoint(
                x: javaRound(anchor.x + factor * (clamped.x - anchor.x)),
                y: javaRound(anchor.y + factor * (clamped.y - anchor.y))
            )
            stitches.append(point)
            stitches.append(previous)
            stitches.append(point)
            previous = point
        }
        anchor = clamped
        return stitches
    }
}
