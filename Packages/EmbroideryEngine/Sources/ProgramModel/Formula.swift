/// A formula expression tree (Catroid `FormulaElement.java` / `Formula.java`),
/// restricted to a numeric subset: literals, variable references, the five
/// binary operators, unary minus (M2), and Catroid's math functions, `pi` and
/// the object's own position and direction sensors (Brick backend, ADR-046). Precedence is structural — the editor/
/// parser builds the tree; evaluation never re-parses. `Codable` (synthesized:
/// every associated value is itself `Codable`) lands in US-203, where formulas
/// ship embedded under `Program`. Like `Variable.value`, a non-finite `.number`
/// payload throws under the default `JSONEncoder` (`.throw` non-conforming-float
/// strategy). ADR-037 (US-404) pins the policy in M4, which builds the first save
/// path: reject at input (`FormulaLiteral.parse`), keep the default coder, and
/// report an escaping value as `ProgramDocumentError.encodingFailed`.
public indirect enum Formula: Sendable, Equatable, Codable {
    case number(Double)
    case variable(String)
    case binary(BinaryOperator, Formula, Formula)
    case unaryMinus(Formula)
    /// A one-argument math function (Catroid `Functions`), e.g. `sin(30)`.
    case unaryFunction(UnaryFunction, Formula)
    /// A two-argument math function, e.g. `mod(7, 3)`.
    case binaryFunction(BinaryFunction, Formula, Formula)
    /// A named constant; `pi` is a zero-argument function in Catroid.
    case constant(FormulaConstant)
    /// A value read from the acting object at evaluation time.
    case sensor(Sensor)

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
        case let (.unaryFunction(leftFunction, left), .unaryFunction(rightFunction, right)):
            leftFunction == rightFunction && left == right
        case let (.binaryFunction(leftFunction, leftFirst, leftSecond),
                  .binaryFunction(rightFunction, rightFirst, rightSecond)):
            leftFunction == rightFunction
                && leftFirst == rightFirst
                && leftSecond == rightSecond
        case let (.constant(left), .constant(right)):
            left == right
        case let (.sensor(left), .sensor(right)):
            left == right
        default:
            // Mismatched cases only. When adding a Formula case, add its
            // same-case comparison above — falling in here breaks reflexivity,
            // which `FormulaCensusTests` (EditorCoreTests) catches.
            false
        }
    }
}

/// The M2 binary operator subset of Catroid `Operators.java`. No `mod`:
/// Catroid's `Operators.MOD` is dead code — the operator switch in
/// `FormulaElementOperations.kt` has no case for it and falls through to the
/// default 0; the working modulo is `Functions.MOD`, out of M2 scope.
public enum BinaryOperator: Sendable, Equatable, CaseIterable, Codable {
    case plus, minus, mult, divide, pow
}

// The four vocabularies below are part of the file format: their case names are
// the synthesized coding keys (`FormulaCodableShapeTests`), so a case is never
// renamed. Names follow Catroid's `Functions` and `Sensors` so a code.xml
// importer maps them 1:1 (ADR-046). Semantics live in `Formula+Evaluation`.

/// Catroid's one-argument math functions. Trigonometry is in degrees, as in
/// Catroid (`MathFunctionProvider`). `rand` is deferred (brief D3).
public enum UnaryFunction: Sendable, Equatable, Hashable, CaseIterable, Codable {
    // `ln` is Catroid's name and a coding key, so it is kept below the length rule.
    // swiftlint:disable:next identifier_name
    case sin, cos, tan, arcsin, arccos, arctan, sqrt, abs, round, floor, ceil, ln, log, exp
}

/// Catroid's two-argument math functions. `power` is left out: the `^`
/// operator already exists with ADR-017's pinned semantics.
public enum BinaryFunction: Sendable, Equatable, Hashable, CaseIterable, Codable {
    case arctan2, min, max, mod
}

/// Catroid's zero-argument functions that are constants. `true`/`false` join
/// with the Variables feature's logic.
public enum FormulaConstant: Sendable, Equatable, Hashable, CaseIterable, Codable {
    // Catroid's name and a coding key, so it is kept below the length rule.
    // swiftlint:disable:next identifier_name
    case pi
}

/// The object sensors a formula may read: the acting object's own needle.
public enum Sensor: Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// Catroid `OBJECT_X`: the position's x in stage units.
    case objectX
    /// Catroid `OBJECT_Y`: the position's y in stage units.
    case objectY
    /// Catroid `MOTION_DIRECTION`: the heading, folded into (−180, 180].
    case motionDirection
}
