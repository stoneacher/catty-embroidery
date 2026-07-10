import Foundation

/// Port of Catroid `SimpleRunningStitch` (AGPL-3.0, org.catrobat.catroid.
/// embroidery): emits a stitch every `length` stage units along the needle's
/// path, interpolated linearly between update points. The anchor stitch at
/// the start position is emitted lazily on the first update that crosses the
/// length threshold — not at construction.
public struct RunningStitchPattern: StitchPattern {
    /// Stitch spacing in stage units. Catroid interprets the brick formula
    /// as an integer (`interpretInteger`); the engine generalizes to
    /// `Double` — if program-output fidelity with Android matters, the
    /// brick layer (US-110+) must truncate formula results before
    /// constructing the pattern.
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
        // Degenerate inputs (length <= 0, non-finite positions) emit nothing
        // and leave the anchor untouched — a deliberate divergence from the
        // reference, where a zero length (Catroid's formula-error fallback)
        // NaN-poisons the anchor and the pattern goes permanently dead. A
        // Swift trap on user input is not an acceptable port of that accident.
        guard length > 0, distance.isFinite, distance >= length else { return [] }

        let remainder = distance.truncatingRemainder(dividingBy: length)
        // Fraction of the move retained after stripping the sub-length
        // surplus (Catroid `surplusPercentage`).
        let surplus = (distance - remainder) / distance
        let clamped = StagePoint(x: anchor.x + surplus * dx, y: anchor.y + surplus * dy)
        let count = Int(((distance - remainder) / length).rounded(.down))

        var stitches: [StagePoint] = []
        if first {
            first = false
            stitches.append(anchor)
        }
        // Half-open like the reference's trap-free loop: a last-ulp float
        // edge can make count 0 even past the guard, and 1...0 would trap.
        for index in 1 ..< count + 1 {
            let factor = Double(index) / Double(count)
            stitches.append(StagePoint(
                x: javaRound(anchor.x + factor * (clamped.x - anchor.x)),
                y: javaRound(anchor.y + factor * (clamped.y - anchor.y))
            ))
        }
        anchor = clamped
        return stitches
    }
}
