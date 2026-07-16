# US-209 — Pattern→stream→bytes differential test

**Epic**: E3 Program model & interpreter | **Estimate**: ~3 h | **Depends on**: US-207

**Status**: Planned

**Story**: As a maintainer, I want an interpreted program piped through `EmbroideryStream` → `DSTFile` to bytes and diffed against a golden `.dst`, closing the test blind spot carried in the workflow journal since US-108: no test yet covers the full pattern-output-to-real-bytes path.

## Acceptance criteria
- [ ] The square program's (US-207) `assembledStream()` feeds `DSTFile(stream:name:)`; the emitted bytes are byte-diffed against a committed golden fixture. `ByteDiff` is internal to the `EmbroideryEngineTests` target and SPM test resources are declared per target, so this story does the plumbing explicitly: either a small shared test-support target or a deliberate copy of the helper into `InterpreterTests`, plus the golden fixture declared as a `Bundle.module` resource of the test target running this test (a `Package.swift` change inside this story).
- [ ] The golden fixture is **verified in an embroidery viewer before being trusted** (ADR-012 discipline: a golden derived from our own output must be externally validated once). Manual Ink/Stitch check happens in this story.
- [ ] Header assertions: stitch count and `CO = colorChangeCount + 1` match the program's actual stitch and color-stop counts (US-104 semantics).
- [ ] Differential assertion: interpreter-assembled bytes equal the bytes of a hand-built `EmbroideryStream` encoding the same geometry — the interpreter path and the manual path converge.

## Test-first plan
1. Square program → `DSTFile.data` equals the golden `.dst` fixture (loaded via `Bundle.module` from this test target's own resources), byte-for-byte via the shared/copied `ByteDiff` helper.
2. Header stitch-count and CO fields match computed expectations.
3. Interpreter-path bytes == manual-stream-path bytes for identical geometry.

**Manual verification (flag for Sebastian)**: before committing the golden fixture, open the freshly generated square `.dst` in Ink/Stitch and check it loads, renders a closed square with a tie-off, and reports the expected stitch count and one color block. The fixture is trusted only after this check; note the result in the story close-out.

## References
- `docs/workflow-journal.md` 2026-07-13 / 2026-07-14 / 2026-07-16 (carry-forward: pattern→stream→bytes blind spot)
- M1 `ByteDiff` test helper; US-104 header semantics; ADR-012 in `docs/DECISIONS.md`
