import ProgramModel

/// Catroid's names for every `Formula` vocabulary case (`Operators.java`,
/// `Functions.java`, `Sensors.java`). Built from exhaustive switches, so a case
/// added to `ProgramModel` does not compile here until it is named.
enum CatroidNames {
    static let binaryOperators = table(BinaryOperator.allCases) { (operator: BinaryOperator) in
        switch `operator` {
        case .plus: "PLUS"
        case .minus: "MINUS"
        case .mult: "MULT"
        case .divide: "DIVIDE"
        case .pow: "POW"
        case .equal: "EQUAL"
        case .notEqual: "NOT_EQUAL"
        case .smallerThan: "SMALLER_THAN"
        case .smallerOrEqual: "SMALLER_OR_EQUAL"
        case .greaterThan: "GREATER_THAN"
        case .greaterOrEqual: "GREATER_OR_EQUAL"
        case .logicalAnd: "LOGICAL_AND"
        case .logicalOr: "LOGICAL_OR"
        }
    }

    static let unaryFunctions = table(UnaryFunction.allCases) { (function: UnaryFunction) in
        switch function {
        case .sin: "SIN"
        case .cos: "COS"
        case .tan: "TAN"
        case .arcsin: "ARCSIN"
        case .arccos: "ARCCOS"
        case .arctan: "ARCTAN"
        case .sqrt: "SQRT"
        case .abs: "ABS"
        case .round: "ROUND"
        case .floor: "FLOOR"
        case .ceil: "CEIL"
        case .ln: "LN"
        case .log: "LOG"
        case .exp: "EXP"
        }
    }

    static let binaryFunctions = table(BinaryFunction.allCases) { (function: BinaryFunction) in
        switch function {
        case .arctan2: "ARCTAN2"
        case .min: "MIN"
        case .max: "MAX"
        case .mod: "MOD"
        case .power: "POWER"
        }
    }

    static let constants = table(FormulaConstant.allCases) { (constant: FormulaConstant) in
        switch constant {
        case .pi: "PI"
        case .true: "TRUE"
        case .false: "FALSE"
        }
    }

    static let sensors = table(Sensor.allCases) { (sensor: Sensor) in
        switch sensor {
        case .objectX: "OBJECT_X"
        case .objectY: "OBJECT_Y"
        case .motionDirection: "MOTION_DIRECTION"
        }
    }

    static func isFunction(_ name: String) -> Bool {
        unaryFunctions[name] != nil || binaryFunctions[name] != nil || constants[name] != nil
    }

    private static func table<Case>(_ cases: [Case], name: (Case) -> String) -> [String: Case] {
        Dictionary(uniqueKeysWithValues: cases.map { (name($0), $0) })
    }
}
