import Foundation

/// Port of Catroid `SimpleRunningStitch` (AGPL-3.0, org.catrobat.catroid.
/// embroidery): emits a stitch every `length` stage units along the needle's
/// path, interpolated linearly between update points. The anchor stitch at
/// the start position is emitted lazily on the first update that crosses the
/// length threshold — not at construction.
public struct RunningStitchPattern: StitchPattern {
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
        guard distance >= length else { return [] }

        let remainder = distance.truncatingRemainder(dividingBy: length)
        let surplus = (distance - remainder) / distance
        let clamped = StagePoint(x: anchor.x + surplus * dx, y: anchor.y + surplus * dy)
        let count = Int(((distance - remainder) / length).rounded(.down))

        var stitches: [StagePoint] = []
        if first {
            first = false
            stitches.append(anchor)
        }
        for index in 1 ... count {
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
