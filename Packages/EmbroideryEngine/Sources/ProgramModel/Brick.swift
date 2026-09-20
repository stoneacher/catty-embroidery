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

    // MARK: US-401 additions — the rest of what the M4 palette seeds

    public static let repeatTimes: Double = 10 // REPEAT
    /// Catroid's own constant, **not** `turnDegrees`: `POINT_IN_DIRECTION` is 90
    /// and `TURN_DEGREES` is 15, so reusing the existing angle would ship a
    /// different default direction.
    public static let pointInDirection: Double = 90 // POINT_IN_DIRECTION
    /// `CHANGE_X_BY`/`CHANGE_Y_BY` are separate constants in Catroid that merely
    /// happen to equal `MOVE_STEPS`. Named separately here for the same reason:
    /// equal values today are not the same decision.
    public static let changeXBy: Double = 10 // CHANGE_X_BY
    public static let changeYBy: Double = 10 // CHANGE_Y_BY
    /// Catroid has two distinct constants for the two variable bricks, both
    /// `1d` — the same shape as `CHANGE_X_BY`/`CHANGE_Y_BY`, so they get two
    /// names rather than one shared value.
    public static let setVariableValue: Double = 1 // SET_VARIABLE
    public static let changeVariableByValue: Double = 1 // CHANGE_VARIABLE
    /// **No Catroid counterpart.** `SetVariableBrick(double)` seeds only the
    /// value formula and leaves the variable unset; the brick's spinner then
    /// offers the project's existing variables. Our `Brick.setVariable(name:)`
    /// is non-optional, so `""` is the model's honest spelling of "no variable
    /// chosen yet" rather than an invented English name. It cannot misbehave —
    /// `VariableScope.value(of:)` resolves an unknown name to 0 (Catroid
    /// `Conversions.FALSE` parity). It does carry a UI obligation: US-407's row
    /// and US-410's editor must render the empty name as a placeholder.
    public static let variableName = ""
    /// **No `BrickValues` counterpart**: Catroid localises this one
    /// (`R.string.brick_default_embroidery_file`, `strings.xml` = "embroidery.dst"),
    /// the same pattern its own closing comment notes for the "Send web request"
    /// brick. Kept a plain Swift constant here — it is a filename, and
    /// `ProgramModel` ships no localized resources.
    public static let embroideryFileName = "embroidery.dst"
}
