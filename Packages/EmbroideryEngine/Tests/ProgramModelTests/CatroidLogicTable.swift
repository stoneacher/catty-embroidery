import ProgramModel
import Testing

// swiftlint:disable file_length type_body_length

/// Catroid's own output for its comparison, logic and decimal operators and for
/// `power`, generated under Java 17 (desktop JDK, not Android ART) on 2026-10-19 by
/// transcribing `FormulaElement.interpretBinaryOperator`/`interpretUnaryOperator`
/// (`FormulaElement.java:798-879`), `interpretOperatorEqual`
/// (`FormulaElementOperations.kt:64-76`), per-node normalization (`:97-101`) and
/// `MathFunctionProvider`'s `POWER` (`Math::pow`, `:50`) into a jshell script. No
/// expected value here was computed by hand or by the code under test. The script is
/// kept at the end of this file. Variables brief D1–D4.
enum CatroidLogicTable {
    /// One operator over every ordered pair of `operands`: row `i`, column `j` is the
    /// result for `(operands[i], operands[j])`, `1` or `0`.
    struct TruthMatrix: Sendable {
        let operation: BinaryOperator, rows: [String]
        init(_ operation: BinaryOperator, _ rows: [String]) {
            (self.operation, self.rows) = (operation, rows)
        }
    }

    /// A decimal operator whose Catroid result is zero or within four smallest normals
    /// of it: where the sign rule of brief D2 lives.
    struct ArithmeticRow: Sendable, CustomTestStringConvertible {
        let operation: BinaryOperator, left: Double, right: Double, expected: Double
        init(_ operation: BinaryOperator, _ left: Double, _ right: Double, _ expected: Double) {
            (self.operation, self.left, self.right, self.expected) = (operation, left, right, expected)
        }

        var testDescription: String { "\(operation)(\(left), \(right)) = \(expected)" }
    }

    struct PowerRow: Sendable, CustomTestStringConvertible {
        let base: Double, exponent: Double, expected: Double
        init(_ base: Double, _ exponent: Double, _ expected: Double) {
            (self.base, self.exponent, self.expected) = (base, exponent, expected)
        }

        var testDescription: String { "power(\(base), \(exponent)) = \(expected)" }
    }

    static let operands: [Double] = [
        .nan,
        0.0,
        -0.0,
        1.0,
        -1.0,
        0.5,
        .greatestFiniteMagnitude,
        -.greatestFiniteMagnitude,
        .leastNonzeroMagnitude,
        -.leastNonzeroMagnitude,
        .leastNormalMagnitude,
        -.leastNormalMagnitude
    ]

    static let truthMatrices: [TruthMatrix] = [
        TruthMatrix(.equal, [
            "100000000000", // .nan
            "011000000000", // 0.0
            "011000000000", // -0.0
            "000100000000", // 1.0
            "000010000000", // -1.0
            "000001000000", // 0.5
            "000000100000", // .greatestFiniteMagnitude
            "000000010000", // -.greatestFiniteMagnitude
            "000000001000", // .leastNonzeroMagnitude
            "000000000100", // -.leastNonzeroMagnitude
            "000000000010", // .leastNormalMagnitude
            "000000000001" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.notEqual, [
            "011111111111", // .nan
            "100111111111", // 0.0
            "100111111111", // -0.0
            "111011111111", // 1.0
            "111101111111", // -1.0
            "111110111111", // 0.5
            "111111011111", // .greatestFiniteMagnitude
            "111111101111", // -.greatestFiniteMagnitude
            "111111110111", // .leastNonzeroMagnitude
            "111111111011", // -.leastNonzeroMagnitude
            "111111111101", // .leastNormalMagnitude
            "111111111110" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.smallerThan, [
            "000000000000", // .nan
            "100101101010", // 0.0
            "110101101010", // -0.0
            "100000100000", // 1.0
            "111101101111", // -1.0
            "100100100000", // 0.5
            "100000000000", // .greatestFiniteMagnitude
            "111111101111", // -.greatestFiniteMagnitude
            "100101100010", // .leastNonzeroMagnitude
            "111101101010", // -.leastNonzeroMagnitude
            "100101100000", // .leastNormalMagnitude
            "111101101110" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.smallerOrEqual, [
            "100000000000", // .nan
            "110101101010", // 0.0
            "111101101010", // -0.0
            "100100100000", // 1.0
            "111111101111", // -1.0
            "100101100000", // 0.5
            "100000100000", // .greatestFiniteMagnitude
            "111111111111", // -.greatestFiniteMagnitude
            "100101101010", // .leastNonzeroMagnitude
            "111101101110", // -.leastNonzeroMagnitude
            "100101100010", // .leastNormalMagnitude
            "111101101111" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.greaterThan, [
            "011111111111", // .nan
            "001010010101", // 0.0
            "000010010101", // -0.0
            "011011011111", // 1.0
            "000000010000", // -1.0
            "011010011111", // 0.5
            "011111011111", // .greatestFiniteMagnitude
            "000000000000", // -.greatestFiniteMagnitude
            "011010010101", // .leastNonzeroMagnitude
            "000010010001", // -.leastNonzeroMagnitude
            "011010011101", // .leastNormalMagnitude
            "000010010000" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.greaterOrEqual, [
            "111111111111", // .nan
            "011010010101", // 0.0
            "001010010101", // -0.0
            "011111011111", // 1.0
            "000010010000", // -1.0
            "011011011111", // 0.5
            "011111111111", // .greatestFiniteMagnitude
            "000000010000", // -.greatestFiniteMagnitude
            "011010011101", // .leastNonzeroMagnitude
            "000010010101", // -.leastNonzeroMagnitude
            "011010011111", // .leastNormalMagnitude
            "000010010001" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.logicalAnd, [
            "100111111111", // .nan
            "000000000000", // 0.0
            "000000000000", // -0.0
            "100111111111", // 1.0
            "100111111111", // -1.0
            "100111111111", // 0.5
            "100111111111", // .greatestFiniteMagnitude
            "100111111111", // -.greatestFiniteMagnitude
            "100111111111", // .leastNonzeroMagnitude
            "100111111111", // -.leastNonzeroMagnitude
            "100111111111", // .leastNormalMagnitude
            "100111111111" // -.leastNormalMagnitude
        ]),
        TruthMatrix(.logicalOr, [
            "111111111111", // .nan
            "100111111111", // 0.0
            "100111111111", // -0.0
            "111111111111", // 1.0
            "111111111111", // -1.0
            "111111111111", // 0.5
            "111111111111", // .greatestFiniteMagnitude
            "111111111111", // -.greatestFiniteMagnitude
            "111111111111", // .leastNonzeroMagnitude
            "111111111111", // -.leastNonzeroMagnitude
            "111111111111", // .leastNormalMagnitude
            "111111111111" // -.leastNormalMagnitude
        ])
    ]

    static let arithmeticRows: [ArithmeticRow] = [
        ArithmeticRow(.plus, 0.0, 0.0, 0.0),
        ArithmeticRow(.plus, 0.0, -0.0, 0.0),
        ArithmeticRow(.plus, 0.0, .leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.plus, 0.0, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.plus, 0.0, .leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.plus, 0.0, -.leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.plus, -0.0, 0.0, 0.0),
        ArithmeticRow(.plus, -0.0, -0.0, 0.0),
        ArithmeticRow(.plus, -0.0, .leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.plus, -0.0, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.plus, -0.0, .leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.plus, -0.0, -.leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.plus, 1.0, -1.0, 0.0),
        ArithmeticRow(.plus, -1.0, 1.0, 0.0),
        ArithmeticRow(.plus, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.plus, -.greatestFiniteMagnitude, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, 0.0, .leastNonzeroMagnitude),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, -0.0, .leastNonzeroMagnitude),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, .leastNonzeroMagnitude, 1.0e-323),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, .leastNormalMagnitude, 2.225073858507202e-308),
        ArithmeticRow(.plus, .leastNonzeroMagnitude, -.leastNormalMagnitude, -2.225073858507201e-308),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, 0.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, -0.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude, -1.0e-323),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, .leastNormalMagnitude, 2.225073858507201e-308),
        ArithmeticRow(.plus, -.leastNonzeroMagnitude, -.leastNormalMagnitude, -2.225073858507202e-308),
        ArithmeticRow(.plus, .leastNormalMagnitude, 0.0, .leastNormalMagnitude),
        ArithmeticRow(.plus, .leastNormalMagnitude, -0.0, .leastNormalMagnitude),
        ArithmeticRow(.plus, .leastNormalMagnitude, .leastNonzeroMagnitude, 2.225073858507202e-308),
        ArithmeticRow(.plus, .leastNormalMagnitude, -.leastNonzeroMagnitude, 2.225073858507201e-308),
        ArithmeticRow(.plus, .leastNormalMagnitude, .leastNormalMagnitude, 4.450147717014403e-308),
        ArithmeticRow(.plus, .leastNormalMagnitude, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.plus, -.leastNormalMagnitude, 0.0, -.leastNormalMagnitude),
        ArithmeticRow(.plus, -.leastNormalMagnitude, -0.0, -.leastNormalMagnitude),
        ArithmeticRow(.plus, -.leastNormalMagnitude, .leastNonzeroMagnitude, -2.225073858507201e-308),
        ArithmeticRow(.plus, -.leastNormalMagnitude, -.leastNonzeroMagnitude, -2.225073858507202e-308),
        ArithmeticRow(.plus, -.leastNormalMagnitude, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.plus, -.leastNormalMagnitude, -.leastNormalMagnitude, -4.450147717014403e-308),
        ArithmeticRow(.minus, 0.0, 0.0, 0.0),
        ArithmeticRow(.minus, 0.0, -0.0, 0.0),
        ArithmeticRow(.minus, 0.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.minus, 0.0, -.leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.minus, 0.0, .leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.minus, 0.0, -.leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.minus, -0.0, 0.0, 0.0),
        ArithmeticRow(.minus, -0.0, -0.0, 0.0),
        ArithmeticRow(.minus, -0.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.minus, -0.0, -.leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.minus, -0.0, .leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.minus, -0.0, -.leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.minus, 1.0, 1.0, 0.0),
        ArithmeticRow(.minus, -1.0, -1.0, 0.0),
        ArithmeticRow(.minus, 0.5, 0.5, 0.0),
        ArithmeticRow(.minus, .greatestFiniteMagnitude, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.minus, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, 0.0, .leastNonzeroMagnitude),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, -0.0, .leastNonzeroMagnitude),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, 1.0e-323),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, .leastNormalMagnitude, -2.225073858507201e-308),
        ArithmeticRow(.minus, .leastNonzeroMagnitude, -.leastNormalMagnitude, 2.225073858507202e-308),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, 0.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, -0.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, .leastNonzeroMagnitude, -1.0e-323),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, .leastNormalMagnitude, -2.225073858507202e-308),
        ArithmeticRow(.minus, -.leastNonzeroMagnitude, -.leastNormalMagnitude, 2.225073858507201e-308),
        ArithmeticRow(.minus, .leastNormalMagnitude, 0.0, .leastNormalMagnitude),
        ArithmeticRow(.minus, .leastNormalMagnitude, -0.0, .leastNormalMagnitude),
        ArithmeticRow(.minus, .leastNormalMagnitude, .leastNonzeroMagnitude, 2.225073858507201e-308),
        ArithmeticRow(.minus, .leastNormalMagnitude, -.leastNonzeroMagnitude, 2.225073858507202e-308),
        ArithmeticRow(.minus, .leastNormalMagnitude, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.minus, .leastNormalMagnitude, -.leastNormalMagnitude, 4.450147717014403e-308),
        ArithmeticRow(.minus, -.leastNormalMagnitude, 0.0, -.leastNormalMagnitude),
        ArithmeticRow(.minus, -.leastNormalMagnitude, -0.0, -.leastNormalMagnitude),
        ArithmeticRow(.minus, -.leastNormalMagnitude, .leastNonzeroMagnitude, -2.225073858507202e-308),
        ArithmeticRow(.minus, -.leastNormalMagnitude, -.leastNonzeroMagnitude, -2.225073858507201e-308),
        ArithmeticRow(.minus, -.leastNormalMagnitude, .leastNormalMagnitude, -4.450147717014403e-308),
        ArithmeticRow(.minus, -.leastNormalMagnitude, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, 0.0, 0.0),
        ArithmeticRow(.mult, 0.0, -0.0, 0.0),
        ArithmeticRow(.mult, 0.0, 1.0, 0.0),
        ArithmeticRow(.mult, 0.0, -1.0, 0.0),
        ArithmeticRow(.mult, 0.0, 0.5, 0.0),
        ArithmeticRow(.mult, 0.0, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, 0.0, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, 0.0, 0.0),
        ArithmeticRow(.mult, -0.0, -0.0, 0.0),
        ArithmeticRow(.mult, -0.0, 1.0, 0.0),
        ArithmeticRow(.mult, -0.0, -1.0, 0.0),
        ArithmeticRow(.mult, -0.0, 0.5, 0.0),
        ArithmeticRow(.mult, -0.0, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, -0.0, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, 1.0, 0.0, 0.0),
        ArithmeticRow(.mult, 1.0, -0.0, 0.0),
        ArithmeticRow(.mult, 1.0, .leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.mult, 1.0, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.mult, 1.0, .leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.mult, 1.0, -.leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.mult, -1.0, 0.0, 0.0),
        ArithmeticRow(.mult, -1.0, -0.0, 0.0),
        ArithmeticRow(.mult, -1.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude),
        ArithmeticRow(.mult, -1.0, -.leastNonzeroMagnitude, .leastNonzeroMagnitude),
        ArithmeticRow(.mult, -1.0, .leastNormalMagnitude, -.leastNormalMagnitude),
        ArithmeticRow(.mult, -1.0, -.leastNormalMagnitude, .leastNormalMagnitude),
        ArithmeticRow(.mult, 0.5, 0.0, 0.0),
        ArithmeticRow(.mult, 0.5, -0.0, 0.0),
        ArithmeticRow(.mult, 0.5, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, 0.5, -.leastNonzeroMagnitude, -0.0),
        ArithmeticRow(.mult, 0.5, .leastNormalMagnitude, 1.1125369292536007e-308),
        ArithmeticRow(.mult, 0.5, -.leastNormalMagnitude, -1.1125369292536007e-308),
        ArithmeticRow(.mult, .greatestFiniteMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, .greatestFiniteMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, -.greatestFiniteMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, -.greatestFiniteMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, 1.0, .leastNonzeroMagnitude),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, -1.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, 0.5, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, -0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, .leastNonzeroMagnitude, -.leastNormalMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, 1.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, -1.0, .leastNonzeroMagnitude),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, 0.5, -0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, .leastNonzeroMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, .leastNormalMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNonzeroMagnitude, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, 1.0, .leastNormalMagnitude),
        ArithmeticRow(.mult, .leastNormalMagnitude, -1.0, -.leastNormalMagnitude),
        ArithmeticRow(.mult, .leastNormalMagnitude, 0.5, 1.1125369292536007e-308),
        ArithmeticRow(.mult, .leastNormalMagnitude, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, -.leastNonzeroMagnitude, -0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.mult, .leastNormalMagnitude, -.leastNormalMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, 0.0, 0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, -0.0, 0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, 1.0, -.leastNormalMagnitude),
        ArithmeticRow(.mult, -.leastNormalMagnitude, -1.0, .leastNormalMagnitude),
        ArithmeticRow(.mult, -.leastNormalMagnitude, 0.5, -1.1125369292536007e-308),
        ArithmeticRow(.mult, -.leastNormalMagnitude, .leastNonzeroMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, .leastNormalMagnitude, -0.0),
        ArithmeticRow(.mult, -.leastNormalMagnitude, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, 1.0, 0.0),
        ArithmeticRow(.divide, 0.0, -1.0, 0.0),
        ArithmeticRow(.divide, 0.0, 0.5, 0.0),
        ArithmeticRow(.divide, 0.0, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.divide, 0.0, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, 1.0, 0.0),
        ArithmeticRow(.divide, -0.0, -1.0, 0.0),
        ArithmeticRow(.divide, -0.0, 0.5, 0.0),
        ArithmeticRow(.divide, -0.0, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, .leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, -.leastNonzeroMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, .leastNormalMagnitude, 0.0),
        ArithmeticRow(.divide, -0.0, -.leastNormalMagnitude, 0.0),
        ArithmeticRow(.divide, 1.0, .greatestFiniteMagnitude, 5.562684646268003e-309),
        ArithmeticRow(.divide, 1.0, -.greatestFiniteMagnitude, -5.562684646268003e-309),
        ArithmeticRow(.divide, -1.0, .greatestFiniteMagnitude, -5.562684646268003e-309),
        ArithmeticRow(.divide, -1.0, -.greatestFiniteMagnitude, 5.562684646268003e-309),
        ArithmeticRow(.divide, 0.5, .greatestFiniteMagnitude, 2.781342323134002e-309),
        ArithmeticRow(.divide, 0.5, -.greatestFiniteMagnitude, -2.781342323134002e-309),
        ArithmeticRow(.divide, .leastNonzeroMagnitude, 1.0, .leastNonzeroMagnitude),
        ArithmeticRow(.divide, .leastNonzeroMagnitude, -1.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.divide, .leastNonzeroMagnitude, 0.5, 1.0e-323),
        ArithmeticRow(.divide, .leastNonzeroMagnitude, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, .leastNonzeroMagnitude, -.greatestFiniteMagnitude, -0.0),
        ArithmeticRow(.divide, -.leastNonzeroMagnitude, 1.0, -.leastNonzeroMagnitude),
        ArithmeticRow(.divide, -.leastNonzeroMagnitude, -1.0, .leastNonzeroMagnitude),
        ArithmeticRow(.divide, -.leastNonzeroMagnitude, 0.5, -1.0e-323),
        ArithmeticRow(.divide, -.leastNonzeroMagnitude, .greatestFiniteMagnitude, -0.0),
        ArithmeticRow(.divide, -.leastNonzeroMagnitude, -.greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, .leastNormalMagnitude, 1.0, .leastNormalMagnitude),
        ArithmeticRow(.divide, .leastNormalMagnitude, -1.0, -.leastNormalMagnitude),
        ArithmeticRow(.divide, .leastNormalMagnitude, 0.5, 4.450147717014403e-308),
        ArithmeticRow(.divide, .leastNormalMagnitude, .greatestFiniteMagnitude, 0.0),
        ArithmeticRow(.divide, .leastNormalMagnitude, -.greatestFiniteMagnitude, -0.0),
        ArithmeticRow(.divide, -.leastNormalMagnitude, 1.0, -.leastNormalMagnitude),
        ArithmeticRow(.divide, -.leastNormalMagnitude, -1.0, .leastNormalMagnitude),
        ArithmeticRow(.divide, -.leastNormalMagnitude, 0.5, -4.450147717014403e-308),
        ArithmeticRow(.divide, -.leastNormalMagnitude, .greatestFiniteMagnitude, -0.0),
        ArithmeticRow(.divide, -.leastNormalMagnitude, -.greatestFiniteMagnitude, 0.0)
    ]

    static let notRows: [(operand: Double, expected: Double)] = [
        (.nan, 0.0),
        (0.0, 1.0),
        (-0.0, 1.0),
        (1.0, 0.0),
        (-1.0, 0.0),
        (0.5, 0.0),
        (.greatestFiniteMagnitude, 0.0),
        (-.greatestFiniteMagnitude, 0.0),
        (.leastNonzeroMagnitude, 0.0),
        (-.leastNonzeroMagnitude, 0.0),
        (.leastNormalMagnitude, 0.0),
        (-.leastNormalMagnitude, 0.0)
    ]

    static let powerRows: [PowerRow] = [
        PowerRow(.nan, .nan, .nan),
        PowerRow(.nan, 0.0, 1.0),
        PowerRow(.nan, -0.0, 1.0),
        PowerRow(.nan, 1.0, .nan),
        PowerRow(.nan, -1.0, .nan),
        PowerRow(.nan, 0.5, .nan),
        PowerRow(.nan, .greatestFiniteMagnitude, .nan),
        PowerRow(.nan, -.greatestFiniteMagnitude, .nan),
        PowerRow(.nan, .leastNonzeroMagnitude, .nan),
        PowerRow(.nan, -.leastNonzeroMagnitude, .nan),
        PowerRow(.nan, .leastNormalMagnitude, .nan),
        PowerRow(.nan, -.leastNormalMagnitude, .nan),
        PowerRow(0.0, .nan, .nan),
        PowerRow(0.0, 0.0, 1.0),
        PowerRow(0.0, -0.0, 1.0),
        PowerRow(0.0, 1.0, 0.0),
        PowerRow(0.0, -1.0, .greatestFiniteMagnitude),
        PowerRow(0.0, 0.5, 0.0),
        PowerRow(0.0, .greatestFiniteMagnitude, 0.0),
        PowerRow(0.0, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(0.0, .leastNonzeroMagnitude, 0.0),
        PowerRow(0.0, -.leastNonzeroMagnitude, .greatestFiniteMagnitude),
        PowerRow(0.0, .leastNormalMagnitude, 0.0),
        PowerRow(0.0, -.leastNormalMagnitude, .greatestFiniteMagnitude),
        PowerRow(-0.0, .nan, .nan),
        PowerRow(-0.0, 0.0, 1.0),
        PowerRow(-0.0, -0.0, 1.0),
        PowerRow(-0.0, 1.0, -0.0),
        PowerRow(-0.0, -1.0, -.greatestFiniteMagnitude),
        PowerRow(-0.0, 0.5, 0.0),
        PowerRow(-0.0, .greatestFiniteMagnitude, 0.0),
        PowerRow(-0.0, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(-0.0, .leastNonzeroMagnitude, 0.0),
        PowerRow(-0.0, -.leastNonzeroMagnitude, .greatestFiniteMagnitude),
        PowerRow(-0.0, .leastNormalMagnitude, 0.0),
        PowerRow(-0.0, -.leastNormalMagnitude, .greatestFiniteMagnitude),
        PowerRow(1.0, .nan, .nan),
        PowerRow(1.0, 0.0, 1.0),
        PowerRow(1.0, -0.0, 1.0),
        PowerRow(1.0, 1.0, 1.0),
        PowerRow(1.0, -1.0, 1.0),
        PowerRow(1.0, 0.5, 1.0),
        PowerRow(1.0, .greatestFiniteMagnitude, 1.0),
        PowerRow(1.0, -.greatestFiniteMagnitude, 1.0),
        PowerRow(1.0, .leastNonzeroMagnitude, 1.0),
        PowerRow(1.0, -.leastNonzeroMagnitude, 1.0),
        PowerRow(1.0, .leastNormalMagnitude, 1.0),
        PowerRow(1.0, -.leastNormalMagnitude, 1.0),
        PowerRow(-1.0, .nan, .nan),
        PowerRow(-1.0, 0.0, 1.0),
        PowerRow(-1.0, -0.0, 1.0),
        PowerRow(-1.0, 1.0, -1.0),
        PowerRow(-1.0, -1.0, -1.0),
        PowerRow(-1.0, 0.5, .nan),
        PowerRow(-1.0, .greatestFiniteMagnitude, 1.0),
        PowerRow(-1.0, -.greatestFiniteMagnitude, 1.0),
        PowerRow(-1.0, .leastNonzeroMagnitude, .nan),
        PowerRow(-1.0, -.leastNonzeroMagnitude, .nan),
        PowerRow(-1.0, .leastNormalMagnitude, .nan),
        PowerRow(-1.0, -.leastNormalMagnitude, .nan),
        PowerRow(0.5, .nan, .nan),
        PowerRow(0.5, 0.0, 1.0),
        PowerRow(0.5, -0.0, 1.0),
        PowerRow(0.5, 1.0, 0.5),
        PowerRow(0.5, -1.0, 2.0),
        PowerRow(0.5, 0.5, 0.7071067811865476),
        PowerRow(0.5, .greatestFiniteMagnitude, 0.0),
        PowerRow(0.5, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(0.5, .leastNonzeroMagnitude, 1.0),
        PowerRow(0.5, -.leastNonzeroMagnitude, 1.0),
        PowerRow(0.5, .leastNormalMagnitude, 1.0),
        PowerRow(0.5, -.leastNormalMagnitude, 1.0),
        PowerRow(.greatestFiniteMagnitude, .nan, .nan),
        PowerRow(.greatestFiniteMagnitude, 0.0, 1.0),
        PowerRow(.greatestFiniteMagnitude, -0.0, 1.0),
        PowerRow(.greatestFiniteMagnitude, 1.0, .greatestFiniteMagnitude),
        PowerRow(.greatestFiniteMagnitude, -1.0, 5.562684646268003e-309),
        PowerRow(.greatestFiniteMagnitude, 0.5, 1.3407807929942596e154),
        PowerRow(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(.greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.0),
        PowerRow(.greatestFiniteMagnitude, .leastNonzeroMagnitude, 1.0),
        PowerRow(.greatestFiniteMagnitude, -.leastNonzeroMagnitude, 1.0),
        PowerRow(.greatestFiniteMagnitude, .leastNormalMagnitude, 1.0),
        PowerRow(.greatestFiniteMagnitude, -.leastNormalMagnitude, 1.0),
        PowerRow(-.greatestFiniteMagnitude, .nan, .nan),
        PowerRow(-.greatestFiniteMagnitude, 0.0, 1.0),
        PowerRow(-.greatestFiniteMagnitude, -0.0, 1.0),
        PowerRow(-.greatestFiniteMagnitude, 1.0, -.greatestFiniteMagnitude),
        PowerRow(-.greatestFiniteMagnitude, -1.0, -5.562684646268003e-309),
        PowerRow(-.greatestFiniteMagnitude, 0.5, .nan),
        PowerRow(-.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, 0.0),
        PowerRow(-.greatestFiniteMagnitude, .leastNonzeroMagnitude, .nan),
        PowerRow(-.greatestFiniteMagnitude, -.leastNonzeroMagnitude, .nan),
        PowerRow(-.greatestFiniteMagnitude, .leastNormalMagnitude, .nan),
        PowerRow(-.greatestFiniteMagnitude, -.leastNormalMagnitude, .nan),
        PowerRow(.leastNonzeroMagnitude, .nan, .nan),
        PowerRow(.leastNonzeroMagnitude, 0.0, 1.0),
        PowerRow(.leastNonzeroMagnitude, -0.0, 1.0),
        PowerRow(.leastNonzeroMagnitude, 1.0, .leastNonzeroMagnitude),
        PowerRow(.leastNonzeroMagnitude, -1.0, .greatestFiniteMagnitude),
        PowerRow(.leastNonzeroMagnitude, 0.5, 2.2227587494850775e-162),
        PowerRow(.leastNonzeroMagnitude, .greatestFiniteMagnitude, 0.0),
        PowerRow(.leastNonzeroMagnitude, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(.leastNonzeroMagnitude, .leastNonzeroMagnitude, 1.0),
        PowerRow(.leastNonzeroMagnitude, -.leastNonzeroMagnitude, 1.0),
        PowerRow(.leastNonzeroMagnitude, .leastNormalMagnitude, 1.0),
        PowerRow(.leastNonzeroMagnitude, -.leastNormalMagnitude, 1.0),
        PowerRow(-.leastNonzeroMagnitude, .nan, .nan),
        PowerRow(-.leastNonzeroMagnitude, 0.0, 1.0),
        PowerRow(-.leastNonzeroMagnitude, -0.0, 1.0),
        PowerRow(-.leastNonzeroMagnitude, 1.0, -.leastNonzeroMagnitude),
        PowerRow(-.leastNonzeroMagnitude, -1.0, -.greatestFiniteMagnitude),
        PowerRow(-.leastNonzeroMagnitude, 0.5, .nan),
        PowerRow(-.leastNonzeroMagnitude, .greatestFiniteMagnitude, 0.0),
        PowerRow(-.leastNonzeroMagnitude, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(-.leastNonzeroMagnitude, .leastNonzeroMagnitude, .nan),
        PowerRow(-.leastNonzeroMagnitude, -.leastNonzeroMagnitude, .nan),
        PowerRow(-.leastNonzeroMagnitude, .leastNormalMagnitude, .nan),
        PowerRow(-.leastNonzeroMagnitude, -.leastNormalMagnitude, .nan),
        PowerRow(.leastNormalMagnitude, .nan, .nan),
        PowerRow(.leastNormalMagnitude, 0.0, 1.0),
        PowerRow(.leastNormalMagnitude, -0.0, 1.0),
        PowerRow(.leastNormalMagnitude, 1.0, .leastNormalMagnitude),
        PowerRow(.leastNormalMagnitude, -1.0, 4.49423283715579e307),
        PowerRow(.leastNormalMagnitude, 0.5, 1.4916681462400413e-154),
        PowerRow(.leastNormalMagnitude, .greatestFiniteMagnitude, 0.0),
        PowerRow(.leastNormalMagnitude, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(.leastNormalMagnitude, .leastNonzeroMagnitude, 1.0),
        PowerRow(.leastNormalMagnitude, -.leastNonzeroMagnitude, 1.0),
        PowerRow(.leastNormalMagnitude, .leastNormalMagnitude, 1.0),
        PowerRow(.leastNormalMagnitude, -.leastNormalMagnitude, 1.0),
        PowerRow(-.leastNormalMagnitude, .nan, .nan),
        PowerRow(-.leastNormalMagnitude, 0.0, 1.0),
        PowerRow(-.leastNormalMagnitude, -0.0, 1.0),
        PowerRow(-.leastNormalMagnitude, 1.0, -.leastNormalMagnitude),
        PowerRow(-.leastNormalMagnitude, -1.0, -4.49423283715579e307),
        PowerRow(-.leastNormalMagnitude, 0.5, .nan),
        PowerRow(-.leastNormalMagnitude, .greatestFiniteMagnitude, 0.0),
        PowerRow(-.leastNormalMagnitude, -.greatestFiniteMagnitude, .greatestFiniteMagnitude),
        PowerRow(-.leastNormalMagnitude, .leastNonzeroMagnitude, .nan),
        PowerRow(-.leastNormalMagnitude, -.leastNonzeroMagnitude, .nan),
        PowerRow(-.leastNormalMagnitude, .leastNormalMagnitude, .nan),
        PowerRow(-.leastNormalMagnitude, -.leastNormalMagnitude, .nan)
    ]
}

// swiftlint:disable line_length
// The generator, run with `jshell -q logic.jsh` (JDK 17):
//
// import java.math.*;
// // Catroid FormulaElement.interpretBinaryOperator / interpretUnaryOperator, transcribed
// // (FormulaElement.java:798-879), with FormulaElementOperations.interpretOperatorEqual
// // (FormulaElementOperations.kt:64-76) and per-node normalization (:97-101).
// double norm(double x) { return x == Double.POSITIVE_INFINITY ? Double.MAX_VALUE : x == Double.NEGATIVE_INFINITY ? -Double.MAX_VALUE : x; }
// double b2d(boolean b) { return b ? 1.0 : 0.0; }
// boolean ieeeEq(double l, double r) { return Double.isNaN(l) && Double.isNaN(r) || !Double.isNaN(l) && !Double.isNaN(r) && l >= r && l <= r; }
// boolean opEq(Object l, Object r) { try { return ieeeEq(Double.parseDouble(l.toString()), Double.parseDouble(r.toString())); } catch (NumberFormatException e) { return l.toString().equals(r.toString()); } }
// BigDecimal bd(double x) { try { return BigDecimal.valueOf(x); } catch (NumberFormatException e) { return BigDecimal.valueOf(0d); } }
// double bin(String op, double ld, double rd) {
//   Double l = ld, r = rd; BigDecimal L = bd(ld), R = bd(rd);
//   boolean nan = Double.isNaN(ld) || Double.isNaN(rd);
//   switch (op) {
//     case "plus": return nan ? Double.NaN : L.add(R, MathContext.DECIMAL128).doubleValue();
//     case "minus": return nan ? Double.NaN : L.subtract(R, MathContext.DECIMAL128).doubleValue();
//     case "mult": return nan ? Double.NaN : L.multiply(R, MathContext.DECIMAL128).doubleValue();
//     case "divide": return (nan || R.equals(BigDecimal.valueOf(0d))) ? Double.NaN : L.divide(R, MathContext.DECIMAL128).doubleValue();
//     case "equal": return b2d(opEq(l, r));
//     case "notEqual": return b2d(!opEq(l, r));
//     case "greaterThan": return b2d(l.compareTo(r) > 0);
//     case "greaterOrEqual": return b2d(l.compareTo(r) >= 0);
//     case "smallerThan": return b2d(l.compareTo(r) < 0);
//     case "smallerOrEqual": return b2d(l.compareTo(r) <= 0);
//     case "logicalAnd": return b2d(l != 0.0 && r != 0.0);
//     case "logicalOr": return b2d(l != 0.0 || r != 0.0);
//   }
//   throw new RuntimeException(op);
// }
// String sw(double x) {
//   if (Double.isNaN(x)) return ".nan";
//   if (x == Double.MAX_VALUE) return ".greatestFiniteMagnitude";
//   if (x == -Double.MAX_VALUE) return "-.greatestFiniteMagnitude";
//   if (x == Double.MIN_VALUE) return ".leastNonzeroMagnitude";
//   if (x == -Double.MIN_VALUE) return "-.leastNonzeroMagnitude";
//   if (x == Double.MIN_NORMAL) return ".leastNormalMagnitude";
//   if (x == -Double.MIN_NORMAL) return "-.leastNormalMagnitude";
//   if (x == 0 && 1/x < 0) return "-0.0";
//   return Double.toString(x).replace("E", "e");
// }
// double[] V = { Double.NaN, 0.0, -0.0, 1.0, -1.0, 0.5, Double.MAX_VALUE, -Double.MAX_VALUE, Double.MIN_VALUE, -Double.MIN_VALUE, Double.MIN_NORMAL, -Double.MIN_NORMAL };
// StringBuilder o = new StringBuilder();
// o.append("    static let operands: [Double] = [").append(String.join(", ", java.util.Arrays.stream(V).mapToObj(x -> sw(x)).toArray(String[]::new))).append("]\n\n");
// o.append("    static let truthMatrices: [TruthMatrix] = [\n");
// for (String op : new String[]{"equal","notEqual","smallerThan","smallerOrEqual","greaterThan","greaterOrEqual","logicalAnd","logicalOr"}) {
//   o.append("        TruthMatrix(.").append(op).append(", [\n");
//   for (double l : V) { StringBuilder row = new StringBuilder(); for (double r : V) row.append(bin(op, norm(l), norm(r)) == 1.0 ? '1' : '0'); o.append("            \"").append(row).append("\", // ").append(sw(l)).append("\n"); }
//   o.append("        ]),\n");
// }
// o.append("    ]\n\n    static let arithmeticRows: [ArithmeticRow] = [\n");
// for (String op : new String[]{"plus","minus","mult","divide"}) for (double l : V) for (double r : V) {
//   double res = norm(bin(op, norm(l), norm(r)));
//   if (Double.isNaN(res)) continue;
//   if (res != 0 && !(Math.abs(res) < Double.MIN_NORMAL * 4)) continue; // zero and subnormal results: where the sign rule lives
//   o.append("        ArithmeticRow(.").append(op).append(", ").append(sw(l)).append(", ").append(sw(r)).append(", ").append(sw(res)).append("),\n");
// }
// o.append("    ]\n\n    static let notRows: [(Double, Double)] = [\n");
// for (double x : V) o.append("        (").append(sw(x)).append(", ").append(sw(b2d(x == 0.0))).append("),\n");
// o.append("    ]\n\n    static let powerRows: [PowerRow] = [\n");
// for (double l : V) for (double r : V) o.append("        PowerRow(").append(sw(l)).append(", ").append(sw(r)).append(", ").append(sw(norm(Math.pow(l, r)))).append("),\n");
// o.append("    ]\n");
// System.out.print(o);
// /exit
// swiftlint:enable line_length
// swiftlint:enable file_length type_body_length
