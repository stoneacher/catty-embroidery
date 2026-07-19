import Foundation
import ProgramModel
import Testing

@Suite("Formula evaluation")
struct FormulaTests {
    /// ADR-017: formula arithmetic runs in native `Double` while Catroid computes
    /// PLUS/MINUS/MULT/DIVIDE in decimal128. Assertions where the two
    /// representations differ use an ADR-014-style absolute tolerance, valid for
    /// this suite's near-unity inputs (not universally — see ADR-017's
    /// cancellation/conditioning caveat).
    private func expect(
        _ value: Double,
        approximates expected: Double,
        tolerance: Double = 1e-9,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(value - expected) <= tolerance,
            "\(value) is not within \(tolerance) of \(expected)",
            sourceLocation: sourceLocation
        )
    }

    private let emptyScope = VariableScope()

    // MARK: - Test plan 1: literals, operators, unary minus

    @Test(
        "literals and operators evaluate to their exact expected values",
        arguments: [
            (Formula.number(7.5), 7.5),
            (.binary(.plus, .number(2), .number(3)), 5),
            (.binary(.minus, .number(10), .number(4)), 6),
            (.binary(.mult, .number(6), .number(7)), 42),
            (.binary(.divide, .number(1), .number(4)), 0.25),
            (.binary(.pow, .number(2), .number(10)), 1024),
            (.binary(.pow, .number(2), .number(-2)), 0.25),
            (.unaryMinus(.number(5)), -5),
            (.unaryMinus(.unaryMinus(.number(5))), 5)
        ] as [(Formula, Double)]
    )
    func exactEvaluation(formula: Formula, expected: Double) throws {
        // Exactly representable operands and results: no ADR-017 tolerance needed.
        #expect(try formula.interpretDouble(scope: emptyScope) == expected)
    }

    @Test("0.1 + 0.2 approximates 0.3 within the ADR-017 tolerance")
    func binaryDoubleDivergenceFromDecimal128() throws {
        // Catroid's decimal128 yields exactly 0.3; native Double yields
        // 0.30000000000000004 — the pinned, accepted divergence.
        let sum = try Formula.binary(.plus, .number(0.1), .number(0.2))
            .interpretDouble(scope: emptyScope)
        expect(sum, approximates: 0.3)
    }

    // MARK: - Test plan 2: precedence lives in the tree structure

    @Test("nested tree evaluates in structural order, not re-parsed precedence")
    func structuralNesting() throws {
        let formula = Formula.binary(
            .mult,
            .number(2),
            .binary(.plus, .number(3), .number(4))
        )
        #expect(try formula.interpretDouble(scope: emptyScope) == 14)
    }

    // MARK: - Test plan 3: interpretInteger / interpretFloat contracts

    @Test(
        "interpretInteger truncates toward zero and saturates at Java Int32 bounds",
        arguments: [
            (2.9, 2),
            (-2.9, -2),
            (2.0, 2),
            (2_147_483_646.9, 2_147_483_646),
            (2_147_483_647.0, 2_147_483_647),
            (2_147_483_647.9, 2_147_483_647),
            (-2_147_483_648.0, -2_147_483_648),
            (-2_147_483_648.9, -2_147_483_648),
            (1e19, 2_147_483_647),
            (-1e19, -2_147_483_648),
            (.infinity, 2_147_483_647),
            (-.infinity, -2_147_483_648)
        ] as [(Double, Int)]
    )
    func integerTruncationAndSaturation(value: Double, expected: Int) throws {
        // Java `Double.intValue()` semantics: (int) cast truncates toward zero and
        // saturates; Swift's `Int32(_:)` would trap. The ±∞ rows reach saturation
        // as ±greatestFiniteMagnitude because every node normalizes non-finites.
        #expect(try Formula.number(value).interpretInteger(scope: emptyScope) == expected)
    }

    @Test("interpretFloat narrows the double result to Float")
    func floatNarrowing() throws {
        // ZigZagStitchAction uses interpretFloat for both length and width.
        #expect(try Formula.number(1.5).interpretFloat(scope: emptyScope) == 1.5)
        // Double.greatestFiniteMagnitude exceeds Float range; both Java's
        // double→float narrowing and Swift's Float(_:) give +∞. Characterized,
        // not diverged from.
        let max = try Formula.number(.greatestFiniteMagnitude).interpretFloat(scope: emptyScope)
        #expect(max == .infinity)
        let min = try Formula.number(-.greatestFiniteMagnitude).interpretFloat(scope: emptyScope)
        #expect(min == -.infinity)
    }

    // MARK: - Test plan 4: NaN throws at the root; ∞ never survives a node

    @Test(
        "a zero divisor yields NaN and therefore throws",
        arguments: [
            (Formula.binary(.divide, .number(1), .number(0)), "1/0"),
            (.binary(.divide, .number(0), .number(0)), "0/0"),
            (.binary(.divide, .number(1), .number(-0.0)), "1/-0.0")
        ] as [(Formula, String)]
    )
    func zeroDivisorThrows(formula: Formula, label: String) {
        // Catroid's DIVIDE returns NaN for a zero divisor (BigDecimal 0.0 and
        // -0.0 compare equal there) — never IEEE ∞ — and assertNotNaN rejects it.
        #expect(throws: FormulaError.notANumber, "\(label) must throw") {
            _ = try formula.interpretDouble(scope: emptyScope)
        }
    }

    @Test("NaN is sticky: a NaN subtree poisons every enclosing operator")
    func nanStickiness() {
        let nanSubtree = Formula.binary(.divide, .number(0), .number(0))
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(.plus, nanSubtree, .number(5))
                .interpretDouble(scope: emptyScope)
        }
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.unaryMinus(nanSubtree).interpretDouble(scope: emptyScope)
        }
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.number(.nan).interpretDouble(scope: emptyScope)
        }
    }

    @Test("NaN is sticky through pow even where IEEE pow is not")
    func nanStickinessThroughPow() {
        // IEEE 754 pow(1, NaN) == 1 and pow(NaN, 0) == 1; Catroid guards POW
        // with atLeastOneIsNaN (FormulaElement.java:856-860) so a NaN operand
        // always yields NaN and throws at the root — mirrored, not IEEE.
        let nanSubtree = Formula.binary(.divide, .number(0), .number(0))
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(.pow, .number(1), nanSubtree)
                .interpretDouble(scope: emptyScope)
        }
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(.pow, nanSubtree, .number(0))
                .interpretDouble(scope: emptyScope)
        }
    }

    @Test(
        "NaN is sticky through every binary operator on either side",
        arguments: BinaryOperator.allCases
    )
    func nanStickyThroughEveryOperator(binaryOperator: BinaryOperator) {
        let nanSubtree = Formula.binary(.divide, .number(0), .number(0))
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(binaryOperator, nanSubtree, .number(2))
                .interpretDouble(scope: emptyScope)
        }
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(binaryOperator, .number(2), nanSubtree)
                .interpretDouble(scope: emptyScope)
        }
    }

    @Test("pow outside the real domain yields NaN and throws")
    func powDomainErrorThrows() {
        // Math.pow(-1, 0.5) and IEEE pow agree: NaN — normalized unchanged,
        // rejected at the root.
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.binary(.pow, .number(-1), .number(0.5))
                .interpretDouble(scope: emptyScope)
        }
    }

    @Test("pow loses the zero sign like Catroid's BigDecimal operand round-trip")
    func powZeroSignParity() throws {
        // Catroid converts POW operands through BigDecimal.valueOf before
        // Math.pow (FormulaElement.java:820-830, 856-860), and BigDecimal has no
        // signed zero: pow(-0.0, -3) is Math.pow(+0.0, -3) = +∞ → +MAX_VALUE.
        // IEEE pow(-0.0, -3) is -∞ — the sign of a maximum-magnitude result
        // flips without zero canonicalization (Codex US-202 round 1, ADR-017).
        #expect(try Formula.binary(.pow, .number(-0.0), .number(-3))
            .interpretDouble(scope: emptyScope) == .greatestFiniteMagnitude)
        // Reachable without a -0.0 literal: unary minus negates a zero.
        #expect(try Formula.binary(.pow, .unaryMinus(.number(0)), .number(-3))
            .interpretDouble(scope: emptyScope) == .greatestFiniteMagnitude)
        // The finite-result case keeps Catroid's positive zero.
        let zero = try Formula.binary(.pow, .number(-0.0), .number(3))
            .interpretDouble(scope: emptyScope)
        #expect(zero == 0 && zero.sign == .plus)
    }

    @Test(
        "overflow in every binary operator normalizes to ±greatestFiniteMagnitude",
        arguments: [
            (Formula.binary(.plus, .number(.greatestFiniteMagnitude), .number(.greatestFiniteMagnitude)),
             Double.greatestFiniteMagnitude),
            (.binary(.minus, .number(-.greatestFiniteMagnitude), .number(.greatestFiniteMagnitude)),
             -.greatestFiniteMagnitude),
            (.binary(.mult, .number(.greatestFiniteMagnitude), .number(2)),
             .greatestFiniteMagnitude),
            (.binary(.divide, .number(.greatestFiniteMagnitude), .number(.leastNonzeroMagnitude)),
             .greatestFiniteMagnitude)
        ] as [(Formula, Double)]
    )
    func overflowNormalizesInEveryOperator(formula: Formula, expected: Double) throws {
        // Catroid's decimal128 intermediate is exact here, but .doubleValue()
        // overflows to ±∞ and the per-node normalization caps it — same
        // observable result as native Double arithmetic.
        #expect(try formula.interpretDouble(scope: emptyScope) == expected)
    }

    @Test("pow overflow normalizes to greatestFiniteMagnitude instead of ∞")
    func powOverflowNormalizes() throws {
        // Catroid normalizes every node's result (normalizeDegeneratedDoubleValues):
        // +∞ → Double.MAX_VALUE, so overflow neither throws nor yields ∞.
        let overflow = Formula.binary(.pow, .number(1e308), .number(2))
        #expect(try overflow.interpretDouble(scope: emptyScope) == .greatestFiniteMagnitude)

        let negativeOverflow = Formula.binary(.pow, .number(-1e308), .number(3))
        #expect(try negativeOverflow.interpretDouble(scope: emptyScope) == -.greatestFiniteMagnitude)
    }

    @Test("an overflowed operand enters the parent operator as greatestFiniteMagnitude")
    func overflowedOperandStaysFinite() throws {
        // Amended AC (2026-07-19): operands are normalized before entering the
        // parent operator, so pow(1e308, 2) + 1 is MAX_VALUE + 1 ≈ MAX_VALUE —
        // not the originally claimed coerce-∞-to-0 result of 1.
        let overflow = Formula.binary(.pow, .number(1e308), .number(2))
        let sum = Formula.binary(.plus, overflow, .number(1))
        #expect(try sum.interpretDouble(scope: emptyScope) == .greatestFiniteMagnitude)
    }

    @Test("infinity literals normalize at the leaf")
    func infinityLiteralsNormalize() throws {
        // Pinned divergence (ADR-017): Catroid NUMBER nodes are strings, which
        // skip normalization — a crafted NUMBER("Infinity") root survives as +∞
        // there and coerces to 0 as a BigDecimal operand. Our literal is
        // Double-typed, no editor can produce an ∞ literal, and it normalizes
        // uniformly like every computed value.
        #expect(try Formula.number(.infinity).interpretDouble(scope: emptyScope)
            == .greatestFiniteMagnitude)
        #expect(try Formula.number(-.infinity).interpretDouble(scope: emptyScope)
            == -.greatestFiniteMagnitude)
        // Nested case of the same pinned divergence: Catroid's string operand
        // "Infinity" coerces to 0 inside PLUS (result 1); our Double literal is
        // already MAX_VALUE when it enters the operator.
        #expect(try Formula.binary(.plus, .number(.infinity), .number(1))
            .interpretDouble(scope: emptyScope) == .greatestFiniteMagnitude)
    }

    @Test("evaluation errors are catchable as a plain Error (US-205 fallback-and-continue)")
    func errorIsCatchableGenerically() {
        do {
            _ = try Formula.binary(.divide, .number(1), .number(0))
                .interpretDouble(scope: emptyScope)
            Issue.record("expected a zero divisor to throw")
        } catch {
            #expect(error is FormulaError)
        }
    }

    // MARK: - Test plan 5: variable resolution

    @Test("a project-scoped variable resolves to its value")
    func projectVariableResolves() throws {
        let scope = VariableScope(projectVariables: [Variable(name: "size", value: 250)])
        #expect(try Formula.variable("size").interpretDouble(scope: scope) == 250)
    }

    @Test("an object-scoped variable shadows a same-named project variable")
    func objectVariableShadowsProject() throws {
        // Catroid UserDataWrapper.getUserVariable: sprite scope first, then project.
        let scope = VariableScope(
            objectVariables: [Variable(name: "speed", value: 3)],
            projectVariables: [Variable(name: "speed", value: 1)]
        )
        #expect(try Formula.variable("speed").interpretDouble(scope: scope) == 3)
    }

    @Test("a variable value is normalized like any other node")
    func variableValueIsNormalized() throws {
        // Variables can hold non-finite values at runtime (Variable.swift); the
        // .variable node passes through the same per-node normalization as
        // literals and operator results.
        let scope = VariableScope(projectVariables: [
            Variable(name: "overflow", value: .infinity),
            Variable(name: "invalid", value: .nan)
        ])
        #expect(try Formula.variable("overflow").interpretDouble(scope: scope)
            == .greatestFiniteMagnitude)
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.variable("invalid").interpretDouble(scope: scope)
        }
    }

    @Test("a NaN object variable shadows a finite project variable and throws")
    func nanShadowingThrows() {
        // Shadowing resolves by name before the value is inspected: the object's
        // NaN wins over the project's finite value and poisons the evaluation —
        // no silent fallback to the project variable.
        let scope = VariableScope(
            objectVariables: [Variable(name: "x", value: .nan)],
            projectVariables: [Variable(name: "x", value: 1)]
        )
        #expect(throws: FormulaError.notANumber) {
            _ = try Formula.variable("x").interpretDouble(scope: scope)
        }
    }

    @Test("an unknown variable evaluates to 0")
    func unknownVariableIsZero() throws {
        let scope = VariableScope(projectVariables: [Variable(name: "size", value: 250)])
        #expect(try Formula.variable("missing").interpretDouble(scope: scope) == 0)
        #expect(try Formula.binary(.plus, .variable("missing"), .number(2))
            .interpretDouble(scope: scope) == 2)
    }

    // MARK: - Formula equality (ADR-006 reflexive whole-value assertions)

    @Test("NaN literals keep formula equality reflexive")
    func nanEqualityIsReflexive() {
        // Same invariant US-201 pinned for Variable/Object: every Double reachable
        // from the model compares NaN-equal, so whole-value assertions stay
        // reflexive once US-203 embeds formulas under Program.
        #expect(Formula.number(.nan) == Formula.number(.nan))
        let nested = Formula.binary(.plus, .number(.nan), .variable("x"))
        #expect(nested == nested)
        #expect(Formula.number(.nan) != Formula.number(0))
    }

    @Test("structurally different formulas compare unequal")
    func structuralInequality() {
        #expect(Formula.unaryMinus(.number(1)) != Formula.number(-1))
        #expect(Formula.binary(.plus, .number(1), .number(2))
            != Formula.binary(.minus, .number(1), .number(2)))
    }
}
