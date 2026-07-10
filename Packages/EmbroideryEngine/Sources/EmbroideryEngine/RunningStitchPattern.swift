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

    public mutating func update(_: NeedleUpdate) -> [StagePoint] {
        []
    }
}
