# US-209 — Pattern→stream→bytes differential test

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-207

**Status**: Done — 2026-07-31. Fixture externally verified (viewer + independent decode).

**Story**: As a maintainer, I want an interpreted program piped through `EmbroideryStream` → `DSTFile` to bytes and diffed against a golden `.dst`, closing the test blind spot carried in the workflow journal since US-108: no test yet covers the full pattern-output-to-real-bytes path.

## Acceptance criteria
- [x] The square program's (US-207) `assembledStream()` feeds `DSTFile(stream:name:)`; the emitted bytes are byte-diffed against a committed golden fixture. `ByteDiff` is internal to the `EmbroideryEngineTests` target and SPM test resources are declared per target, so this story does the plumbing explicitly: either a small shared test-support target or a deliberate copy of the helper into `InterpreterTests`, plus the golden fixture declared as a `Bundle.module` resource of the test target running this test (a `Package.swift` change inside this story). **Resolved as the deliberate copy** — SwiftPM forbids a test target depending on another test target, so sharing would mean test-only code under `Sources/` plus `import Testing` in a library target (and the package has no external dependencies today). Both copies cross-reference each other; promotion trigger recorded: if a third target needs them, promote then.
- [x] The golden fixture is **verified in an embroidery viewer before being trusted** (ADR-012 discipline: a golden derived from our own output must be externally validated once). Manual Ink/Stitch check happens in this story. — **Both halves passed.** Independent byte-level decode (the repo's own `DSTFileReader`/`DSTRecordDecoder`, which share no definitions with the writer): 22 records, 0 jumps, 0 colour changes, positions equal to `goldenSquareRecords`, every header field as expected. Viewer (Sebastian, 2026-07-31): loads, renders a closed square walked bottom-left upwards, reports **4.00 × 4.60 mm, 22 stitches, 0 colour changes, 0 jumps, 0 trims, 0 stops**. The downward spur below the start corner is the `sewUp` tack's `behind` leg — its `ahead` leg lies along the square's own left edge and is invisible — and the 4.60 mm height is the arithmetic proof: 40 units of square plus exactly the 6 the tack hangs below (`-Y 6`).
- [x] Header assertions: stitch count and `CO = colorChangeCount + 1` match the program's actual stitch and color-stop counts (US-104 semantics). Read out of the **file** bytes, not a separately built `DSTHeader` (which is what US-208 did and cannot see a serializer that fails to emit the header it built), and compared against the run's own `stream.count` / `colorChangeCount`, not against literals.
- [x] Differential assertion: interpreter-assembled bytes equal the bytes of a hand-built `EmbroideryStream` encoding the same geometry — the interpreter path and the manual path converge. **Deviation — the AC as written is close to vacuous, and the test now says so instead of claiming otherwise.** `DSTFile` is a pure function of the stream, so both sides of the comparison run through the same serializer and every defect in `DSTFile`/`DSTHeader`/`DSTStitchRecord` cancels; US-207 already pins the interpreter's stream against the same geometry in unit space, more strongly. Measured, not argued: mutating `stitchPointUnitFactor` 2.0 → 1.0 takes 106 assertions red while leaving this one **green**, because both paths move together. Implemented anyway (Sebastian chose the hand-built-stream form during planning) with its limit documented in the suite header, and its real contribution stated honestly: it makes the 22-versus-21 dedup structure executable rather than a comment plus a count, and states the design's pre-conversion **stage** geometry, which the already-converted `goldenSquareRecords` cannot. The serializer mutants are caught by the committed-fixture leg, whose expected side cannot move with the code.

### Added beyond the ACs
- [x] **The name join**: the design name travels program brick → `.finalizeRequested` → `DSTFile` → the `LA` field, and is sanitized at the header rather than by the interpreter. Nothing in the package joined those before. Package-unique: a mutant that pre-sanitizes the name in `Interpreter+Step` takes **exactly one** test red.
- [x] **ADR-019 threshold screening** for the two thresholds this story newly compares against: the ±121 record delta (max per-axis delta 10, margin 111), and the ×2 + `javaRound` conversion boundary, measured on the **interpreter's own** stage points — worst margin ~7e-15 against a 0.5 boundary. Plus the residue class the manual path depends on, pinned at both ends (ε = 0 dedups to 21 records; ε = 0.25 moves the coordinate). The pattern-interval threshold is *inherited*: ADR-019 states outright that US-207's square needs no tripwire, and this story changes no geometry.
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
every interpreter defect *that reaches the stream* is already visible in
`assembledStream()`, which US-207 pins twice over. Almost nothing here therefore adds
interpreter discrimination; what it adds is composition (a real program's header, deltas
and terminator), the negative-space extent route, and a fixture whose expected side
cannot move with the code. The journal's "blind spot" wording was broader than what
closing it could deliver, and the close-out entry corrects that.

The **name join is the exception**, and it is precise: a design name never enters
`assembledStream()` at all — it lives only in the `.finalizeRequested` payload — so it
sits outside that argument, and the name test is the package's only killer of an
interpreter-side name mutant. An earlier version of this paragraph said "no interpreter
discrimination" flatly, which undersold the one genuinely new discriminator in the story
(`swift-code-reviewer`).

**Mutation matrix** (measured, per US-208's lesson that measuring must precede the
claim): CO drops `+1` → 17 issues; record delta x reversed → 11; end-of-file record
dropped → 17; unit factor 2.0 → 1.0 → 106 with the **AC-4 convergence leg** green
(precisely that one test, not the whole manual-path suite — its other three compare
against the frozen fixture and do go red); interpreter pre-sanitizes the name → exactly 1;
`SewUp.steps` 3.0 → 3.25 → 26, including the ADR-019 conversion-boundary screening once
that screening was rewritten to measure the engine's own stage values instead of the
hand-written literals, which sit on whole units by construction and left it green. Seeding the first record at the origin
instead of `previous ?? stitch.position` **traps** rather than failing (the delta
exceeds ±121), so it is detected but is not a usable mutant.

Not claimed, in the precise form: `javaRound` → `.rounded()` is killed by **no US-209
test** — no stage value in this design is a negative half, so the two rules agree at
every point here, and US-105/US-106 own that edge. It does **not** survive the package:
measured, it takes 15 issues across 8 test functions, `CoordinateConversionTests`
included (`StagePoint(x: -0.25, y: 0.25)` expects `(0, 1)` and becomes `(-1, 1)`).
Earlier drafts of this line and of the journal entry said "survives the whole suite",
which is false at package scope — Codex US-209 caught the overreach.

**A claim I wrote and mutation testing disproved.** I asserted the displaced square
uniquely killed `abs(box.min.x)` in place of `abs(min(box.min.x - first.x, 0))`. With
that test skipped the mutant still takes `DSTHeaderTests.nonOriginFirstStitch` and a
round-trip test red — its synthetic stream has first stitch (20, 10) over a box starting
at (0, 0), so the mutant reads 0 where 20 is correct. The comment now claims only the
route, not the kill. Same defect class US-207 and US-208 each surfaced; caught here
because the mutation was run before the claim was committed.

**A gap I reported and then disproved**: I claimed no test pins a *negative* `AX`/`AY`,
so `AX = abs(last.x - first.x)` — the mirror of the Catty signed-extent bug ADR-012 says
not to port — would survive the package. It does not. `DSTRoundTripTests`'
"jumps, a color change, and a non-origin start survive a round trip" kills it, because
`expectMatches` compares `last.x - first.x` literally and its stream ends left of its
start. Measured, both axes independently. There is no gap and nothing to fold into a
later story. (Found by `swift-code-reviewer`; the claim originated in a planning agent's
finding that I recorded without running its mutation — see the journal correction.)

**Manual viewer verification: done and passed** (2026-07-31) — the first externally
validated design in this repo that actually sews anything, and the first with a non-zero
*negative* extent. Full record in the fixture's `PROVENANCE.md`.

The one finding was a false alarm worth keeping, because it is the shape of the next
one: a stroke hanging below the square's start corner looked like a stray stitch and is
the `sewUp` bar tack. The tack is laid along the **closing heading** (0° after four
`turnRight(90)`s, i.e. +y), so its `ahead` leg runs up along the square's own left edge
and is invisible while its `behind` leg runs down outside the design — only one leg of a
tack at this corner can ever be seen. The viewer's own `4.00 × 4.60 mm` settles it
arithmetically: 4.60 mm is 46 units, the square's 40 plus exactly the 6 the tack hangs
below, which is the `-Y 6` the decode read from the header. A tack in the wrong place or
of the wrong length could not produce that number. Also recorded: the predicted risk
that a viewer might collapse the zero-delta 18th record did **not** occur — it counted
all 22.
