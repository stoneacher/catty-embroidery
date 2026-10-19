import Foundation
import ProgramModel
import Testing

/// Variables slice 1: comparisons, `and`/`or`/`not`, `true`/`false` and `power`
/// (brief D1–D6, ADR-048).
///
/// The tables are Catroid's own output (`CatroidLogicTable`). The operand set adds
/// the smallest subnormal and the smallest normal to NaN, ±0 and ±MAX, because the
/// zero-sign rule fails only on underflow, which the brief's first operand set could
/// not reach (Codex brief review, finding 1).
@Suite("Formula logic")
struct FormulaLogicTests {
    private let scope = VariableScope()

    private func value(_ formula: Formula) throws -> Double {
        try formula.interpretDouble(scope: scope)
    }

    private static let logicOperators: Set<BinaryOperator> = [
        .equal, .notEqual, .smallerThan, .smallerOrEqual, .greaterThan, .greaterOrEqual, .logicalAnd, .logicalOr
    ]

    // MARK: - The tables

    @Test("every comparison and logic operator matches Catroid's truth table",
          arguments: CatroidLogicTable.truthMatrices)
    func truthTable(_ matrix: CatroidLogicTable.TruthMatrix) throws {
        let operands = CatroidLogicTable.operands
        try #require(matrix.rows.count == operands.count)
        for (row, left) in zip(matrix.rows, operands) {
            try #require(row.count == operands.count)
            for (cell, right) in zip(row, operands) {
                let expected: Double = cell == "1" ? 1 : 0
                let actual = try value(.binary(matrix.operation, .number(left), .number(right)))
                #expect(actual == expected, "\(left) \(matrix.operation) \(right)")
            }
        }
    }

    @Test("the truth tables cover every comparison and logic operator")
    func truthTablesCoverEveryOperator() {
        #expect(Set(CatroidLogicTable.truthMatrices.map(\.operation)) == Self.logicOperators)
    }

    /// Bit for bit, so the sign of a zero is part of the claim.
    @Test("zero and near-zero results of + − × ÷ match Catroid bit for bit",
          arguments: CatroidLogicTable.arithmeticRows)
    func decimalOperatorSigns(_ row: CatroidLogicTable.ArithmeticRow) throws {
        let actual = try value(.binary(row.operation, .number(row.left), .number(row.right)))
        #expect(actual.bitPattern == row.expected.bitPattern, "got \(actual)")
    }

    @Test("not matches Catroid")
    func logicalNot() throws {
        #expect(CatroidLogicTable.notRows.count == CatroidLogicTable.operands.count)
        for (operand, expected) in CatroidLogicTable.notRows {
            #expect(try value(.logicalNot(.number(operand))) == expected, "not \(operand)")
        }
    }

    /// Exact, signed zeros included; within 4 ulps elsewhere, as for the other functions
    /// (Java's and Darwin's libm may differ in the last place). A NaN result throws at the
    /// root, as every NaN does (ADR-017).
    @Test("power matches Java's Math.pow", arguments: CatroidLogicTable.powerRows)
    func power(_ row: CatroidLogicTable.PowerRow) throws {
        let formula = Formula.binaryFunction(.power, .number(row.base), .number(row.exponent))
        if row.expected.isNaN {
            #expect(throws: FormulaError.notANumber) { try formula.interpretDouble(scope: VariableScope()) }
            return
        }
        let actual = try value(formula)
        let close = row.expected == 0
            ? actual == 0 && actual.sign == row.expected.sign
            : abs(actual - row.expected) <= 4 * row.expected.ulp
        #expect(close, "got \(actual)")
    }

    @Test("true is 1 and false is 0")
    func constants() throws {
        #expect(try value(.constant(.true)) == 1)
        #expect(try value(.constant(.false)) == 0)
    }

    // MARK: - D1: one equality rule

    @Test("NaN equals NaN, as Catroid's equality does")
    func nanEqualsNaN() throws {
        let nan = Formula.binary(.divide, .number(0), .number(0))
        #expect(try value(.binary(.equal, nan, nan)) == 1)
        #expect(try value(.binary(.notEqual, nan, nan)) == 0)
    }

    @Test("−0 equals +0")
    func signedZerosAreEqual() throws {
        #expect(try value(.binary(.equal, .unaryMinus(.number(0)), .number(0))) == 1)
    }

    // MARK: - D2: Java ordering, and the zero sign Catroid's decimal arithmetic keeps

    /// Catroid's BigDecimal product of a zero is an unsigned zero, so `0 × −1` is +0
    /// there and `+0 < 0` is false. Native `Double` gives −0, which Java's ordering
    /// puts below +0 — the reason for the canonicalization.
    @Test("a zero product compares like Catroid's unsigned zero")
    func zeroProductIsUnsigned() throws {
        #expect(try value(.binary(.smallerThan, .binary(.mult, .number(0), .number(-1)), .number(0))) == 0)
        #expect(try value(.binary(.mult, .number(-0.0), .number(5))).sign == .plus)
        #expect(try value(.binary(.plus, .number(-0.0), .number(-0.0))).sign == .plus)
        #expect(try value(.binary(.divide, .number(-0.0), .number(5))).sign == .plus)
    }

    /// The exception the brief review found: two nonzero doubles have a nonzero decimal
    /// product, and `doubleValue()` rounds a tiny negative one to −0.
    @Test("negative underflow keeps its −0, so it sorts below +0")
    func negativeUnderflowKeepsItsSign() throws {
        let underflow = Formula.binary(.divide, .number(-.leastNonzeroMagnitude), .number(2))
        #expect(try value(.binary(.smallerThan, underflow, .number(0))) == 1)
        #expect(try value(.binary(.mult, .number(-1e-300), .number(1e-300))).sign == .minus)
    }

    /// Every −0 Catroid itself produces survives: unary minus and `ceil` are not decimal
    /// operators.
    @Test("the −0 of unary minus and ceil still sorts below +0")
    func otherNegativeZerosRemain() throws {
        #expect(try value(.binary(.smallerThan, .unaryMinus(.number(0)), .number(0))) == 1)
        #expect(try value(.binary(.smallerThan, .unaryFunction(.ceil, .number(-0.5)), .number(0))) == 1)
    }

    @Test("NaN sorts above every number, as in Java's compareTo")
    func nanSortsHighest() throws {
        let nan = Formula.unaryFunction(.sqrt, .number(-1))
        #expect(try value(.binary(.greaterThan, nan, .number(.greatestFiniteMagnitude))) == 1)
        #expect(try value(.binary(.smallerThan, .number(5), nan)) == 1)
        #expect(try value(.binary(.smallerOrEqual, nan, nan)) == 1)
    }

    /// Unary minus flips a NaN's sign bit, and Java's `doubleToLongBits` makes every NaN the
    /// same positive bit pattern before comparing, so a negated NaN still sorts highest. Found
    /// by mutation: every NaN the tests built before was already canonical.
    @Test("a negated NaN still sorts above every number")
    func negatedNaNSortsHighest() throws {
        let negatedNaN = Formula.unaryMinus(.unaryFunction(.sqrt, .number(-1)))
        #expect(try value(.binary(.greaterThan, negatedNaN, .number(.greatestFiniteMagnitude))) == 1)
        #expect(try value(.binary(.smallerThan, negatedNaN, .number(-.greatestFiniteMagnitude))) == 0)
        #expect(try value(.binary(.equal, negatedNaN, .unaryFunction(.sqrt, .number(-1)))) == 1)
    }

    // MARK: - D3: logic never yields NaN

    @Test("and/or test x ≠ 0, so a NaN operand is true")
    func logicOnNaN() throws {
        let nan = Formula.unaryFunction(.sqrt, .number(-1))
        #expect(try value(.binary(.logicalAnd, nan, .number(1))) == 1)
        #expect(try value(.binary(.logicalAnd, .number(0), nan)) == 0)
        #expect(try value(.binary(.logicalOr, nan, .number(0))) == 1)
        #expect(try value(.logicalNot(nan)) == 0)
    }

    // MARK: - D4: power is raw Math.pow, not ^

    @Test("power differs from ^ exactly where Math.pow does")
    func powerIsNotPow() throws {
        let nan = Formula.unaryFunction(.sqrt, .number(-1))
        let negativeZero = Formula.unaryMinus(.number(0))
        // power(NaN, 0) is 1 (Java); ^ guards NaN first and throws.
        #expect(try value(.binaryFunction(.power, nan, .number(0))) == 1)
        #expect(throws: FormulaError.notANumber) {
            try Formula.binary(.pow, nan, .number(0)).interpretDouble(scope: VariableScope())
        }
        // power keeps the zero's sign; ^ canonicalizes it (ADR-017).
        #expect(try value(.binaryFunction(.power, negativeZero, .number(-3))) == -.greatestFiniteMagnitude)
        #expect(try value(.binary(.pow, negativeZero, .number(-3))) == .greatestFiniteMagnitude)
        // Java's pow(1, NaN) is NaN, where C's pow gives 1.
        #expect(try value(.binary(.equal, .binaryFunction(.power, .number(1), nan), nan)) == 1)
    }

    // MARK: - D6: decimal128 now decides branches (ADR-019 class)

    /// Pinned divergence: `0.1 + 0.2` is exactly 0.3 in Catroid's decimal128, so `=` is 1
    /// there. Here it is 0.30000000000000004, so `=` is 0. A language test asserting the
    /// Catroid value is an expected failure.
    @Test("0.1 + 0.2 = 0.3 is false here, true in Catroid (pinned divergence)")
    func decimalEqualityDiverges() throws {
        #expect(try value(.binary(.equal, .binary(.plus, .number(0.1), .number(0.2)), .number(0.3))) == 0)
    }

    // MARK: - Totality

    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private static func tree(depth: Int, using rng: inout SplitMix) -> Formula {
        if depth == 0 || rng.next() % 4 == 0 {
            let leaves = CatroidLogicTable.operands.map(Formula.number)
                + FormulaConstant.allCases.map(Formula.constant)
            return leaves.randomElement(using: &rng) ?? .number(0)
        }
        switch rng.next() % 3 {
        case 0:
            return .logicalNot(tree(depth: depth - 1, using: &rng))
        case 1:
            return .binaryFunction(.power, tree(depth: depth - 1, using: &rng), tree(depth: depth - 1, using: &rng))
        default:
            let operation = BinaryOperator.allCases.randomElement(using: &rng) ?? .equal
            return .binary(operation, tree(depth: depth - 1, using: &rng), tree(depth: depth - 1, using: &rng))
        }
    }

    @Test("no logic tree traps or returns infinity")
    func totality() {
        var rng = SplitMix(state: 0x2026_1019)
        for _ in 0 ..< 5000 {
            let formula = Self.tree(depth: 6, using: &rng)
            do {
                let result = try formula.interpretDouble(scope: VariableScope())
                #expect(result.isFinite, "\(formula) gave \(result)")
            } catch {
                #expect(error as? FormulaError == .notANumber, "\(formula) threw \(error)")
            }
        }
    }
}
