import EmbroideryEngine
import Foundation

/// Java's `Math.toRadians`/`toDegrees` constants (desktop JDK 9+), as ADR-046
/// uses for the formula functions.
private let degreesToRadians = Double.pi / 180
private let radiansToDegrees = 180 / Double.pi

public extension VirtualNeedle {
    /// Travels `sweepDegrees` around a circle of `radius` (Catroid `ArcAction`),
    /// counter-clockwise for a positive sweep (left), clockwise for a negative one
    /// (right). Returns the updates it fed, in order; ADR-047 pins the rules:
    ///
    /// - The centre lies on the heading's normal: `(−cos h, sin h)` to the left,
    ///   `(cos h, −sin h)` to the right. Headings are compass angles (ADR-007);
    ///   the angle *around the centre* is a math angle, `atan2(y − cy, x − cx)`.
    /// - Samples i = 1…100 at `start + sweep·i/100`. Catroid's i = 0 only
    ///   reconstructs the start, with a float-vs-double residual that can turn a
    ///   0° arc's heading.
    /// - A sample is fed only if it differs from the previous one, and then turns
    ///   the needle to the chord it travelled (`atan2(dx, dy)`), so the final
    ///   heading is the last chord's, ≈ sweep/200 off the tangent (D6, mirrored).
    /// - **Degenerate first**: radius 0 or sweep 0 feeds nothing.
    /// - **Compute, then commit**: a non-finite sample anywhere leaves the needle
    ///   untouched, so it never holds an overflowed coordinate.
    /// - Feeding nothing returns one *unchanged* update (US-204's rule for turns).
    mutating func arc(radius: Double, sweepDegrees: Double) -> [NeedleUpdate] {
        let unchanged = [NeedleUpdate(position: position, heading: heading)]
        let radius = abs(radius)
        guard radius != 0, sweepDegrees != 0 else {
            return unchanged
        }
        let heading = normalized(self.heading) * degreesToRadians
        let side: Double = sweepDegrees > 0 ? 1 : -1
        let centre = StagePoint(
            x: position.x - side * radius * cos(heading),
            y: position.y + side * radius * sin(heading)
        )
        let startAngle = atan2(position.y - centre.y, position.x - centre.x)

        var updates: [NeedleUpdate] = []
        updates.reserveCapacity(100)
        var previous = position
        for step in 1 ... 100 {
            let angle = startAngle + sweepDegrees * Double(step) / 100 * degreesToRadians
            let point = StagePoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            guard point.x.isFinite, point.y.isFinite else {
                return unchanged
            }
            if point != previous {
                let bearing = atan2(point.x - previous.x, point.y - previous.y) * radiansToDegrees
                updates.append(NeedleUpdate(position: point, heading: bearing))
                previous = point
            }
        }
        guard let last = updates.last else {
            return unchanged
        }
        position = last.position
        self.heading = last.heading
        return updates
    }
}
