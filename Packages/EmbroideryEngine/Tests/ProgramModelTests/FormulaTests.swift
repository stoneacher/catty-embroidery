import Foundation
import ProgramModel
import Testing

@Suite("Formula evaluation")
struct FormulaTests {
    /// ADR-014: formula arithmetic runs in native `Double` while Catroid computes
    /// PLUS/MINUS/MULT/DIVIDE in decimal128. Assertions where the two
    /// representations differ use an absolute tolerance far above binary/decimal
    /// noise and far below stitch resolution.
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
        // Exactly representable operands and results: no ADR-014 tolerance needed.
        #expect(try formula.interpretDouble(scope: emptyScope) == expected)
    }

    @Test("0.1 + 0.2 approximates 0.3 within the ADR-014 tolerance")
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
        #expect(try Formula.number(.infinity).interpretDouble(scope: emptyScope)
            == .greatestFiniteMagnitude)
        #expect(try Formula.number(-.infinity).interpretDouble(scope: emptyScope)
            == -.greatestFiniteMagnitude)
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
