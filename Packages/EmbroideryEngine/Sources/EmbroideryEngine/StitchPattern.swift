/// Needle state a pattern receives per movement tick. `heading` follows
/// ADR-007: degrees, 0° = up, x via sin, y via cos. The running stitch
/// ignores it; zigzag and sew-up (US-108/109) derive their geometry from
/// the heading rather than the movement vector, which differ under
/// goto/glide.
public struct NeedleUpdate: Hashable, Sendable {
    public var position: StagePoint
    public var heading: Double

    public init(position: StagePoint, heading: Double = 0) {
        self.position = position
        self.heading = heading
    }
}

/// Upper bound on the *whole-length count* of a single needle update
/// (ADR-014); a boundary update can emit one point more (the lazy anchor).
/// The count is compared against this before the `Int` conversion:
/// Catroid's `(int)` cast saturates to `Integer.MAX_VALUE` and Android hangs
/// materializing the stitches, while Swift's `Int(_:)` would trap — neither
/// accident is ported; the update is rejected outright. A million stitches is
/// two orders of magnitude past any legitimate design (DST's stitch-count
/// header field itself caps at seven digits).
let maxStitchesPerUpdate = 1_000_000.0

/// A pure stitch-generating state machine (Catroid `RunningStitchType`).
/// Patterns return stage-space stitch positions and never touch the
/// `EmbroideryStream` — the stream stays the single writer, owning unit
/// conversion, long-move interpolation, dedup, and pending flags.
public protocol StitchPattern: Sendable {
    /// Re-anchors the pattern's reference point without emitting anything
    /// (Catroid `setStartCoordinates`) — the seam US-109's sew-up uses to
    /// resume cleanly after emitting direct stitches.
    mutating func setStartPosition(_ position: StagePoint)

    /// Advances the state machine by one needle sample, returning the
    /// stage-space positions to stitch, in order.
    mutating func update(_ needle: NeedleUpdate) -> [StagePoint]
}
