import ProgramModel

/// One editable value of a brick, named by what it means in the brick's
/// sentence (US-410).
///
/// Named rather than positional so a call site reads `.width`, not "the second
/// formula", and so `replacing(_:with:)` can refuse a slot the brick does not
/// have instead of writing into whichever formula happens to sit at that
/// position.
public enum ParameterSlot: Sendable, Hashable, CaseIterable {
    case steps
    case degrees
    case x
    case y
    case times
    case seconds
    case value
    case length
    case width
    case variableName
    case hex
    case fileName
}

/// What a slot holds. The case is the shape of the value, which decides the
/// editor (`ParameterEditorKind`) and which slots may receive it.
public enum ParameterValue: Sendable, Equatable {
    case formula(Formula)
    case variableName(String)
    case threadColor(hex: String)
    case fileName(String)
}

/// A slot and its current value.
public struct BrickParameter: Sendable, Equatable {
    public let slot: ParameterSlot
    public let value: ParameterValue

    public init(slot: ParameterSlot, value: ParameterValue) {
        self.slot = slot
        self.value = value
    }
}

public extension Brick {
    /// The brick's parameters in sentence order — `placeAt` is x then y,
    /// `setVariable` is the name then the value.
    ///
    /// Exhaustive with no `default:`, the `BrickKind.init(of:)` pattern, so a
    /// new `Brick` case is a compile error here rather than a brick the editor
    /// silently shows as having nothing to edit.
    var parameters: [BrickParameter] {
        switch self {
        case let .moveNSteps(steps):
            [.init(slot: .steps, value: .formula(steps))]
        case let .turnLeft(degrees), let .turnRight(degrees), let .pointInDirection(degrees):
            [.init(slot: .degrees, value: .formula(degrees))]
        case let .placeAt(x, y):
            [.init(slot: .x, value: .formula(x)), .init(slot: .y, value: .formula(y))]
        case let .setX(x), let .changeXBy(x):
            [.init(slot: .x, value: .formula(x))]
        case let .setY(y), let .changeYBy(y):
            [.init(slot: .y, value: .formula(y))]
        case let .repeatLoop(times):
            [.init(slot: .times, value: .formula(times))]
        case let .wait(seconds):
            [.init(slot: .seconds, value: .formula(seconds))]
        case let .setVariable(name, value), let .changeVariableBy(name, value):
            [.init(slot: .variableName, value: .variableName(name)), .init(slot: .value, value: .formula(value))]
        case let .runningStitch(length), let .tripleStitch(length):
            [.init(slot: .length, value: .formula(length))]
        case let .zigZagStitch(length, width):
            [.init(slot: .length, value: .formula(length)), .init(slot: .width, value: .formula(width))]
        case let .setThreadColor(hex):
            [.init(slot: .hex, value: .threadColor(hex: hex))]
        case let .writeEmbroideryToFile(name):
            [.init(slot: .fileName, value: .fileName(name))]
        case .forever, .loopEnd, .stitch, .sewUp, .stopRunningStitch:
            []
        }
    }

    /// The brick with one slot replaced and every other slot untouched — or
    /// `nil` when the brick has no such slot, or the value is the wrong shape
    /// for it.
    ///
    /// **Always the same kind**, by construction: every arm rebuilds the case it
    /// matched. That is what makes the parameter editor's `replaceBrick` unable
    /// to trip ADR-035's same-kind guard (test-first item 10), so the guard in
    /// the funnel stays a backstop rather than a path the UI exercises.
    func replacing(_ slot: ParameterSlot, with value: ParameterValue) -> Brick? {
        switch (self, slot, value) {
        case let (.moveNSteps, .steps, .formula(formula)):
            .moveNSteps(formula)
        case let (.turnLeft, .degrees, .formula(formula)):
            .turnLeft(formula)
        case let (.turnRight, .degrees, .formula(formula)):
            .turnRight(formula)
        case let (.pointInDirection, .degrees, .formula(formula)):
            .pointInDirection(formula)
        case let (.placeAt(_, y), .x, .formula(formula)):
            .placeAt(x: formula, y: y)
        case let (.placeAt(x, _), .y, .formula(formula)):
            .placeAt(x: x, y: formula)
        case let (.setX, .x, .formula(formula)):
            .setX(formula)
        case let (.setY, .y, .formula(formula)):
            .setY(formula)
        case let (.changeXBy, .x, .formula(formula)):
            .changeXBy(formula)
        case let (.changeYBy, .y, .formula(formula)):
            .changeYBy(formula)
        case let (.repeatLoop, .times, .formula(formula)):
            .repeatLoop(times: formula)
        case let (.wait, .seconds, .formula(formula)):
            .wait(seconds: formula)
        case let (.setVariable(_, value), .variableName, .variableName(name)):
            .setVariable(name: name, to: value)
        case let (.setVariable(name, _), .value, .formula(formula)):
            .setVariable(name: name, to: formula)
        case let (.changeVariableBy(_, value), .variableName, .variableName(name)):
            .changeVariableBy(name: name, value: value)
        case let (.changeVariableBy(name, _), .value, .formula(formula)):
            .changeVariableBy(name: name, value: formula)
        case let (.runningStitch, .length, .formula(formula)):
            .runningStitch(length: formula)
        case let (.tripleStitch, .length, .formula(formula)):
            .tripleStitch(length: formula)
        case let (.zigZagStitch(_, width), .length, .formula(formula)):
            .zigZagStitch(length: formula, width: width)
        case let (.zigZagStitch(length, _), .width, .formula(formula)):
            .zigZagStitch(length: length, width: formula)
        case let (.setThreadColor, .hex, .threadColor(hex)):
            .setThreadColor(hex: hex)
        case let (.writeEmbroideryToFile, .fileName, .fileName(name)):
            .writeEmbroideryToFile(name: name)
        default:
            // A triple space, so `default:` is the only total answer; the
            // refusal direction is the safe one (ADR-035).
            nil
        }
    }
}
