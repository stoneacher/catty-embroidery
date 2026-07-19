/// A formula expression tree (Catroid `FormulaElement.java` / `Formula.java`),
/// restricted to the numeric M2 subset: literals, variable references, the five
/// binary operators, and unary minus. Precedence is structural — the editor/
/// parser builds the tree; evaluation never re-parses. Codable is deferred to
/// US-203, where formulas are embedded under `Program`.
public indirect enum Formula: Sendable, Equatable {
    case number(Double)
    case variable(String)
    case binary(BinaryOperator, Formula, Formula)
    case unaryMinus(Formula)

    /// NaN-aware on `.number` payloads for the same reflexivity guarantee as
    /// `Variable.==` (US-201, ADR-006): every `Double` reachable from the model
    /// compares NaN-equal, keeping whole-value assertions reflexive. All other
    /// cases compare structurally.
    public static func == (lhs: Formula, rhs: Formula) -> Bool {
        switch (lhs, rhs) {
        case let (.number(left), .number(right)):
            left.isSameValue(as: right)
        case let (.variable(left), .variable(right)):
            left == right
        case let (.binary(leftOperator, leftFirst, leftSecond),
                  .binary(rightOperator, rightFirst, rightSecond)):
            leftOperator == rightOperator
                && leftFirst == rightFirst
                && leftSecond == rightSecond
        case let (.unaryMinus(left), .unaryMinus(right)):
            left == right
        default:
            false
        }
    }
}

/// The M2 binary operator subset of Catroid `Operators.java`. No `mod`:
/// Catroid's `Operators.MOD` is dead code — the operator switch in
/// `FormulaElementOperations.kt` has no case for it and falls through to the
/// default 0; the working modulo is `Functions.MOD`, out of M2 scope.
public enum BinaryOperator: Sendable, Equatable, CaseIterable {
    case plus, minus, mult, divide, pow
}
