import Foundation

// MARK: - Public interpretation API

public extension Formula {
    /// Evaluates the tree and returns a normalized result — finite or throwing,
    /// never ±∞ (Catroid `FormulaElement.interpretRecursive` followed by
    /// `assertNotNaN`). NaN at the root is the only failure.
    func interpretDouble(scope: some Scope) throws -> Double {
        let result = evaluate(scope: scope)
        if result.isNaN {
            throw FormulaError.notANumber
        }
        return result
    }

    /// `interpretDouble` narrowed with Java `Double.intValue()` semantics:
    /// truncate toward zero, saturate to the Int32 bounds. Java's `(int)` cast
    /// saturates where Swift's `Int32(_:)` traps — the same platform difference
    /// ADR-014 documents for the stitch-count guard.
    func interpretInteger(scope: some Scope) throws -> Int {
        try Self.saturatedInt32(interpretDouble(scope: scope))
    }

    /// `interpretDouble` narrowed to `Float` (Catroid interprets to Double and
    /// casts; `ZigZagStitchAction` consumes this for length and width).
    /// `Double.greatestFiniteMagnitude` narrows to +∞ in both Java and Swift —
    /// characterized by the tests, no special handling.
    func interpretFloat(scope: some Scope) throws -> Float {
        try Float(interpretDouble(scope: scope))
    }
}

// MARK: - Recursive evaluation

extension Formula {
    /// Post-order evaluation; EVERY node's result passes through `normalize`,
    /// so operands enter the parent operator already capped at
    /// ±`greatestFiniteMagnitude` (Catroid normalizes per node, see `normalize`).
    private func evaluate(scope: some Scope) -> Double {
        switch self {
        case let .number(value):
            Self.normalize(value)
        case let .variable(name):
            Self.normalize(scope.value(of: name))
        case let .binary(binaryOperator, left, right):
            Self.normalize(
                binaryOperator.apply(left.evaluate(scope: scope), right.evaluate(scope: scope))
            )
        case let .unaryMinus(operand):
            Self.normalize(-operand.evaluate(scope: scope))
        }
    }

    /// Catroid's per-node `normalizeDegeneratedDoubleValues`
    /// (`FormulaElement.java:391-394`, `FormulaElementOperations.kt:97-101`):
    /// +∞ → `Double.MAX_VALUE`, −∞ → `-Double.MAX_VALUE`; everything else —
    /// including NaN — passes through unchanged.
    private static func normalize(_ x: Double) -> Double {
        if x == .infinity {
            return .greatestFiniteMagnitude
        }
        if x == -.infinity {
            return -.greatestFiniteMagnitude
        }
        return x
    }

    /// Java `Double.intValue()` parity: truncate toward zero, saturate to the
    /// Int32 bounds. The NaN branch matches Java (`intValue(NaN) == 0`); it is
    /// unreachable after `interpretDouble`'s NaN throw but kept so the helper
    /// stays total.
    private static func saturatedInt32(_ x: Double) -> Int {
        if x.isNaN {
            return 0
        }
        let truncated = x.rounded(.towardZero)
        if truncated >= 2_147_483_647 {
            return 2_147_483_647
        }
        if truncated <= -2_147_483_648 {
            return -2_147_483_648
        }
        return Int(truncated) // strictly in range: cannot trap
    }
}

// MARK: - Operator semantics

extension BinaryOperator {
    /// Catroid `FormulaElementOperations.kt` operator semantics on operands the
    /// caller has already normalized. `plus`/`minus`/`mult` run in native
    /// `Double` — the pinned ADR-014 divergence from Catroid's decimal128.
    /// `divide` returns NaN for a zero divisor (Catroid DIVIDE; BigDecimal
    /// `equals` treats -0.0 == 0.0 there, and Swift `rhs == 0` is likewise true
    /// for -0.0; a NaN divisor fails the comparison and flows through
    /// `lhs / rhs` to NaN). `pow` is `Foundation.pow` — exact parity with
    /// Catroid's `Math.pow` on doubles. NaN stickiness is plain IEEE behavior,
    /// never special-cased.
    func apply(_ lhs: Double, _ rhs: Double) -> Double {
        switch self {
        case .plus:
            lhs + rhs
        case .minus:
            lhs - rhs
        case .mult:
            lhs * rhs
        case .divide:
            rhs == 0 ? .nan : lhs / rhs
        case .pow:
            Foundation.pow(lhs, rhs)
        }
    }
}
