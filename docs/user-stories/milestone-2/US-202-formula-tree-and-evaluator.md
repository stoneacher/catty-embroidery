# US-202 — Formula tree and evaluator

**Epic**: E3 Program model & interpreter | **Estimate**: ~5 h | **Depends on**: US-201

**Status**: Planned

**Story**: As a brick, I want to interpret a formula of literals, arithmetic operators, and variables to a number, mirroring Catroid's evaluator semantics.

## Acceptance criteria
- [ ] `Formula` is an `indirect enum`: `number(Double)`, `variable(String)`, `binary(BinaryOperator, Formula, Formula)`, `unaryMinus(Formula)` — mirroring Catroid's `FormulaElement` tree restricted to the M2 subset (NUMBER, USER_VARIABLE, OPERATOR). Operators: `plus`, `minus`, `mult`, `divide`, `pow`. Unary minus mirrors Catroid's MINUS-with-only-a-right-child. **No `mod` operator**: Catroid declares `Operators.MOD` but `tryInterpretOperator` has no case for it (it falls through to 0) — the working modulo is `Functions.MOD`, a *function*, and functions are outside the M2 subset. Brackets are omitted from the tree (a parse/round-trip concern for the `.catrobat` importer, stretch scope — precedence is encoded structurally in M2).
- [ ] `interpretDouble(scope:) throws`: recursive evaluation; **throws on NaN only** (Catroid `assertNotNaN` checks `Double.isNaN()` and nothing else — `InterpretationException`). **±Infinity propagates as a value**, matching Catroid: `1/0` evaluates to `+∞` successfully, `Math.pow` overflow returns `∞`; only `0/0`-style NaN throws.
- [ ] `interpretInteger(scope:)` = `interpretDouble` truncated **toward zero** for in-range values (Java `Double.intValue()`), and **saturating** (not trapping) for out-of-range magnitudes and ±∞ — Java's narrowing conversion saturates where Swift's `Int(_:)` traps, a platform difference the engine already documents (`StitchPattern.swift` `maxStitchesPerUpdate` comment). Exact saturation bound (Java's `Int32` vs Swift's `Int`) is pinned during this story. This is the contract for running/triple stitch length (Catroid `RunningStitchAction`/`TripleStitchAction` use `interpretInteger`). `interpretFloat(scope:)` returns `Float` — zigzag length **and** width use it (`ZigZagStitchAction` uses `interpretFloat` for both).
- [ ] Variable scoping: object-scoped variables shadow same-named project-scoped ones (Catroid `UserDataWrapper.getUserVariable`: sprite-first, then project). Unknown variable evaluates to 0. The evaluator takes a read-only `Scope`; mutation belongs to the interpreter (US-205).

## Test-first plan
1. Literal and each operator on known inputs, including `pow`; unary minus.
2. Structural nesting evaluates in tree order: `binary(.mult, number(2), binary(.plus, number(3), number(4)))` = 14 (precedence lives in structure, not re-parsing).
3. `interpretInteger` truncates toward zero: 2.9 → 2, −2.9 → −2 (not floor); out-of-range: 1e19 and `+∞` saturate to the pinned bound instead of trapping.
4. NaN-producing formula (`0/0`) throws; `1/0` evaluates to `+∞` without throwing (Catroid `assertNotNaN` semantics). The error type is caught-able by brick execution (US-205's fallback-and-continue relies on it).
5. Variable resolution: project variable read; object variable shadows a same-named project variable; unknown variable → 0.

## References
- `Catroid/.../formulaeditor/Formula.java` (`interpretDouble`/`interpretInteger`/`interpretFloat`, `assertNotNaN`), `FormulaElement.java` (`interpretRecursive`, `tryInterpretOperator` — no MOD case), `Operators.java`, `UserDataWrapper.java`, `InterpretationException.java`
- `Catroid/.../content/actions/RunningStitchAction.java`, `ZigZagStitchAction.java` (per-brick interpret-type split)
- `EmbroideryEngine` `StitchPattern.swift` (documented Java-saturates-vs-Swift-traps platform difference)
