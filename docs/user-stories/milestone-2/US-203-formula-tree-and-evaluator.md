# US-203 — Formula tree and evaluator

**Epic**: E3 Program model & interpreter | **Estimate**: ~5 h | **Depends on**: US-201

**Status**: Planned

**Story**: As a brick, I want to interpret a formula of literals, arithmetic operators, and variables to a number, mirroring Catroid's evaluator semantics.

## Acceptance criteria
- [ ] `Formula` is an `indirect enum`: `number(Double)`, `variable(String)`, `binary(BinaryOperator, Formula, Formula)`, `unaryMinus(Formula)` — mirroring Catroid's `FormulaElement` tree restricted to the M2 subset (NUMBER, USER_VARIABLE, OPERATOR). Operators: `plus`, `minus`, `mult`, `divide`, `mod`, `pow`. Unary minus mirrors Catroid's MINUS-with-only-a-right-child. Brackets are omitted from the tree (a parse/round-trip concern for the `.catrobat` importer, stretch scope — precedence is encoded structurally in M2).
- [ ] `interpretDouble(scope:) throws`: recursive evaluation; **throws on NaN** (Catroid `assertNotNaN` → `InterpretationException`) and on non-finite results (divide by zero, invalid mod/pow).
- [ ] `interpretInteger(scope:)` = `interpretDouble` truncated **toward zero** (Java `Double.intValue()`; Swift `Int(_:)` matches) — the contract for running/triple stitch length (Catroid `RunningStitchAction`/`TripleStitchAction` use `interpretInteger`). `interpretFloat(scope:)` returns `Float` — zigzag length **and** width use it (`ZigZagStitchAction` uses `interpretFloat` for both).
- [ ] Variable scoping: object-scoped variables shadow same-named project-scoped ones (Catroid `UserDataWrapper.getUserVariable`: sprite-first, then project). Unknown variable evaluates to 0. The evaluator takes a read-only `Scope`; mutation belongs to the interpreter (US-205).

## Test-first plan
1. Literal and each operator on known inputs, including `mod` and `pow`; unary minus.
2. Structural nesting evaluates in tree order: `binary(.mult, number(2), binary(.plus, number(3), number(4)))` = 14 (precedence lives in structure, not re-parsing).
3. `interpretInteger` truncates toward zero: 2.9 → 2, −2.9 → −2 (not floor).
4. Divide-by-zero and NaN-producing formulas throw; the error type is caught-able by brick execution (US-205's default-and-continue relies on it).
5. Variable resolution: project variable read; object variable shadows a same-named project variable; unknown variable → 0.

## References
- `Catroid/.../formulaeditor/Formula.java` (`interpretDouble`/`interpretInteger`/`interpretFloat`), `FormulaElement.java` (`interpretRecursive`), `Operators.java`, `UserDataWrapper.java`, `InterpretationException.java`
- `Catroid/.../content/actions/RunningStitchAction.java`, `ZigZagStitchAction.java` (per-brick interpret-type split)
