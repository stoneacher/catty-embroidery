import ProgramModel

public extension BrickKind {
    /// Catroid's palette condition for both Ifs, `1 < 2` (`CategoryBricksFactory.kt:361-380`).
    private static var defaultCondition: Formula {
        .binary(.smallerThan, .number(BrickDefaults.conditionLeft), .number(BrickDefaults.conditionRight))
    }

    /// Catroid's palette For loop, no variable chosen yet, from 1 to 10 (`BrickValues.java:93-94`).
    private static var defaultForLoop: Brick {
        .forVariableFromTo(
            name: BrickDefaults.variableName,
            from: .number(BrickDefaults.forLoopFrom),
            to: .number(BrickDefaults.forLoopTo)
        )
    }

    /// A new brick of this kind, seeded from `BrickDefaults` (Catroid
    /// `BrickValues.java`, ported verbatim — AGPL-3.0).
    ///
    /// Returns an **array** because a block opener yields its whole block: ADR-035
    /// inserts `[opener, .loopEnd]` together, and an If/Else
    /// `[opener, .elseBranch, .ifEnd]`, so a balanced script stays balanced by
    /// construction and `Script.validate()` is never needed as a repair.
    ///
    /// Total over every kind, including the markers `.loopEnd`, `.elseBranch` and
    /// `.ifEnd`. Note precisely what that does and does not claim:
    /// `BrickKind.loopEnd.template()` **is** `[.loopEnd]` (and likewise the other two),
    /// and appending it to a balanced script would unbalance it — `validate()`
    /// would throw `.unmatchedLoopEnd` at *that brick's own index*, which is `0`
    /// only when the script was empty. What keeps that unreachable is
    /// the *insertion* policy, not this function: ADR-035 and ADR-045 keep the
    /// markers out of the palette (US-409) and make inserting one a rejection.
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
        case .placeAt: [.placeAt(x: .number(BrickDefaults.placeAtX), y: .number(BrickDefaults.placeAtY))]
        case .setX: [.setX(.number(BrickDefaults.placeAtX))]
        case .setY: [.setY(.number(BrickDefaults.placeAtY))]
        case .changeXBy: [.changeXBy(.number(BrickDefaults.changeXBy))]
        case .changeYBy: [.changeYBy(.number(BrickDefaults.changeYBy))]
        case .arc: [.arc(direction: BrickDefaults.arcDirection, radius: .number(BrickDefaults.arcRadius),
                         degrees: .number(BrickDefaults.arcDegrees))]
        case .goThrough: [.goThrough(
                throughX: .number(BrickDefaults.goThroughThroughX),
                throughY: .number(BrickDefaults.goThroughThroughY),
                x: .number(BrickDefaults.goThroughX),
                y: .number(BrickDefaults.goThroughY)
            )]
        case .repeatLoop: [.repeatLoop(times: .number(BrickDefaults.repeatTimes)), .loopEnd]
        case .forever: [.forever, .loopEnd]
        case .repeatUntil: [.repeatUntil(condition: Self.defaultCondition), .loopEnd]
        case .forVariableFromTo: [Self.defaultForLoop, .loopEnd]
        case .loopEnd: [.loopEnd]
        case .wait: [.wait(seconds: .number(BrickDefaults.waitSeconds))]
        case .waitUntil: [.waitUntil(condition: Self.defaultCondition)]
        case .ifThen: [.ifThen(condition: Self.defaultCondition), .ifEnd]
        case .ifElse: [.ifElse(condition: Self.defaultCondition), .elseBranch, .ifEnd]
        case .elseBranch: [.elseBranch]
        case .ifEnd: [.ifEnd]
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
