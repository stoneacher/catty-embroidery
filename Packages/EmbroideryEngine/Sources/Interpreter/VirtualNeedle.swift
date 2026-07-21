import EmbroideryEngine
import Foundation

/// The virtual needle: the moving object motion bricks steer through ADR-007
/// stage space (center origin, y-up, degrees, 0° = up, x via sin, y via cos).
/// Catroid has no separate needle — embroidery reads the sprite's position — so
/// here the needle *is* the object's motion state. This type is pure geometry:
/// the `apply(_:scope:)` bridge (in `VirtualNeedle+Brick`) is the only place it
/// meets `ProgramModel` formulas. Emitting one `NeedleUpdate` per motion is the
/// bridge's job; these methods only mutate.
public struct VirtualNeedle: Hashable, Sendable {
    /// Current position in ADR-007 stage space.
    public var position: StagePoint
    /// Current heading in degrees (0° = up, clockwise positive). Not guaranteed
    /// pre-normalized — the public initializer and stored property accept any
    /// value, so movement normalizes at use (see `moveNSteps`).
    public var heading: Double

    public init(position: StagePoint = StagePoint(x: 0, y: 0), heading: Double = 0) {
        self.position = position
        self.heading = heading
    }
}

public extension VirtualNeedle {
    /// Advances along the current heading (Catroid `MoveNStepsAction`):
    /// `dx = steps·sin(heading)`, `dy = steps·cos(heading)`. The heading is
    /// reduced mod 360 *before* the radian conversion (ADR-014): `heading` is a
    /// public stored var, so a caller can hand in a `greatestFiniteMagnitude`
    /// -scale value with no intervening turn, and `·π/180` would overflow to ∞
    /// whose sin/cos is NaN (US-108 Codex find). The engine extends such headings
    /// by exact periodicity rather than reproducing Java's raw huge-argument noise.
    mutating func moveNSteps(_ steps: Double) {
        let radians = heading.truncatingRemainder(dividingBy: 360) * .pi / 180
        position.x += steps * sin(radians)
        position.y += steps * cos(radians)
    }

    /// Turns clockwise, **adding** degrees (Catroid `TurnRightAction` via
    /// `changeDirectionInUserInterfaceDimensionUnit`), then normalizes mod 360.
    mutating func turnRight(_ degrees: Double) {
        heading = normalized(heading + degrees)
    }

    /// Turns counter-clockwise, **subtracting** degrees (Catroid `TurnLeftAction`),
    /// then normalizes mod 360.
    mutating func turnLeft(_ degrees: Double) {
        heading = normalized(heading - degrees)
    }

    /// Sets an absolute heading (Catroid `PointInDirectionAction`), normalized
    /// mod 360 — not relative to the current heading.
    mutating func pointInDirection(_ degrees: Double) {
        heading = normalized(degrees)
    }

    /// Teleports to `(x, y)` (Catroid compiles `PlaceAt` as a zero-duration glide
    /// — instantaneous, no interpolation).
    mutating func placeAt(x: Double, y: Double) {
        position = StagePoint(x: x, y: y)
    }

    /// Sets the x axis only (Catroid `SetXAction`).
    mutating func setX(_ x: Double) {
        position.x = x
    }

    /// Sets the y axis only (Catroid `SetYAction`).
    mutating func setY(_ y: Double) {
        position.y = y
    }

    /// Accumulates onto the x axis (Catroid `ChangeXByNAction`).
    mutating func changeXBy(_ dx: Double) {
        position.x += dx
    }

    /// Accumulates onto the y axis (Catroid `ChangeYByNAction`).
    mutating func changeYBy(_ dy: Double) {
        position.y += dy
    }

    /// Headings normalized mod 360 exactly (ADR-014), via `truncatingRemainder`.
    /// Deliberately *not* Catroid's `Look.breakDownCatroidAngle` fold to
    /// (−180, 180]: Catroid's sprite layer pre-normalizes there, but this engine
    /// pins exact mod-360 periodicity. Same sin/cos geometry, different stored
    /// representation.
    private func normalized(_ degrees: Double) -> Double {
        degrees.truncatingRemainder(dividingBy: 360)
    }
}
