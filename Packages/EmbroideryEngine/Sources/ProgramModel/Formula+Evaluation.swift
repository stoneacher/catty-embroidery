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
    /// ADR-014 documents for the stitch-count guard. The result is always
    /// within `Int32.min...Int32.max` (Catroid returns a 32-bit `int`);
    /// callers never need to re-clamp.
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
        case let .unaryFunction(function, argument):
            Self.normalize(function.apply(argument.evaluate(scope: scope)))
        case let .binaryFunction(function, first, second):
            Self.normalize(function.apply(first.evaluate(scope: scope), second.evaluate(scope: scope)))
        case .constant(.pi):
            Double.pi
        case .sensor:
            // Brick backend slice 3 reads the needle; until then a sensor fails
            // like any other uninterpretable node.
            .nan
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
        // Both bounds are exactly representable as Double, so the comparisons
        // are exact.
        if truncated >= Double(Int32.max) {
            return Int(Int32.max)
        }
        if truncated <= Double(Int32.min) {
            return Int(Int32.min)
        }
        return Int(truncated) // strictly in range: cannot trap
    }
}

// MARK: - Operator semantics

extension BinaryOperator {
    /// Catroid operator semantics (`FormulaElement.interpretBinaryOperator`) on
    /// operands the caller has already normalized. `plus`/`minus`/`mult` run in
    /// native `Double` — the pinned ADR-017 divergence from Catroid's
    /// decimal128; for those, IEEE NaN propagation is equivalent to Catroid's
    /// `atLeastOneIsNaN` guard. `divide` returns NaN for a zero divisor
    /// (Catroid DIVIDE; BigDecimal `equals` treats -0.0 == 0.0 there, and Swift
    /// `rhs == 0` is likewise true for -0.0; a NaN divisor fails the comparison
    /// and flows through `lhs / rhs` to NaN). `pow` needs two explicit guards:
    /// IEEE `pow(1, NaN)` and `pow(NaN, 0)` are 1, but Catroid checks
    /// `atLeastOneIsNaN` before `Math.pow` (`FormulaElement.java:856-860`), so
    /// a NaN operand always yields NaN; and Catroid round-trips both POW
    /// operands through `BigDecimal.valueOf` (`:820-830`), which has no signed
    /// zero — `pow(-0.0, -3)` is `Math.pow(+0.0, -3)` = +∞ there, where IEEE
    /// gives −∞ (a maximum-magnitude sign flip after normalization; Codex
    /// US-202 round 1, ADR-017). Zero operands are therefore canonicalized to
    /// +0.0. For non-NaN, ∞-free, canonicalized operands `Foundation.pow` and
    /// `Math.pow` agree everywhere.
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
            if lhs.isNaN || rhs.isNaN {
                .nan
            } else {
                Foundation.pow(lhs.isZero ? 0 : lhs, rhs.isZero ? 0 : rhs)
            }
        }
    }
}

// MARK: - Function semantics (ADR-046)

/// Java's `Math.toRadians` and `Math.toDegrees` multiply by these constants
/// (JDK 9+), so `x * degreesToRadians` is the same expression Catroid evaluates.
private let degreesToRadians = 0.017453292519943295
private let radiansToDegrees = 57.29577951308232

extension UnaryFunction {
    /// Catroid `MathFunctionProvider` on an argument the caller has already
    /// normalized. Trigonometry takes and returns degrees. `round` is Java 7+
    /// `Math.round`, which differs from the engine's `javaRound` (brief D2,
    /// divergence d) and consumes a NaN as 0.
    func apply(_ x: Double) -> Double {
        switch self {
        case .sin: Foundation.sin(x * degreesToRadians)
        case .cos: Foundation.cos(x * degreesToRadians)
        case .tan: Foundation.tan(x * degreesToRadians)
        case .arcsin: Foundation.asin(x) * radiansToDegrees
        case .arccos: Foundation.acos(x) * radiansToDegrees
        case .arctan: Foundation.atan(x) * radiansToDegrees
        case .sqrt: x.squareRoot()
        case .abs: Swift.abs(x)
        case .round: Self.javaMathRound(x)
        case .floor: x.rounded(.down)
        case .ceil: x.rounded(.up)
        case .ln: Foundation.log(x)
        case .log: Foundation.log10(x)
        case .exp: Foundation.exp(x)
        }
    }

    /// Java 7+ `Math.round(double)`: the nearest `long`, ties toward +∞,
    /// computed without `floor(x + 0.5)`'s addition error (which rounds
    /// 0.49999999999999994 up). NaN is 0; out-of-range values saturate to the
    /// `long` bounds; the `long` result has no negative zero.
    static func javaMathRound(_ x: Double) -> Double {
        if x.isNaN {
            return 0
        }
        let down = x.rounded(.down)
        let rounded = x - down >= 0.5 ? down + 1 : down
        // 2^63 is exactly representable; `Double(Int64.max)` rounds up to it.
        if rounded >= 9_223_372_036_854_775_808.0 {
            return Double(Int64.max)
        }
        if rounded <= Double(Int64.min) {
            return Double(Int64.min)
        }
        return Double(Int64(rounded))
    }
}

extension BinaryFunction {
    /// Catroid `MathFunctionProvider` on arguments the caller has already
    /// normalized, with two pinned divergences (brief D2): `mod` is the floored
    /// modulo, and `arctan2` of two zeros is 0 instead of a random angle.
    func apply(_ first: Double, _ second: Double) -> Double {
        switch self {
        case .arctan2:
            // Also hides IEEE `atan2(+0, −0)` = 180°: any two zeros give 0.
            first == 0 && second == 0 ? 0 : Foundation.atan2(first, second) * radiansToDegrees
        case .min:
            Self.javaMin(first, second)
        case .max:
            -Self.javaMin(-first, -second)
        case .mod:
            Self.flooredMod(first, second)
        }
    }

    /// Java `Math.min`: NaN if either argument is NaN, and −0 below +0. Both
    /// Swift spellings differ (`min(1, .nan)` is 1; `Double.minimum` drops NaN).
    private static func javaMin(_ lhs: Double, _ rhs: Double) -> Double {
        if lhs.isNaN || rhs.isNaN {
            return .nan
        }
        if lhs == 0, rhs == 0 {
            return lhs.sign == .minus ? lhs : rhs
        }
        return lhs < rhs ? lhs : rhs
    }

    /// The result takes the divisor's sign. This is what Catroid's
    /// `interpretFunctionMod` implements, except that it returns the divisor
    /// for a zero remainder with a positive dividend and negative divisor
    /// (`6 mod −3` is −3 there) and loops forever once `dividend + |divisor|`
    /// stops changing the dividend. A zero dividend or divisor returns the
    /// dividend, as in Catroid.
    private static func flooredMod(_ dividend: Double, _ divisor: Double) -> Double {
        if dividend == 0 || divisor == 0 {
            return dividend
        }
        var remainder = dividend.truncatingRemainder(dividingBy: divisor)
        if remainder != 0, (remainder < 0) != (divisor < 0) {
            remainder += divisor
        }
        return remainder
    }
}
