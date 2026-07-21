import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-204 test-plan item 5 (emission + per-brick bad-formula fallback): the
/// model↔engine bridge `VirtualNeedle.apply(_:scope:)`. Every executed motion
/// brick returns exactly one `NeedleUpdate`; the fallback is per-brick, mirroring
/// the corresponding Catroid action — catch-and-skip for most motion bricks,
/// per-coordinate zero-substitution for `placeAt` (its Catroid `GlideToAction`
/// coerces a failed coordinate to 0). A non-motion brick returns nil.
@Suite("Virtual needle brick application")
struct VirtualNeedleBrickTests {
    /// A formula that always throws `FormulaError.notANumber` (0/0 → NaN root).
    private let throwing = Formula.binary(.divide, .number(0), .number(0))
    private let scope = VariableScope()

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    // MARK: A motion brick emits exactly one update matching the new state (AC 4)

    @Test("a valid motion brick returns one NeedleUpdate carrying the new needle state")
    func motionBrickEmitsMatchingUpdate() throws {
        var needle = VirtualNeedle(heading: 0)
        let emitted = needle.apply(.moveNSteps(.number(10)), scope: scope)
        let update = try #require(emitted)
        #expect(isClose(needle.position.y, 10))
        #expect(update.position == needle.position)
        #expect(update.heading == needle.heading)
    }

    // MARK: Catch-and-skip still emits one update carrying the UNCHANGED state

    @Test("a throwing moveNSteps leaves the needle unchanged but still emits one update")
    func throwingMoveSkipsButStillEmits() throws {
        var needle = VirtualNeedle(position: .init(x: 7, y: -3), heading: 42)
        let before = needle
        let emitted = needle.apply(.moveNSteps(throwing), scope: scope)
        let update = try #require(emitted)
        #expect(needle == before) // position AND heading untouched
        #expect(update.position == before.position)
        #expect(update.heading == before.heading)
    }

    @Test("a throwing turnRight leaves the heading unchanged but still emits one update")
    func throwingTurnSkipsButStillEmits() throws {
        var needle = VirtualNeedle(heading: 42)
        let before = needle
        let emitted = needle.apply(.turnRight(throwing), scope: scope)
        let update = try #require(emitted)
        #expect(needle == before) // fallback is uniform across motion bricks, not move-specific
        #expect(update.heading == before.heading)
    }

    // MARK: Each motion arm dispatches to its own needle method (ADR-016 seam)

    @Test("apply routes every motion brick to its matching needle mutation")
    func everyMotionArmDispatchesCorrectly() {
        var turnedRight = VirtualNeedle(heading: 0)
        _ = turnedRight.apply(.turnRight(.number(90)), scope: scope)
        #expect(isClose(turnedRight.heading, 90)) // adds

        var turnedLeft = VirtualNeedle(heading: 0)
        _ = turnedLeft.apply(.turnLeft(.number(90)), scope: scope)
        #expect(isClose(turnedLeft.heading, -90)) // subtracts

        var pointed = VirtualNeedle(heading: 33)
        _ = pointed.apply(.pointInDirection(.number(180)), scope: scope)
        #expect(isClose(pointed.heading, 180)) // absolute, discards prior

        var moved = VirtualNeedle(heading: 0)
        _ = moved.apply(.moveNSteps(.number(10)), scope: scope)
        #expect(isClose(moved.position.y, 10)) // heading 0 → +y

        var xSet = VirtualNeedle(position: .init(x: 1, y: 2))
        _ = xSet.apply(.setX(.number(5)), scope: scope)
        #expect(isClose(xSet.position.x, 5))
        #expect(isClose(xSet.position.y, 2)) // y untouched

        var ySet = VirtualNeedle(position: .init(x: 1, y: 2))
        _ = ySet.apply(.setY(.number(5)), scope: scope)
        #expect(isClose(ySet.position.x, 1)) // x untouched
        #expect(isClose(ySet.position.y, 5))

        var xChanged = VirtualNeedle(position: .init(x: 10, y: 0))
        _ = xChanged.apply(.changeXBy(.number(5)), scope: scope)
        #expect(isClose(xChanged.position.x, 15)) // accumulates

        var yChanged = VirtualNeedle(position: .init(x: 0, y: 10))
        _ = yChanged.apply(.changeYBy(.number(5)), scope: scope)
        #expect(isClose(yChanged.position.y, 15)) // accumulates
    }

    // MARK: placeAt zero-substitutes each failed coordinate independently (NOT a no-op)

    @Test("placeAt with a throwing x and valid y places the needle at (0, y)")
    func placeAtZeroSubstitutesFailedCoordinate() throws {
        var needle = VirtualNeedle(position: .init(x: 99, y: 99))
        let emitted = needle.apply(.placeAt(x: throwing, y: .number(200)), scope: scope)
        let update = try #require(emitted)
        #expect(isClose(needle.position.x, 0)) // bad x → 0, not left at 99
        #expect(isClose(needle.position.y, 200))
        #expect(update.position == needle.position)
    }

    @Test("placeAt substitutes per-coordinate: good x + bad y ⇒ (x, 0); both bad ⇒ (0, 0)")
    func placeAtSubstitutesPerCoordinate() throws {
        var goodXBadY = VirtualNeedle(position: .init(x: 9, y: 9))
        let goodXBadYUpdate = goodXBadY.apply(.placeAt(x: .number(50), y: throwing), scope: scope)
        _ = try #require(goodXBadYUpdate)
        #expect(isClose(goodXBadY.position.x, 50)) // good x kept
        #expect(isClose(goodXBadY.position.y, 0)) // bad y → 0

        var bothBad = VirtualNeedle(position: .init(x: 9, y: 9))
        let bothBadUpdate = bothBad.apply(.placeAt(x: throwing, y: throwing), scope: scope)
        _ = try #require(bothBadUpdate)
        #expect(isClose(bothBad.position.x, 0))
        #expect(isClose(bothBad.position.y, 0))
    }

    // MARK: Non-motion brick is a classification signal (nil), never a crash

    @Test("a non-motion brick returns nil")
    func nonMotionBrickReturnsNil() {
        var needle = VirtualNeedle()
        let result = needle.apply(.stitch, scope: scope)
        #expect(result == nil)
    }

    // MARK: Catch-and-skip is uniform across every motion brick (no accidental zeroing)

    @Test("a throwing formula leaves every motion brick's state unchanged and still emits")
    func throwingFormulaSkipsEveryBrick() {
        let start = VirtualNeedle(position: .init(x: 7, y: 3), heading: 42)
        let bricks: [Brick] = [
            .moveNSteps(throwing), .turnLeft(throwing), .turnRight(throwing),
            .pointInDirection(throwing), .setX(throwing), .setY(throwing),
            .changeXBy(throwing), .changeYBy(throwing)
        ]
        for brick in bricks {
            var needle = start
            let emitted = needle.apply(brick, scope: scope)
            #expect(emitted != nil) // still exactly one update
            #expect(needle == start) // untouched — NOT zeroed
        }
    }

    // MARK: Formulas are evaluated against the supplied scope, not ignored

    @Test("apply evaluates a variable formula against the supplied scope")
    func evaluatesAgainstSuppliedScope() {
        let scoped = VariableScope(projectVariables: [Variable(name: "n", value: 10)])
        var needle = VirtualNeedle(heading: 90) // heading 90° → move advances +x
        _ = needle.apply(.moveNSteps(.variable("n")), scope: scoped)
        #expect(isClose(needle.position.x, 10))
        #expect(isClose(needle.position.y, 0))
    }
}
