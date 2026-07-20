/// One instruction in a flat script list (Catroid `Brick`). Control bricks are
/// begin/end pairs in the same list — `repeatLoop`/`forever` open a loop and a
/// later `loopEnd` closes it (ADR-008); nesting is a rendering concern, not a
/// type-level tree. `Codable` and `Equatable` are synthesized; the latter
/// delegates to `Formula`'s NaN-aware `==`, so whole-`Program` equality stays
/// reflexive. Declared `indirect` per the US-203 model contract.
///
/// Case order mirrors Catroid's brick categories; the embroidery cases follow
/// `CategoryBricksFactory.setupEmbroideryCategoryList`.
public indirect enum Brick: Sendable, Equatable, Codable {
    // MARK: Motion (Catroid motion category)

    case moveNSteps(Formula)
    case turnLeft(Formula)
    case turnRight(Formula)
    case pointInDirection(Formula)
    case placeAt(x: Formula, y: Formula)
    case setX(Formula)
    case setY(Formula)
    case changeXBy(Formula)
    case changeYBy(Formula)

    // MARK: Control (Catroid control category)

    /// Opens a counted loop; closed by a later `loopEnd` (Catroid `RepeatBrick`).
    case repeatLoop(times: Formula)
    /// Opens an infinite loop; closed by a later `loopEnd` (Catroid `ForeverBrick`).
    case forever
    /// Closes the nearest open loop. A pure marker retained in the model — never
    /// dropped or synthesized away (ADR-008; Catroid `LoopEndBrick` contributes
    /// no action but terminates the loop in the flat list).
    case loopEnd
    case wait(seconds: Formula)

    // MARK: Data (Catroid data category)

    case setVariable(name: String, to: Formula)
    case changeVariableBy(name: String, value: Formula)

    // MARK: Embroidery (setupEmbroideryCategoryList order)

    case stitch
    case setThreadColor(hex: String)
    case runningStitch(length: Formula)
    case zigZagStitch(length: Formula, width: Formula)
    case tripleStitch(length: Formula)
    case sewUp
    case stopRunningStitch
    case writeEmbroideryToFile(name: String)
}

/// Catroid `common/BrickValues.java` defaults, ported verbatim (AGPL-3.0), that
/// the M4 editor seeds new bricks with. Angles are degrees, positions/lengths
/// stage units; `waitSeconds` is Catroid's `WAIT` (1000 ms) expressed in the
/// seconds the `wait` brick uses.
public enum BrickDefaults {
    public static let moveSteps: Double = 10 // MOVE_STEPS
    public static let turnDegrees: Double = 15 // TURN_DEGREES
    public static let placeAtX: Double = 100 // X_POSITION
    public static let placeAtY: Double = 200 // Y_POSITION
    public static let stitchLength: Double = 10 // STITCH_LENGTH (running & triple)
    public static let zigZagLength: Double = 2 // ZIGZAG_STITCH_LENGTH
    public static let zigZagWidth: Double = 10 // ZIGZAG_STITCH_WIDTH
    public static let threadColorHex = "#ff0000" // THREAD_COLOR
    public static let waitSeconds: Double = 1.0 // WAIT (1000 ms)
}
