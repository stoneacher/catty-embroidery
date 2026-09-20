import ProgramModel

public extension BrickKind {
    /// A new brick of this kind, seeded from `BrickDefaults` (Catroid
    /// `BrickValues.java`, ported verbatim — AGPL-3.0).
    ///
    /// Returns an **array** because a loop opener yields two bricks: ADR-035
    /// inserts `[opener, .loopEnd]` together so a balanced script stays balanced
    /// by construction and `Script.validate()` is never needed as a repair.
    ///
    /// Total over every kind, including `.loopEnd`. Note precisely what that
    /// does and does not claim: `BrickKind.loopEnd.template()` **is** `[.loopEnd]`,
    /// and appending it to a balanced script would unbalance it — `validate()`
    /// would throw `.unmatchedLoopEnd(index: 0)`. What keeps that unreachable is
    /// the *insertion* policy, not this function: ADR-035 keeps `.loopEnd` out of
    /// the palette (US-409) and makes `insert(.loopEnd, …)` a rejection (US-402).
    /// This function describes a kind's shape; authorising an edit is US-402's
    /// job. Exhaustive with no `default:`, so a new kind is a compile error
    /// rather than a missing template.
    ///
    /// Where two kinds share a constant, it is because **Catroid shares the same
    /// Java constant** — `setX`/`setY`/`placeAt` all take `X_POSITION`/
    /// `Y_POSITION`, and `tripleStitch`/`runningStitch` both take
    /// `STITCH_LENGTH`. Where Catroid has separate constants that merely happen
    /// to be equal (`CHANGE_X_BY` vs `MOVE_STEPS`), they stay separate here.
    func template() -> [Brick] {
        switch self {
        case .moveNSteps: [.moveNSteps(.number(BrickDefaults.moveSteps))]
        case .turnLeft: [.turnLeft(.number(BrickDefaults.turnDegrees))]
        case .turnRight: [.turnRight(.number(BrickDefaults.turnDegrees))]
        case .pointInDirection: [.pointInDirection(.number(BrickDefaults.pointInDirection))]
        case .placeAt: [.placeAt(
                x: .number(BrickDefaults.placeAtX),
                y: .number(BrickDefaults.placeAtY)
            )]
        case .setX: [.setX(.number(BrickDefaults.placeAtX))]
        case .setY: [.setY(.number(BrickDefaults.placeAtY))]
        case .changeXBy: [.changeXBy(.number(BrickDefaults.changeXBy))]
        case .changeYBy: [.changeYBy(.number(BrickDefaults.changeYBy))]
        case .repeatLoop: [.repeatLoop(times: .number(BrickDefaults.repeatTimes)), .loopEnd]
        case .forever: [.forever, .loopEnd]
        case .loopEnd: [.loopEnd]
        case .wait: [.wait(seconds: .number(BrickDefaults.waitSeconds))]
        case .setVariable: [.setVariable(
                name: BrickDefaults.variableName,
                to: .number(BrickDefaults.setVariableValue)
            )]
        case .changeVariableBy: [.changeVariableBy(
                name: BrickDefaults.variableName,
                value: .number(BrickDefaults.changeVariableByValue)
            )]
        case .stitch: [.stitch]
        case .setThreadColor: [.setThreadColor(hex: BrickDefaults.threadColorHex)]
        case .runningStitch: [.runningStitch(length: .number(BrickDefaults.stitchLength))]
        case .zigZagStitch: [.zigZagStitch(
                length: .number(BrickDefaults.zigZagLength),
                width: .number(BrickDefaults.zigZagWidth)
            )]
        case .tripleStitch: [.tripleStitch(length: .number(BrickDefaults.stitchLength))]
        case .sewUp: [.sewUp]
        case .stopRunningStitch: [.stopRunningStitch]
        case .writeEmbroideryToFile:
            [.writeEmbroideryToFile(name: BrickDefaults.embroideryFileName)]
        }
    }
}
