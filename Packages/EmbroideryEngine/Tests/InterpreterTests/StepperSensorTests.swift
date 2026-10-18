import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Brick backend slice 3: formulas read the acting object's own needle
/// (ADR-046, brief D4). Each sensor value is observed through the needle itself
/// (`setX(.sensor(…))` moves x to the value read), so every assertion is on
/// interpreter output.
@Suite("Stepper sensors")
struct StepperSensorTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    private func run(_ objects: [Object]) -> [InterpreterEvent] {
        var interpreter = Interpreter(program: Program(scenes: [Scene(objects: objects)]), clock: clock)
        return interpreter.run(maxTicks: 100)
    }

    /// The last position each actor's needle reported, by actor index.
    private func finalPositions(_ events: [InterpreterEvent]) -> [Int: StagePoint] {
        var positions: [Int: StagePoint] = [:]
        for case let .needleMoved(actor, update) in events {
            positions[actor.rawValue] = update.position
        }
        return positions
    }

    private func finalPosition(of bricks: [Brick], startHeading: Double = 0) -> StagePoint? {
        finalPositions(run([Object(startHeading: startHeading, scripts: [Script(bricks: bricks)])]))[0]
    }

    @Test("object x and y read the needle after earlier moves")
    func positionAfterMoves() {
        let position = finalPosition(of: [
            .placeAt(x: .number(3), y: .number(4)),
            .changeXBy(.number(10)),
            .setVariable(name: "v", to: .sensor(.objectX)),
            .setY(.variable("v"))
        ])
        #expect(position == StagePoint(x: 13, y: 13))
    }

    /// The scope is built before the brick applies, so both coordinates read the
    /// needle as it was: `placeAt(objectY, objectX)` swaps them.
    @Test("a brick reads the needle as it was before it moved")
    func readBeforeMutate() {
        let position = finalPosition(of: [
            .placeAt(x: .number(3), y: .number(4)),
            .placeAt(x: .sensor(.objectY), y: .sensor(.objectX))
        ])
        #expect(position == StagePoint(x: 4, y: 3))
    }

    @Test("each object reads its own needle")
    func objectsReadTheirOwnNeedle() {
        let positions = finalPositions(run([
            Object(startX: 10, scripts: [Script(bricks: [.setY(.sensor(.objectX))])]),
            Object(startX: -5, scripts: [Script(bricks: [.setY(.sensor(.objectX))])])
        ]))
        #expect(positions == [0: StagePoint(x: 10, y: 10), 1: StagePoint(x: -5, y: -5)])
    }

    /// One needle per object (ADR-018): a second script sees the first one's
    /// move, run before it in the same tick.
    @Test("two scripts on one object share its needle")
    func scriptsShareTheNeedle() {
        let positions = finalPositions(run([Object(scripts: [
            Script(bricks: [.placeAt(x: .number(7), y: .number(0))]),
            Script(bricks: [.setY(.sensor(.objectX))])
        ])]))
        #expect(positions == [0: StagePoint(x: 7, y: 7)])
    }

    /// Catroid's `MOTION_DIRECTION` is folded into (−180, 180]
    /// (`Look.breakDownCatroidAngle`), while the needle keeps (−360, 360).
    @Test("motion direction folds into (−180, 180]", arguments: [
        (Brick.turnRight(.number(270)), -90.0),
        (.turnLeft(.number(180)), 180),
        (.pointInDirection(.number(540)), 180),
        (.pointInDirection(.number(-180)), 180),
        (.turnLeft(.number(190)), 170),
        (.pointInDirection(.number(180.5)), -179.5),
        (.pointInDirection(.number(90)), 90)
    ])
    func directionFolds(_ turn: Brick, _ expected: Double) {
        let position = finalPosition(of: [turn, .setX(.sensor(.motionDirection))])
        #expect(position?.x == expected)
    }

    /// The start heading reaches the needle unreduced (no turn has normalized
    /// it yet), so the fold must reduce mod 360 first: 900° is 180°, not 540°.
    @Test("motion direction starts at the object's start heading, folded", arguments: [
        (270.0, -90.0), (900, 180), (-900, 180), (-1000, 80)
    ])
    func directionFromStartHeading(_ startHeading: Double, _ expected: Double) {
        let position = finalPosition(of: [.setX(.sensor(.motionDirection))], startHeading: startHeading)
        #expect(position?.x == expected)
    }

    /// Sensors reach every formula the stepper evaluates, not only motion: a
    /// `repeat` count is read when the loop is entered.
    @Test("a sensor drives a repeat count")
    func sensorInRepeat() {
        let position = finalPosition(of: [
            .setX(.number(3)),
            .repeatLoop(times: .sensor(.objectX)),
            .changeYBy(.number(1)),
            .loopEnd
        ])
        #expect(position == StagePoint(x: 3, y: 3))
    }
}
