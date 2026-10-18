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

    private func run(_ objects: [Object], projectVariables: [Variable] = []) -> [InterpreterEvent] {
        let program = Program(scenes: [Scene(objects: objects)], variables: projectVariables)
        var interpreter = Interpreter(program: program, clock: clock)
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

    /// One needle per object, one action per script per tick (ADR-018): the
    /// second script reads the first one's tick-1 move, not its tick-2 move. A
    /// run-to-completion scheduler would read 9 (Codex slice review of slice 3).
    @Test("two scripts on one object share its needle, tick by tick")
    func scriptsShareTheNeedle() {
        let positions = finalPositions(run([Object(scripts: [
            Script(bricks: [.setX(.number(7)), .setX(.number(9))]),
            Script(bricks: [.setY(.sensor(.objectX))])
        ])]))
        #expect(positions == [0: StagePoint(x: 9, y: 7)])
    }

    /// Objects run in creation order within a tick (ADR-018): object 1 reads
    /// what object 0 published from its own needle in the same tick, through a
    /// project variable (an undeclared name would land in object 0's own store).
    @Test("a later object sees an earlier object's sensor value in the same tick")
    func objectsRunInCreationOrder() {
        let positions = finalPositions(run([
            Object(startX: 10, scripts: [Script(bricks: [.setVariable(name: "p", to: .sensor(.objectX))])]),
            Object(scripts: [Script(bricks: [.setY(.variable("p"))])])
        ], projectVariables: [Variable(name: "p")]))
        #expect(positions[1] == StagePoint(x: 0, y: 10))
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

    /// Catroid's direction is never `−0` (its fold runs on `90 − ((−d + 90) % 360)`,
    /// which cannot be a negative zero), and `−0` is observable: `arctan2(−0, −1)`
    /// is −180° where `arctan2(+0, −1)` is 180° (`swift-code-reviewer`, slice 3).
    @Test("motion direction is never negative zero", arguments: [-360.0, -720, 0, 360])
    func directionNeverNegativeZero(_ heading: Double) {
        let position = finalPosition(of: [
            .pointInDirection(.number(heading)),
            .setX(.binaryFunction(.arctan2, .sensor(.motionDirection), .number(-1)))
        ])
        #expect(position?.x == 180)
    }

    /// A needle can reach ±∞ (`changeXBy(MAX)` twice; positions are not capped),
    /// and a sensor read is normalized like any other node (ADR-017): `MAX − MAX`
    /// is 0, so the y below is 5. Without the cap it is `∞ − ∞`, NaN, and the
    /// brick is skipped (`swift-code-reviewer`, slice 3).
    @Test("a sensor read is normalized")
    func sensorIsNormalized() {
        let position = finalPosition(of: [
            .changeXBy(.number(.greatestFiniteMagnitude)),
            .changeXBy(.number(.greatestFiniteMagnitude)),
            .setY(.binary(.plus, .binary(.minus, .sensor(.objectX), .sensor(.objectX)), .number(5)))
        ])
        #expect(position?.y == 5)
    }

    /// A `wait` reads its duration through the same scope: waiting `objectX`
    /// seconds behaves exactly like waiting the literal. A concurrent script
    /// moving every tick makes the timing visible in the event order (Codex
    /// slice review of slice 3).
    @Test("a sensor drives a wait duration")
    func sensorInWait() {
        func events(waiting duration: Formula) -> [InterpreterEvent] {
            run([Object(scripts: [
                Script(bricks: [.setX(.number(0.2)), .wait(seconds: duration), .setY(.number(5))]),
                Script(bricks: [.repeatLoop(times: .number(8)), .changeYBy(.number(1)), .loopEnd])
            ])])
        }
        let viaSensor = events(waiting: .sensor(.objectX))
        #expect(viaSensor == events(waiting: .number(0.2)))
        #expect(viaSensor != events(waiting: .number(0)))
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
