# US-209 — Pattern→stream→bytes differential test

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-207

**Status**: In review — 2026-07-30. Implemented and CI green; **the Ink/Stitch half of
the fixture's trust verification is outstanding** (AC 2), so the story cannot close yet.

**Story**: As a maintainer, I want an interpreted program piped through `EmbroideryStream` → `DSTFile` to bytes and diffed against a golden `.dst`, closing the test blind spot carried in the workflow journal since US-108: no test yet covers the full pattern-output-to-real-bytes path.

## Acceptance criteria
- [x] The square program's (US-207) `assembledStream()` feeds `DSTFile(stream:name:)`; the emitted bytes are byte-diffed against a committed golden fixture. `ByteDiff` is internal to the `EmbroideryEngineTests` target and SPM test resources are declared per target, so this story does the plumbing explicitly: either a small shared test-support target or a deliberate copy of the helper into `InterpreterTests`, plus the golden fixture declared as a `Bundle.module` resource of the test target running this test (a `Package.swift` change inside this story). **Resolved as the deliberate copy** — SwiftPM forbids a test target depending on another test target, so sharing would mean test-only code under `Sources/` plus `import Testing` in a library target (and the package has no external dependencies today). Both copies cross-reference each other; promotion trigger recorded: if a third target needs them, promote then.
- [ ] The golden fixture is **verified in an embroidery viewer before being trusted** (ADR-012 discipline: a golden derived from our own output must be externally validated once). Manual Ink/Stitch check happens in this story. — **Half done.** The independent byte-level decode passed (the repo's own `DSTFileReader`/`DSTRecordDecoder`, which share no definitions with the writer): 22 records, 0 jumps, 0 colour changes, positions equal to `goldenSquareRecords`, every header field as expected. **The Ink/Stitch check is outstanding**, and `PROVENANCE.md` says so — until it is done the fixture is a regression anchor, not an externally validated golden.
- [x] Header assertions: stitch count and `CO = colorChangeCount + 1` match the program's actual stitch and color-stop counts (US-104 semantics). Read out of the **file** bytes, not a separately built `DSTHeader` (which is what US-208 did and cannot see a serializer that fails to emit the header it built), and compared against the run's own `stream.count` / `colorChangeCount`, not against literals.
- [x] Differential assertion: interpreter-assembled bytes equal the bytes of a hand-built `EmbroideryStream` encoding the same geometry — the interpreter path and the manual path converge. **Deviation — the AC as written is close to vacuous, and the test now says so instead of claiming otherwise.** `DSTFile` is a pure function of the stream, so both sides of the comparison run through the same serializer and every defect in `DSTFile`/`DSTHeader`/`DSTStitchRecord` cancels; US-207 already pins the interpreter's stream against the same geometry in unit space, more strongly. Measured, not argued: mutating `stitchPointUnitFactor` 2.0 → 1.0 takes 106 assertions red while leaving this one **green**, because both paths move together. Implemented anyway (Sebastian chose the hand-built-stream form during planning) with its limit documented in the suite header, and its real contribution stated honestly: it makes the 22-versus-21 dedup structure executable rather than a comment plus a count, and states the design's pre-conversion **stage** geometry, which the already-converted `goldenSquareRecords` cannot. The serializer mutants are caught by the committed-fixture leg, whose expected side cannot move with the code.

### Added beyond the ACs
- [x] **The name join**: the design name travels program brick → `.finalizeRequested` → `DSTFile` → the `LA` field, and is sanitized at the header rather than by the interpreter. Nothing in the package joined those before. Package-unique: a mutant that pre-sanitizes the name in `Interpreter+Step` takes **exactly one** test red.
- [x] **ADR-019 threshold screening** for the two thresholds this story newly compares against (the ±121 record delta — margin 111; and the ×2 + `javaRound` conversion boundary — full half-unit margin), plus the residue class the manual path depends on, pinned at both ends (ε = 0 dedups to 21 records; ε = 0.25 moves the coordinate). The pattern-interval threshold is *inherited*: ADR-019 states outright that US-207's square needs no tripwire, and this story changes no geometry.
- [x] A wholly-negative-space design (`GoldenSquare.displacedProgram`) reaching `DSTHeader` through a real interpreted program — composition coverage ADR-012 calls for. **Not** a unique mutant kill: an earlier comment claimed it was and mutation testing disproved it (see close-out).

## Test-first plan
1. Square program → `DSTFile.data` equals the golden `.dst` fixture (loaded via `Bundle.module` from this test target's own resources), byte-for-byte via the shared/copied `ByteDiff` helper.
2. Header stitch-count and CO fields match computed expectations.
3. Interpreter-path bytes == manual-stream-path bytes for identical geometry.

**Manual verification (flag for Sebastian)**: before committing the golden fixture, open the freshly generated square `.dst` in Ink/Stitch and check it loads, renders a closed square with a tie-off, and reports the expected stitch count and one color block. The fixture is trusted only after this check; note the result in the story close-out.

## References
- `docs/workflow-journal.md` 2026-07-13 / 2026-07-14 / 2026-07-16 (carry-forward: pattern→stream→bytes blind spot)
- M1 `ByteDiff` test helper; US-104 header semantics; ADR-012 in `docs/DECISIONS.md`

## Outcome

Test-only; no production code changed. 334 tests green, `swiftlint --strict` clean,
CI green. Golden fixture `Tests/InterpreterTests/Resources/GoldenPrograms/square.dst`,
581 bytes (512 + 22·3 + 3), SHA-256 `4a76c57d…74ff`, `ST 22`, `CO 1`.

**What the byte path actually adds, stated narrowly.** `DSTFile` is a pure *and lossy*
function of the stream — DST carries no thread-colour table, only change flags — so
every interpreter defect visible in the bytes is already visible in `assembledStream()`,
which US-207 pins twice over. This story therefore adds **no interpreter
discrimination**. What it adds is composition (a real program's header, deltas and
terminator), the name join, the negative-space extent route, and a fixture whose
expected side cannot move with the code. The journal's "blind spot" wording was
broader than what closing it could deliver, and the close-out entry corrects that.

**Mutation matrix** (measured, per US-208's lesson that measuring must precede the
claim): CO drops `+1` → 17 issues; record delta x reversed → 11; end-of-file record
dropped → 17; unit factor 2.0 → 1.0 → 106 **with the manual-path leg green**;
interpreter pre-sanitizes the name → exactly 1. Seeding the first record at the origin
instead of `previous ?? stitch.position` **traps** rather than failing (the delta
exceeds ±121), so it is detected but is not a usable mutant. Not claimed:
`javaRound` → `.rounded()` survives the whole suite, since no stage value in this
design is a negative half — US-105/106 own that edge.

**A claim I wrote and mutation testing disproved.** I asserted the displaced square
uniquely killed `abs(box.min.x)` in place of `abs(min(box.min.x - first.x, 0))`. With
that test skipped the mutant still takes `DSTHeaderTests.nonOriginFirstStitch` and a
round-trip test red — its synthetic stream has first stitch (20, 10) over a box starting
at (0, 0), so the mutant reads 0 where 20 is correct. The comment now claims only the
route, not the kill. Same defect class US-207 and US-208 each surfaced; caught here
because the mutation was run before the claim was committed.

**Gap found and deliberately left open**: no test in the package pins a *negative*
`AX`/`AY`. Every existing case has `last >= first`, and a closed design has
`AX = AY = 0`, so neither square can reach it — a mutant `AX = abs(last.x - first.x)`
(the mirror of the Catty signed-extent bug ADR-012 says not to port) survives
everything. Closing it is ~3 lines in `DSTHeaderTests`, i.e. the engine target and M1
semantics, so it is flagged rather than folded into this story.

**Manual Ink/Stitch verification: REQUIRED and still outstanding** — see AC 2 and the
fixture's `PROVENANCE.md`, which carries the check-list, the two benign observations to
expect (a viewer may collapse the zero-delta 18th record; sub-millimetre tack legs draw
short-stitch warnings), and the note that "renders empty" would be a real finding here,
unlike the US-101 Catty fixtures.
