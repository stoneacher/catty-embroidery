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
        let update = try #require(needle.apply(.moveNSteps(.number(10)), scope: scope))
        #expect(isClose(needle.position.y, 10))
        #expect(update.position == needle.position)
        #expect(update.heading == needle.heading)
    }

    // MARK: Catch-and-skip still emits one update carrying the UNCHANGED state

    @Test("a throwing moveNSteps leaves the needle unchanged but still emits one update")
    func throwingMoveSkipsButStillEmits() throws {
        var needle = VirtualNeedle(position: .init(x: 7, y: -3), heading: 42)
        let before = needle
        let update = try #require(needle.apply(.moveNSteps(throwing), scope: scope))
        #expect(needle == before) // position AND heading untouched
        #expect(update.position == before.position)
        #expect(update.heading == before.heading)
    }

    // MARK: placeAt zero-substitutes the failed coordinate (NOT a no-op)

    @Test("placeAt with a throwing x and valid y places the needle at (0, y)")
    func placeAtZeroSubstitutesFailedCoordinate() throws {
        var needle = VirtualNeedle(position: .init(x: 99, y: 99))
        let update = try #require(
            needle.apply(.placeAt(x: throwing, y: .number(200)), scope: scope)
        )
        #expect(isClose(needle.position.x, 0)) // bad x → 0, not left at 99
        #expect(isClose(needle.position.y, 200))
        #expect(update.position == needle.position)
    }

    // MARK: Non-motion brick is a classification signal (nil), never a crash

    @Test("a non-motion brick returns nil")
    func nonMotionBrickReturnsNil() {
        var needle = VirtualNeedle()
        #expect(needle.apply(.stitch, scope: scope) == nil)
    }
}
