# US-312 — Thread colours do not survive export, and nothing tells the user

**Epic**: E7 Export & sharing | **Estimate**: ~3 h | **Depends on**: US-405
**Discovered**: 2026-08-29, US-308 manual Ink/Stitch verification. **Scheduled into M4**: 2026-09-19.

**Story**: As a user, I want to know before I open my file somewhere else that the machine, not my design, picks the thread colours — so a correct export does not look broken.

## Problem

The app shows the design in the thread colours the program set, and the exported `.dst` cannot carry them. **Tajima DST stores no colour at all** — only stitch coordinates and colour-*change* commands — so every viewer and every machine assigns its own palette per block. Verified two ways rather than assumed: this repo's writer emits no RGB anywhere (`DSTFile`/`DSTHeader`/`DSTStitchRecord` contain no colour bytes), and Catroid's reference writer likewise tracks only `colorChangeCount`.

Measured on the first file exported through the app path (`squareCoil`, named "SquareCoilexp"): the design sets `#1d4ed8` for the inner half and `#f59e0b` for the outer; Ink/Stitch drew the inner half **pink** and the outer **green**. The *structure* round-tripped exactly — `CO:2`, one colour change at record 1489 of 2976 (50.0 %), extents 53.40 × 52.80 mm matching the app's own summary to the millimetre — so this is a **fidelity-of-expectation** problem, not a byte problem.

**Not a defect in US-308**: ADR-012 pins the byte semantics, ADR-015 pins when a colour change is emitted, and both are met. ADR-026 records the finding.

## Scope — deliberately the cheap option, and why

The backlog entry listed three options. This story takes the first and **explicitly defers the second**:

1. ✅ **Say so in the app.** A line near the share control stating that thread colours are chosen on the machine. Cheapest, and honest.
2. ⏭ **A companion colour sidecar file.** Deferred to M5. The entry's own placement note said this option is "better decided once M5's file handling exists to decide it against", and that is still right: it interacts with the exported UTType (ADR-026), with sharing two files instead of one, and with whatever M5 decides about documents on disk. **This story owes the research, not the build** — which formats Ink/Stitch and common machines actually read — written into the story's close-out so M5 inherits an answer rather than a question.
3. ❌ **Write a format that carries colour.** Out of scope for the DST-only promise (ROADMAP E7) and a much larger change.

Sebastian took this into M4 on 2026-09-19 against the entry's "M4 or M5" note. Recorded as a deliberate override: the honest-statement half needs nothing from M5, and it is the half the user actually meets.

## Why it is here rather than anywhere in M4

M4 is the first milestone where the colours are the **user's own choice** rather than a sample author's. A user who picks `#1d4ed8` in US-410's thread palette has a much stronger expectation that the file carries it than a user who ran a bundled design. The problem gets worse exactly as the editor gets better, so it belongs in the milestone that makes it worse.

It sits after US-405 so the export surface is touched once, after the selection type has settled, rather than being rewritten by that refactor.

## Acceptance criteria

- [ ] The export area states that thread colours are not stored in the file and are chosen by the machine or viewer. **Localised** with a translator comment, per the M3+ definition of done — this is a sentence about a file format and is exactly the kind of string a translator needs context for.
- [ ] It is visible **before** the share sheet, not inside it. The user should learn this while deciding to export, not while exporting. A `ShareLink` also cannot be relied on to present our copy.
- [ ] It does **not** read as an error or a warning. The export is correct; the sentence is information. This is a visual-design criterion and is checked on the screenshot, not in a test.
- [ ] It is part of the export row's single accessibility element or an adjacent one — not a floating string a VoiceOver user meets out of context.
- [ ] Nothing about the emitted bytes changes. Asserted: the DST goldens are untouched and byte-identical.
- [ ] **Story-specific definition of done**: a screenshot of the export area at default and at AX1, where the added sentence is the most likely thing to overflow.
- [ ] Close-out records the **sidecar research** for M5: which sidecar formats Ink/Stitch reads, whether common consumer machines read any, and what it would cost against ADR-026's UTType and single-file share.

## Test-first plan

1. The export row's copy includes the colour statement, from the String Catalog, not a literal.
2. The statement is present regardless of whether the design has one colour or several — a single-colour design still gets machine-assigned colour, so suppressing it there would be wrong.
3. The export row's accessibility label contains the statement.
4. The DST goldens are unchanged — the assertion that this story is UI-only.

No manual Ink/Stitch verification is needed for the *change*; the Ink/Stitch observation is what produced the story and is already recorded.

## References

- ADR-026 (the export gate, the UTType, and where this finding is already recorded), ADR-015 (thread-colour emission semantics), ADR-012 (byte semantics — met, not violated)
- ROADMAP E7 — the DST-only promise that rules out option 3
- `docs/user-stories/backlog.md` — the original entry and its three options
