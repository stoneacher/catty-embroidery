# US-404 — The program document: codec, version floor, non-finite policy

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~4 h | **Depends on**: US-401

**Story**: As a user, I want my program to become a file and come back unchanged — and if the app cannot understand a file, I want it to say so rather than quietly replace my work with a blank page.

**Freely movable** anywhere between US-401 and US-406. It needs US-401 only for the `EditorCore` target to exist; its own types consume `Program`, and its tests additionally read the shipped `Samples` and `Interpreter`. *(Codex round 1: the first draft said "consumes `Program` only", which contradicted this story's own `Depends on` line.)* This is the milestone's slack, of the kind US-211 had in M3.

## The finding that makes this story sharper than it looks

`Program` is Codable end to end today — synthesized all the way down, colours are plain hex `String`s, and `SampleJSONResourceTests` already proves the whole graph round-trips through checked-in JSON. **There is exactly one hole, and it is reachable from an ordinary number pad.**

`Formula.swift` and `Variable.swift` both carry a doc comment saying a non-finite `Double` payload throws under the default `JSONEncoder` and that **"the M5 persistence layer pins the policy"**. That sentence is now wrong about the milestone: the ROADMAP puts autosave in **M4**, so M4 builds the first save path and therefore owns the policy.

Three facts, all executed at planning time rather than reasoned about (ADR-032 invariant 4):

- `JSONEncoder` on a non-finite `Double` throws `EncodingError.invalidValue` — and `ProgramModelTests/BrickTests.swift:73` already asserts exactly that for a `Program` containing `.moveNSteps(.number(.nan))`.
- `Double("1e400")` is `+∞`. So is a 310-digit entry. Neither is adversarial; both are things a number pad accepts.
- Normalization to `±greatestFiniteMagnitude` lives in `Formula+Evaluation.swift`, i.e. at **evaluation**. The model can hold `+∞` and still be a valid `Program`.

So without this story, M4 ships an app where typing a long number into a brick silently stops autosave working.

## Acceptance criteria

- [ ] `ProgramDocument.encode(_:) throws -> Data` and `ProgramDocument.decode(_:) throws -> Program` live in `EditorCore` — **pure, no `FileManager`, no `URL`** — with `ProgramDocumentError { unsupportedVersion(Int), corrupt, encodingFailed, unbalancedScript(ScriptValidationError) }`. **The fourth case is not optional trimming**: the admission check below demands its own reason, and collapsing it into `.corrupt` loses exactly the distinction that check exists to make — a file we can parse but must not open is not the same as a file we cannot parse *(Codex round 4 found the contract still listing three cases while a criterion demanded four)*. `Script.validate()` already supplies `unmatchedLoopEnd`/`unmatchedLoopOpener`, so the reason is propagated, not invented.
- [ ] **The default `JSONEncoder` is kept.** Changing `nonConformingFloatEncodingStrategy` would put a second, divergent encoding of the same format beside the one `SampleJSONResourceTests` guards. One format, one encoding.
- [ ] **`FormulaLiteral.parse(_:) -> Result<Formula, FormulaLiteralError>` rejects non-finite input at the boundary** with a reason a person can read. This is ADR-025's shape — reject at the boundary and say which rule was broken — applied one layer up.
- [ ] **The second route to a non-finite value is closed or proved unreachable, not assumed away.** `Variable.swift`'s own doc comment says "the US-202 formula semantics let ±∞ reach a variable **at runtime**", which input rejection cannot guard, and `changeVariableBy` is the reachable route. **The interpreter builds independent runtime stores rather than mutating the `Program` it was given**, so the authored values in the document should be untouched — but that is a claim, and this story executes it rather than inheriting it (ADR-032 invariant 4): run a program that drives a variable to ±∞ through `changeVariableBy`, then assert the working `Program`'s `Variable.value` is unchanged and still encodes. **This needs no app layer and no US-405** — it is testable against shipped package code, which is why it belongs to this story rather than to the integration. If the runtime value *can* reach the document, input rejection is insufficient and the policy needs a second half; decide it here, not in US-406.
- [ ] `decode` **refuses `formatVersion > 1`** with `unsupportedVersion`, and does not migrate. `Program.currentFormatVersion` already exists and is already stamped and encoded, so this is a check, not a mechanism.
- [ ] **`decode` also refuses a structurally valid document whose scripts are unbalanced**, with its own reason, and the file is preserved exactly as an unsupported version is. This is not defensive padding: a version-1 JSON containing a bare `[loopEnd]` decodes fine through the synthesized `Codable` model, and **the document is the third door into the app** alongside a sample and the blank program *(Codex round 3)*. US-402's non-introduction guarantee and US-408's unconditional `Script.validate()` test both assume everything entering is balanced; without this check a hand-edited file falsifies both, and exit criterion 4 with them.
- [ ] Round-trip: `decode(encode(p)) == p` for a program containing every `Brick` case and every `Formula` case, asserted as whole-`Program` equality.
- [ ] **Both shipped samples round-trip** through this codec, which ties the new path to the existing `Samples` resources rather than to a fresh fixture.

**Not in this story**: touching the disk. `ProgramStoring`, the Documents path, atomic writes and the load-at-launch flow are US-406's. The split follows US-308's precedent, where `DSTDesign` (the value) and `DSTFileWriting` (the syscall) were deliberately separate.

**Also in this story, because a correction is not finished until every copy is gone** (ADR-032 invariant 3): update the claim that M5 owns this policy. It is in **`Formula.swift:8`** ("the M5 persistence layer pins the policy for the save path") and **`Variable.swift:6-8`** ("the M5 persistence layer must pin a policy … before programs are saved"). Both located by grep at planning time; **ROADMAP.md's M5 section does not contain it**, so there are two copies, not three. Re-grep for `M5 persistence` rather than trusting this list — the point of the invariant is that a written list of locations is itself a copy that can go stale.

## Test-first plan

1. `decode(encode(p)) == p` for a program exercising every `Brick` case.
2. The same for every `Formula` case, including a deeply nested `.binary`.
3. Both `SampleLibrary` programs round-trip.
4. A payload whose `formatVersion` is 2 decodes to `.unsupportedVersion(2)`; one at version 1 succeeds.
5. Truncated and non-JSON payloads produce `corrupt`, not a trap.
5b. A structurally valid version-1 payload whose script is `[loopEnd]` is **refused** with `.unbalancedScript(.unmatchedLoopEnd)` — the reason, not merely a refusal. Its counterpart: a balanced payload decodes. **Preservation of the refused file is US-406's**, since this target touches no disk.
6. `FormulaLiteral.parse("1e400")` is a failure carrying a non-finite reason — **not** a success carrying `+∞`.
7. `FormulaLiteral.parse` of a 310-digit string is the same failure. Written separately from test 6 because it is the realistic user route and the one a reviewer will not think of.
8. `FormulaLiteral.parse` accepts ordinary input — integers, decimals, a leading minus — and rejects empty, alphabetic and multi-decimal-point input.
9. **The exit test asserts `.success`**: a program built only from parser-accepted literals encodes without throwing. US-211's lesson — for a story that replaces a failure with a guard, asserting `.failure` passes while the bug is present (ADR-032 invariant 2).

## References

- ADR-037 (reserved — this story and US-406 write it), ADR-025 (reject at the boundary with a reason; the `.success` exit-test lesson)
- ADR-003 — JSON as the project format; ADR-022 — samples already ship a checked-in JSON encoding
- `Sources/ProgramModel/Formula.swift`, `Variable.swift` — the two doc comments this story corrects
- `Tests/ProgramModelTests/BrickTests.swift:73` — the existing non-finite `EncodingError` assertion
- ROADMAP M5 — the project list, versioning UI and migration machinery this story deliberately does not build
