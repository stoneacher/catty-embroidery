import EmbroideryEngine
import Interpreter
import Testing

/// US-204 test-plan items 1–4 (plus a huge-heading guard): the pure-geometry
/// half of the virtual needle. The needle operates in ADR-007 stage space
/// (center origin, y-up, degrees, 0° = up, x via sin, y via cos) and normalizes
/// headings mod 360 exactly via `truncatingRemainder` — the ADR-014 discipline,
/// deliberately *not* Catroid's fold to (−180, 180]. Stage-space coordinates are
/// asserted within an absolute tolerance of 1e-9 (ADR-014), never `==`.
@Suite("Virtual needle geometry")
struct VirtualNeedleTests {
    /// Absolute-tolerance stage-space comparison (ADR-014, 1e-9).
    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    // MARK: Item 1 — move follows the heading (0° = up, x via sin, y via cos)

    @Test("moveNSteps at heading 0° advances +y; at 90° advances +x")
    func moveFollowsHeading() {
        var upward = VirtualNeedle(heading: 0)
        upward.moveNSteps(10)
        #expect(isClose(upward.position.x, 0))
        #expect(isClose(upward.position.y, 10))

        var right = VirtualNeedle(heading: 90)
        right.moveNSteps(10)
        #expect(isClose(right.position.x, 10))
        #expect(isClose(right.position.y, 0))
    }

    // MARK: Item 2 — turnRight adds, turnLeft subtracts; accumulate + normalize

    @Test("turnRight(90) then move advances +x; turnLeft(90) mirrors to −x")
    func turnsSteerTheMove() {
        var right = VirtualNeedle(heading: 0)
        right.turnRight(90)
        right.moveNSteps(10)
        #expect(isClose(right.position.x, 10))
        #expect(isClose(right.position.y, 0))

        var left = VirtualNeedle(heading: 0)
        left.turnLeft(90)
        left.moveNSteps(10)
        #expect(isClose(left.position.x, -10))
        #expect(isClose(left.position.y, 0))
    }

    @Test("turns accumulate and normalize mod 360 (truncatingRemainder, not (−180,180])")
    func turnsAccumulateAndNormalize() {
        var full = VirtualNeedle(heading: 0)
        full.turnRight(90)
        full.turnRight(90)
        full.turnRight(90)
        full.turnRight(90)
        #expect(isClose(full.heading, 0)) // 360 → 0

        var over = VirtualNeedle(heading: 0)
        over.turnRight(370)
        #expect(isClose(over.heading, 10)) // 370 → 10

        // Discriminating cases (|reduced| > 180): these expose the ADR-014
        // divergence — Catroid's (−180,180] fold would give −90 / +90 instead.
        var beyond = VirtualNeedle(heading: 0)
        beyond.turnRight(270)
        #expect(isClose(beyond.heading, 270)) // truncatingRemainder keeps 270, not −90

        var negative = VirtualNeedle(heading: 0)
        negative.turnLeft(90)
        #expect(isClose(negative.heading, -90)) // stored negative, not folded to 270
    }

    // MARK: Item 3 — pointInDirection is absolute, not relative

    @Test("pointInDirection sets an absolute heading a later move follows")
    func pointInDirectionIsAbsolute() {
        var needle = VirtualNeedle(heading: 0)
        needle.turnRight(45) // prior heading that an absolute set must discard
        needle.pointInDirection(180)
        #expect(isClose(needle.heading, 180))

        needle.moveNSteps(10)
        #expect(isClose(needle.position.x, 0))
        #expect(isClose(needle.position.y, -10))
    }

    // MARK: Item 4 — placeAt / setX / setY / changeXBy·changeYBy

    @Test("placeAt teleports; setX/setY move one axis; changeXBy accumulates")
    func placementAndSingleAxis() {
        var needle = VirtualNeedle()
        needle.placeAt(x: 100, y: 200)
        #expect(isClose(needle.position.x, 100))
        #expect(isClose(needle.position.y, 200))

        needle.setX(50)
        #expect(isClose(needle.position.x, 50))
        #expect(isClose(needle.position.y, 200)) // y untouched

        needle.setY(-30)
        #expect(isClose(needle.position.x, 50)) // x untouched
        #expect(isClose(needle.position.y, -30))

        var acc = VirtualNeedle()
        acc.changeXBy(5)
        acc.changeXBy(5)
        acc.changeYBy(-3)
        acc.changeYBy(-3)
        #expect(isClose(acc.position.x, 10))
        #expect(isClose(acc.position.y, -6))
    }

    // MARK: Item 5 — huge-heading periodic extension stays finite (ADR-014, US-108)

    @Test("a greatestFiniteMagnitude-scale heading yields a finite move, not NaN")
    func hugeHeadingStaysFinite() {
        var needle = VirtualNeedle(heading: .greatestFiniteMagnitude)
        needle.moveNSteps(10)
        #expect(needle.position.x.isFinite)
        #expect(needle.position.y.isFinite)
    }
}
