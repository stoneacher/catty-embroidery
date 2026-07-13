import Foundation

/// Port of Catroid `ZigZagRunningStitch` (AGPL-3.0, org.catrobat.catroid.
/// embroidery): stitches alternate perpendicular to the needle's heading,
/// offset ±width/2, spaced `length` apart along the path.
///
/// TDD red-phase stub — US-108's failing tests define the semantics; the
/// implementation follows in the green commit.
public struct ZigzagStitchPattern: StitchPattern {
    /// Stitch spacing along the path in stage units.
    public let length: Double
    /// Full zigzag amplitude in stage units; points offset ±width/2.
    public let width: Double

    private var anchor: StagePoint

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

    public mutating func update(_: NeedleUpdate) -> [StagePoint] {
        []
    }
}
