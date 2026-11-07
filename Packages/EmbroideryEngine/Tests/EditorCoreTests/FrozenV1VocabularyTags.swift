import ProgramModel

// MARK: - The v1 vocabulary, by exhaustive switch

/// One tag per `Brick` case. `init(of:)` has no `default:`, so a new `Brick` case does not
/// compile here until it gets a tag, and then the census test fails until `FrozenV1.bricks`
/// holds one, which changes the frozen bytes. That is the point: a new brick is a v2.
enum V1BrickCase: CaseIterable {
    case moveNSteps, turnLeft, turnRight, pointInDirection, placeAt, setX, setY, changeXBy, changeYBy
    case arc, goThrough
    case repeatLoop, forever, repeatUntil, forVariableFromTo, loopEnd
    case wait, waitUntil, ifThen, ifElse, elseBranch, ifEnd
    case setVariable, changeVariableBy
    case stitch, setThreadColor, runningStitch, zigZagStitch, tripleStitch, sewUp, stopRunningStitch
    case writeEmbroideryToFile

    init(of brick: Brick) {
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
        case .arc: self = .arc
        case .goThrough: self = .goThrough
        case .repeatLoop: self = .repeatLoop
        case .forever: self = .forever
        case .repeatUntil: self = .repeatUntil
        case .forVariableFromTo: self = .forVariableFromTo
        case .loopEnd: self = .loopEnd
        case .wait: self = .wait
        case .waitUntil: self = .waitUntil
        case .ifThen: self = .ifThen
        case .ifElse: self = .ifElse
        case .elseBranch: self = .elseBranch
        case .ifEnd: self = .ifEnd
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

/// One tag per `ScriptHeader` case, for the same reason as `V1BrickCase`.
enum V1HeaderCase: CaseIterable {
    case whenStarted

    init(of header: ScriptHeader) {
        switch header {
        case .whenStarted: self = .whenStarted
        }
    }
}

/// The leaf vocabularies, owned by the test. Each tag maps both ways through exhaustive
/// switches, and the maximal program is built from the *tags*, so a production `allCases`
/// that omits a case cannot shrink the program and the oracle together.
enum V1Operator: CaseIterable {
    case plus, minus, mult, divide, pow
    case equal, notEqual, smallerThan, smallerOrEqual, greaterThan, greaterOrEqual
    case logicalAnd, logicalOr

    init(of value: BinaryOperator) {
        switch value {
        case .plus: self = .plus
        case .minus: self = .minus
        case .mult: self = .mult
        case .divide: self = .divide
        case .pow: self = .pow
        case .equal: self = .equal
        case .notEqual: self = .notEqual
        case .smallerThan: self = .smallerThan
        case .smallerOrEqual: self = .smallerOrEqual
        case .greaterThan: self = .greaterThan
        case .greaterOrEqual: self = .greaterOrEqual
        case .logicalAnd: self = .logicalAnd
        case .logicalOr: self = .logicalOr
        }
    }

    var value: BinaryOperator {
        switch self {
        case .plus: .plus
        case .minus: .minus
        case .mult: .mult
        case .divide: .divide
        case .pow: .pow
        case .equal: .equal
        case .notEqual: .notEqual
        case .smallerThan: .smallerThan
        case .smallerOrEqual: .smallerOrEqual
        case .greaterThan: .greaterThan
        case .greaterOrEqual: .greaterOrEqual
        case .logicalAnd: .logicalAnd
        case .logicalOr: .logicalOr
        }
    }
}

enum V1UnaryFunction: CaseIterable {
    // swiftlint:disable:next identifier_name
    case sin, cos, tan, arcsin, arccos, arctan, sqrt, abs, round, floor, ceil, ln, log, exp

    init(of value: UnaryFunction) {
        switch value {
        case .sin: self = .sin
        case .cos: self = .cos
        case .tan: self = .tan
        case .arcsin: self = .arcsin
        case .arccos: self = .arccos
        case .arctan: self = .arctan
        case .sqrt: self = .sqrt
        case .abs: self = .abs
        case .round: self = .round
        case .floor: self = .floor
        case .ceil: self = .ceil
        case .ln: self = .ln
        case .log: self = .log
        case .exp: self = .exp
        }
    }

    var value: UnaryFunction {
        switch self {
        case .sin: .sin
        case .cos: .cos
        case .tan: .tan
        case .arcsin: .arcsin
        case .arccos: .arccos
        case .arctan: .arctan
        case .sqrt: .sqrt
        case .abs: .abs
        case .round: .round
        case .floor: .floor
        case .ceil: .ceil
        case .ln: .ln
        case .log: .log
        case .exp: .exp
        }
    }
}

enum V1BinaryFunction: CaseIterable {
    case arctan2, min, max, mod, power

    init(of value: BinaryFunction) {
        switch value {
        case .arctan2: self = .arctan2
        case .min: self = .min
        case .max: self = .max
        case .mod: self = .mod
        case .power: self = .power
        }
    }

    var value: BinaryFunction {
        switch self {
        case .arctan2: .arctan2
        case .min: .min
        case .max: .max
        case .mod: .mod
        case .power: .power
        }
    }
}

enum V1Constant: CaseIterable {
    // swiftlint:disable:next identifier_name
    case pi, `true`, `false`

    init(of value: FormulaConstant) {
        switch value {
        case .pi: self = .pi
        case .true: self = .true
        case .false: self = .false
        }
    }

    var value: FormulaConstant {
        switch self {
        case .pi: .pi
        case .true: .true
        case .false: .false
        }
    }
}

enum V1Sensor: CaseIterable {
    case objectX, objectY, motionDirection

    init(of value: Sensor) {
        switch value {
        case .objectX: self = .objectX
        case .objectY: self = .objectY
        case .motionDirection: self = .motionDirection
        }
    }

    var value: Sensor {
        switch self {
        case .objectX: .objectX
        case .objectY: .objectY
        case .motionDirection: .motionDirection
        }
    }
}

enum V1ArcDirection: CaseIterable {
    case left, right

    init(of value: ArcDirection) {
        switch value {
        case .left: self = .left
        case .right: self = .right
        }
    }
}
