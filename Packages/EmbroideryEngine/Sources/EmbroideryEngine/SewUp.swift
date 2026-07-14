import Foundation

/// Port of Catroid `SewUpAction` (AGPL-3.0, org.catrobat.catroid.content.
/// actions): a five-point bar-tack — center, ahead, center, behind, center,
/// `steps` stage units along the heading — that locks the thread in place.
/// ADR-012 pins this to Catroid's 5-point sequence; Catty's 4-point variant
/// (no leading center) is a known bug and deliberately not ported.
public enum SewUp {
    /// Catroid `SewUpAction.STEPS`, in stage units.
    public static let steps = 3.0

    /// The full reference dance around the emission: pause the running
    /// stitch, produce the five points, re-anchor the pattern to the center,
    /// resume. The re-anchor is load-bearing — `RunningStitch.resume()`
    /// deliberately does not re-anchor, and without it accumulated
    /// sub-length travel would drift the next stitch. Points are returned
    /// for the caller to feed the stream (the stream stays the single
    /// writer, ADR-013); Catroid routes them through the same
    /// `addStitchCommand` path as pattern stitches, so the workspace dedup
    /// applies — a needle already stitched at the center dedups the leading
    /// point to 4 records.
    public static func perform(
        at center: StagePoint,
        heading: Double,
        runningStitch: inout RunningStitch
    ) -> [StagePoint] {
        // Degenerate inputs emit nothing and leave the running stitch
        // untouched (ADR-014) — guarded before pause() so a garbage sew-up
        // does not disturb the lifecycle.
        guard center.x.isFinite, center.y.isFinite, heading.isFinite else { return [] }

        runningStitch.pause()
        // Normalize before converting: a huge finite heading would overflow
        // (heading × π/180) to infinity and sin/cos to NaN (the US-108
        // zigzag find, same class of bug).
        let radians = heading.truncatingRemainder(dividingBy: 360) * .pi / 180
        // ADR-007 like the reference: x via sin, y via cos, 0° = up. The
        // center is reused exactly for points 1/3/5 instead of replaying
        // Catroid's add-then-subtract float round-trip — sub-1e-9 (ADR-014).
        let dx = steps * sin(radians)
        let dy = steps * cos(radians)
        let ahead = StagePoint(x: center.x + dx, y: center.y + dy)
        let behind = StagePoint(x: center.x - dx, y: center.y - dy)

        runningStitch.setStartPosition(center)
        runningStitch.resume()
        return [center, ahead, center, behind, center]
    }
}
