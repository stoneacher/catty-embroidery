import EditorCore
import ProgramModel
import Testing

/// US-401 test-plan item 5: every template's parameters are seeded from
/// `BrickDefaults`, asserted **against the constants by name** so a change to a
/// default cannot leave this suite passing against a stale re-typed literal.
///
/// The limitation is stated rather than implied, because the story states it:
/// this proves *"the template tracks the constant if the constant changes"*, and
/// nothing more. It does **not** prove the implementation references the
/// constant — rewriting `.number(BrickDefaults.changeXBy)` as `.number(10)`
/// leaves every assertion here green, because the values are equal today.
/// Mutation M9 executes exactly that and records the green as evidence. A
/// structural check over the source is the alternative if the stronger
/// guarantee is ever wanted; this story claims only the weaker one.
///
/// The Catroid values themselves are pinned once, in
/// `ProgramModelTests/BrickTests.brickDefaultsMatchCatroid`, beside the
/// constants they belong to — not duplicated here (ADR-032 invariant 3).
@Suite("Brick templates seed from BrickDefaults")
struct BrickTemplateDefaultsTests {
    struct TemplateExpectation: Sendable {
        let kind: BrickKind
        let bricks: [Brick]
    }

    static let expectations: [TemplateExpectation] = [
        .init(kind: .moveNSteps, bricks: [.moveNSteps(.number(BrickDefaults.moveSteps))]),
        .init(kind: .turnLeft, bricks: [.turnLeft(.number(BrickDefaults.turnDegrees))]),
        .init(kind: .turnRight, bricks: [.turnRight(.number(BrickDefaults.turnDegrees))]),
        // Catroid's POINT_IN_DIRECTION is 90, *not* TURN_DEGREES' 15 — reusing
        // the existing angle constant would ship a different default direction.
        .init(
            kind: .pointInDirection,
            bricks: [.pointInDirection(.number(BrickDefaults.pointInDirection))]
        ),
        .init(kind: .placeAt, bricks: [
            .placeAt(x: .number(BrickDefaults.placeAtX), y: .number(BrickDefaults.placeAtY))
        ]),
        // setX/setY reuse placeAtX/placeAtY because *Catroid* reuses the same
        // Java constants (X_POSITION/Y_POSITION) for all three bricks.
        .init(kind: .setX, bricks: [.setX(.number(BrickDefaults.placeAtX))]),
        .init(kind: .setY, bricks: [.setY(.number(BrickDefaults.placeAtY))]),
        // changeXBy/changeYBy do *not* reuse moveSteps, though all three are 10:
        // Catroid has separate CHANGE_X_BY/CHANGE_Y_BY constants, and equal
        // values today are not the same decision.
        .init(kind: .changeXBy, bricks: [.changeXBy(.number(BrickDefaults.changeXBy))]),
        .init(kind: .changeYBy, bricks: [.changeYBy(.number(BrickDefaults.changeYBy))]),
        .init(kind: .repeatLoop, bricks: [
            .repeatLoop(times: .number(BrickDefaults.repeatTimes)), .loopEnd
        ]),
        .init(kind: .forever, bricks: [.forever, .loopEnd]),
        .init(kind: .loopEnd, bricks: [.loopEnd]),
        .init(kind: .wait, bricks: [.wait(seconds: .number(BrickDefaults.waitSeconds))]),
        .init(kind: .setVariable, bricks: [
            .setVariable(
                name: BrickDefaults.variableName,
                to: .number(BrickDefaults.setVariableValue)
            )
        ]),
        .init(kind: .changeVariableBy, bricks: [
            .changeVariableBy(
                name: BrickDefaults.variableName,
                value: .number(BrickDefaults.changeVariableByValue)
            )
        ]),
        .init(kind: .stitch, bricks: [.stitch]),
        .init(kind: .setThreadColor, bricks: [.setThreadColor(hex: BrickDefaults.threadColorHex)]),
        .init(kind: .runningStitch, bricks: [
            .runningStitch(length: .number(BrickDefaults.stitchLength))
        ]),
        .init(kind: .zigZagStitch, bricks: [
            .zigZagStitch(
                length: .number(BrickDefaults.zigZagLength),
                width: .number(BrickDefaults.zigZagWidth)
            )
        ]),
        // tripleStitch reuses stitchLength because Catroid does: both
        // RunningStitchBrick and TripleStitchBrick take STITCH_LENGTH.
        .init(kind: .tripleStitch, bricks: [
            .tripleStitch(length: .number(BrickDefaults.stitchLength))
        ]),
        .init(kind: .sewUp, bricks: [.sewUp]),
        .init(kind: .stopRunningStitch, bricks: [.stopRunningStitch]),
        .init(kind: .writeEmbroideryToFile, bricks: [
            .writeEmbroideryToFile(name: BrickDefaults.embroideryFileName)
        ])
    ]

    @Test(
        "each template's parameters equal their BrickDefaults constants",
        arguments: BrickTemplateDefaultsTests.expectations
    )
    func everyTemplateSeedsItsParametersFromBrickDefaults(_ row: TemplateExpectation) {
        #expect(row.kind.template() == row.bricks)
    }

    /// Enumeration, not a hand-written list: a new `BrickKind` without a row
    /// above fails here rather than escaping the suite silently. Same house
    /// style as M4 exit criterion 2.
    @Test("the expectation table covers every kind")
    func templateExpectationsCoverEveryKind() {
        #expect(Set(Self.expectations.map(\.kind)) == Set(BrickKind.allCases))
    }
}
