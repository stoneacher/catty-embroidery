import EmbroideryEngine
import Foundation
import Interpreter
import ProgramModel
import Testing

/// Brick backend slice 5: Catroid's GoThrough (`content/actions/GoThroughAction.kt`),
/// a quadratic Bézier from the needle to the destination whose control point
/// `A = 2T − (S + E)/2` makes it pass through T at t = ½. Same rules as Arc
/// (ADR-047): samples i = 1…100, feed on change, chord heading, compute then
/// commit, catch-and-skip.
@Suite("GoThrough")
struct GoThroughTests {
    private let scope = VariableScope()
    private let throwing = Formula.binary(.divide, .number(0), .number(0))

    private static func goThrough(_ throughX: Double, _ throughY: Double, _ x: Double, _ y: Double) -> Brick {
        .goThrough(throughX: .number(throughX), throughY: .number(throughY), x: .number(x), y: .number(y))
    }

    private func close(_ lhs: Double, _ rhs: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    private func updates(
        _ brick: Brick, from position: StagePoint = StagePoint(x: 0, y: 0), heading: Double = 0
    ) throws -> (updates: [NeedleUpdate], needle: VirtualNeedle) {
        var needle = VirtualNeedle(position: position, heading: heading)
        let emitted = needle.apply(brick, scope: scope)
        let updates = try #require(emitted)
        return (updates, needle)
    }

    @Test("the curve passes through its point halfway and ends exactly on its destination")
    func throughAndEnd() throws {
        let start = StagePoint(x: 3, y: -4)
        let (updates, needle) = try updates(Self.goThrough(50, 100, 100, 0), from: start, heading: 20)
        #expect(updates.count == 100)
        #expect(close(updates[49].position.x, 50) && close(updates[49].position.y, 100))
        #expect(needle.position == StagePoint(x: 100, y: 0))
        #expect(updates.last?.position == StagePoint(x: 100, y: 0))
    }

    @Test("every update faces along the chord leading to it")
    func everyUpdateFacesItsChord() throws {
        let start = StagePoint(x: -20, y: 7)
        let (updates, needle) = try updates(Self.goThrough(10, 60, 40, -30), from: start, heading: 75)
        var previous = start
        for update in updates {
            let bearing = atan2(update.position.x - previous.x, update.position.y - previous.y) * 180 / .pi
            #expect(close(update.heading, bearing), "\(update)")
            previous = update.position
        }
        #expect(needle.heading == updates.last?.heading)
    }

    /// Catroid's defaults (0, 0, 0, 0) from the origin: every sample is the
    /// start, nothing is fed, one unchanged update.
    @Test("a curve that never leaves the needle emits one unchanged update")
    func degenerate() throws {
        let (updates, needle) = try updates(Self.goThrough(0, 0, 0, 0), heading: 42)
        #expect(updates == [NeedleUpdate(position: StagePoint(x: 0, y: 0), heading: 42)])
        #expect(needle == VirtualNeedle(heading: 42))
    }

    /// A Catroid characterization: through the origin and back to it from
    /// (100, 0), the control point is (−50, 0), so the curve overshoots to
    /// x = 100·(1 − t)(1 − 2t) = −12.5 at t = ¾ before returning.
    @Test("the defaults from (100, 0) overshoot to −12.5 at three quarters")
    func overshoot() throws {
        let (updates, needle) = try updates(Self.goThrough(0, 0, 0, 0), from: StagePoint(x: 100, y: 0))
        #expect(close(updates[74].position.x, -12.5))
        #expect(needle.position == StagePoint(x: 0, y: 0))
    }

    @Test("a bad formula in any field skips the curve", arguments: 0 ..< 4)
    func badFormulaSkips(_ field: Int) throws {
        var values = [Formula.number(10), .number(20), .number(30), .number(40)]
        values[field] = throwing
        let brick = Brick.goThrough(throughX: values[0], throughY: values[1], x: values[2], y: values[3])
        let start = StagePoint(x: 1, y: 2)
        let (updates, needle) = try updates(brick, from: start, heading: 15)
        #expect(updates == [NeedleUpdate(position: start, heading: 15)])
        #expect(needle == VirtualNeedle(position: start, heading: 15))
    }

    /// The control point `2T − (S + E)/2` overflows for T = MAX; nothing is
    /// committed, so the needle never holds a non-finite coordinate.
    @Test("a curve whose samples overflow leaves the needle unchanged")
    func overflowSkips() throws {
        let (updates, needle) = try updates(Self.goThrough(.greatestFiniteMagnitude, 0, 10, 0), heading: 5)
        #expect(updates == [NeedleUpdate(position: StagePoint(x: 0, y: 0), heading: 5)])
        #expect(needle == VirtualNeedle(heading: 5))
    }

    @Test("a GoThrough costs one tick")
    func oneTick() {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
            Self.goThrough(50, 100, 100, 0), .moveNSteps(.number(5))
        ])])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        guard case let .ticked(first) = interpreter.step(), case let .ticked(second) = interpreter.step() else {
            Issue.record("expected two ticks")
            return
        }
        #expect(first.count {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        } == 100)
        #expect(second.count {
            if case .needleMoved = $0 {
                true
            } else {
                false
            }
        } == 1)
    }

    // MARK: - Android golden export

    /// Sebastian's `go_through` export. Its straight second curve, from (100, 0)
    /// to (−100, 0), ends without a stitch at −100: Android's last stitch is at −90
    /// although 200 is a multiple of the stitch length. This test decides whether
    /// the `Double` needle does the same.
    @Test("running stitch along two curves matches the Android export")
    func androidGoThrough() throws {
        let ours = try interpretedRecords([
            .runningStitch(length: .number(10)),
            Self.goThrough(50, 100, 100, 0),
            Self.goThrough(0, 0, -100, 0)
        ])
        try expectMatchesAndroid(ours, decodeRecordPositions(AndroidReference.data("go_through")))
    }
}
