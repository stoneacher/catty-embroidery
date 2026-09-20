import ProgramModel

/// A payload-free mirror of `Brick` — the spine of the M4 editor. Palette rows
/// (US-409), the same-kind guard on `replaceBrick` (US-402) and row labels
/// (US-407) all key off it, none of which needs a brick's parameters.
///
/// **`.loopEnd` has a kind, and deleting the case is not a fix.** ADR-035's
/// "`.loopEnd` is never in the palette" is a statement about the palette — a
/// curated subset US-409 owns — not about this enum. A `loopEnd` is an ordinary
/// `Brick` that the script list renders and whose kind US-402's guard must be
/// able to compute.
///
/// **Deliberately not `Codable`.** ADR-033's whole argument is that
/// `ProgramModel`'s public API *is* the serialized format and `EditorCore`'s is
/// not; a `Codable` `BrickKind` would invite someone to persist it and make
/// that distinction stop being true.
public enum BrickKind: Sendable, Hashable, CaseIterable {
    // MARK: Motion

    case moveNSteps
    case turnLeft
    case turnRight
    case pointInDirection
    case placeAt
    case setX
    case setY
    case changeXBy
    case changeYBy

    // MARK: Control

    case repeatLoop
    case forever
    case loopEnd
    case wait

    // MARK: Data

    case setVariable
    case changeVariableBy

    // MARK: Embroidery

    case stitch
    case setThreadColor
    case runningStitch
    case zigZagStitch
    case tripleStitch
    case sewUp
    case stopRunningStitch
    case writeEmbroideryToFile

    /// The kind of an existing brick.
    ///
    /// Exhaustive with **no `default:`** — the pattern `RunBatch.reducing` uses —
    /// so adding a `Brick` case is a compile error here rather than a silent gap.
    /// Associated values are deliberately not bound: this mapping discards them.
    public init(of brick: Brick) {
        switch brick {
        case .moveNSteps: self = .moveNSteps
        case .turnLeft: self = .turnLeft
        case .turnRight: self = .turnRight
        case .pointInDirection: self = .pointInDirection
        case .placeAt: self = .placeAt
        case .setX: self = .setX
        case .setY: self = .setY
        case .changeXBy: self = .changeXBy
        case .changeYBy: self = .changeYBy
        case .repeatLoop: self = .repeatLoop
        case .forever: self = .forever
        case .loopEnd: self = .loopEnd
        case .wait: self = .wait
        case .setVariable: self = .setVariable
        case .changeVariableBy: self = .changeVariableBy
        case .stitch: self = .stitch
        case .setThreadColor: self = .setThreadColor
        case .runningStitch: self = .runningStitch
        case .zigZagStitch: self = .zigZagStitch
        case .tripleStitch: self = .tripleStitch
        case .sewUp: self = .sewUp
        case .stopRunningStitch: self = .stopRunningStitch
        case .writeEmbroideryToFile: self = .writeEmbroideryToFile
        }
    }
}
