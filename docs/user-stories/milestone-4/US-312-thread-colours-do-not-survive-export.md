# US-312 — Thread colours do not survive export, and nothing tells the user

**Epic**: E7 Export & sharing | **Estimate**: ~3 h | **Depends on**: US-405
**Discovered**: 2026-08-29, US-308 manual Ink/Stitch verification. **Scheduled into M4**: 2026-09-19.

**Status**: In review — 2026-09-27. Implemented test-first; all seven acceptance criteria met (see the close-out below for the AX1 cap and the evidence behind the VoiceOver criterion).

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

- [x] The export area states that thread colours are not stored in the file and are chosen by the machine or viewer. **Localised** with a translator comment, per the M3+ definition of done — this is a sentence about a file format and is exactly the kind of string a translator needs context for.
- [x] It is visible **before** the share sheet, not inside it. The user should learn this while deciding to export, not while exporting. A `ShareLink` also cannot be relied on to present our copy.
- [x] It does **not** read as an error or a warning. The export is correct; the sentence is information. This is a visual-design criterion and is checked on the screenshot, not in a test.
- [x] It is part of the export row's single accessibility element or an adjacent one — not a floating string a VoiceOver user meets out of context.
- [x] Nothing about the emitted bytes changes. Asserted: the DST goldens are untouched and byte-identical.
- [x] **Story-specific definition of done**: a screenshot of the export area at default and at AX1, where the added sentence is the most likely thing to overflow.
- [x] Close-out records the **sidecar research** for M5: which sidecar formats Ink/Stitch reads, whether common consumer machines read any, and what it would cost against ADR-026's UTType and single-file share.

## Test-first plan

1. The export row's copy includes the colour statement, from the String Catalog, not a literal.
2. The statement is present regardless of whether the design has one colour or several — a single-colour design still gets machine-assigned colour, so suppressing it there would be wrong.
3. The statement is reachable by VoiceOver **in whichever arrangement the criteria adopt** — contained in the export row's combined label, *or* exposed as the adjacent element the criteria expressly permit. Written against the chosen arrangement, because an unconditional "the label contains it" would fail a layout the acceptance criteria allow, and `StageExportRow` derives its label from its button title rather than absorbing a neighbour.
4. The DST goldens are unchanged — the assertion that this story is UI-only.

No manual Ink/Stitch verification is needed for the *change*; the Ink/Stitch observation is what produced the story and is already recorded.

## References

- ADR-026 (the export gate, the UTType, and where this finding is already recorded), ADR-015 (thread-colour emission semantics), ADR-012 (byte semantics — met, not violated)
- ROADMAP E7 — the DST-only promise that rules out option 3
- `docs/user-stories/backlog.md` — the original entry and its three options

## Close-out (2026-09-27)

**What shipped.**
- A caption under **Share DST File**, "DST files don't store thread colours. The machine or viewer chooses them." The copy was chosen by Sebastian.
- It comes from `ExportControl.Readiness.threadColorNote`, catalog key `stage.export.thread.colors`, which has a translator comment.
- It shows in every state the row renders, and is `nil` only for `.noSelection`, which is never rendered.
- Plain `.caption` in `.secondary`, with no glyph, outside `.disabled`.
- Placement came from a `swift-ui-design` pass (adjacent, not combined) and was agreed with `swift-architect`. The amendment is recorded in ADR-026.

**Evidence per criterion.**
- **Localised, from the catalog, pinned.** `ExportControlTests.theThreadColorNoteComesFromTheCatalog` pins the English value. The reviewer's opposite-claim mutant survived until that pin existed.
- **Before the share sheet.** It sits in the row, under the button.
- **Not a warning.** Checked on the screenshots.
- **Adjacent accessibility element.** Two runtime snapshots of the stage's accessibility tree (XcodeBuildMCP `snapshot-ui --output json`, iPhone 17e) read **Share DST File → caption → Play Again** after a finished run and **Share DST File → caption → Play** in the disabled not-run state. These snapshots are also the only thing that catches the two view-level mutants the reviewer found unit-untestable: caption dropped, and caption shown only when enabled.
- **Bytes unchanged.** `git diff main -- Packages/` is empty, and all 981 engine tests pass, including the byte-for-byte goldens.
- **One colour or several.** `ExportWiringTests.aReadyExportCarriesTheNoteWhateverTheColorCount` runs Octagon Rosette (1 colour) and Square Coil (2 colours). It pins colour-independence at the `Readiness` level only; a gate added in the view is caught only by the snapshots.
- **Screenshots** on the iPhone 17e, the smallest available simulator, in `docs/screenshots/us-312/`:
  - `default.png` and `ax1.png`, the story's bar;
  - `disabled.png`, where the caption is not dimmed with the button.

**AX5, measured.**
- **The caption is capped at AX1** (Sebastian's decision).
- Uncapped, at AX5 the Share label spilled out of its own background (`ax5-uncapped.png`).
- The cause predates this story: `main` at AX5 already loses the design-name field (`ax5-main-before.png`).
- With the cap the button is intact, and the name counter is half hidden (`ax5-capped.png`).
- The squeeze is **backlog US-319**. That entry also records a pre-existing "Ready to St…" title truncated at default size on this device.

### Sidecar research for M5

Verified in the pyembroidery (`c16d1b4`), Ink/Stitch (`d59c9ab`) and pystitch (`b72b557`) sources unless marked otherwise.

- **pyembroidery's extended DST header** writes these lines into the 512-byte header when opted in with `settings={"version": "extended"}`, after `PD:`:
  - `AU:`, `CP:`;
  - one `TC:#rrggbb,<description>,<catalog>` line per thread.

  Its reader parses them back. **There is no overflow guard**: past 512 bytes the stitch records start at the wrong offset. The budget after the fixed fields is 387 bytes, which is about 18 threads as `TC:#rrggbb,None,None` (an empty field is written as the literal `None`), or about 29 with truly empty fields. No other producer is known; the EduTech wiki calls the tags "exceptionally rare" (secondary source). Machine tolerance of unknown header lines is **unverified**.
- **Ink/Stitch** imports through pystitch (a pyembroidery fork with the same DST reader), so **`TC:` colours reach the SVG** with no user action. Without them it uses random filler threads. It does **not** apply a sibling file automatically: its *Apply Threadlist* extension accepts **`.txt`, `.edr`, `.col`, `.inf`**, applied in colour-change order. Its `.txt` is its own threadlist format: lines containing `(#rrggbb)`.
- **Sidecar formats in pyembroidery**:
  - `.edr`, read/write: raw RGB0, 4 bytes per colour;
  - `.col`, read/write: a count line, then `index,r,g,b` lines;
  - `.inf`, read/write: binary, with RGB, needle, description and chart;
  - `.rgb` and `.thr`: not supported;
  - `.txt`: a debug dump, not a threadlist.
- **Home machines read no colour from DST.** Brother says so officially (primary source). Janome, Viking/Pfaff and Singer are the same per secondary sources. Colour on those machines comes only from native formats: PES, JEF, VP3, XXX, and Bernina's EXP+INF. The one real sidecar convention is Bernina's `.inf`, and it goes with EXP, not DST.
- **Sharing two files**: `ShareLink(items:)` and `UIActivityViewController` accept several. Apple guarantees nothing about AirDrop or Files keeping them together, which is unverified and needs a device test. A ZIP is the only guaranteed bundle.

**What M5 inherits.**
- **First candidate: a `.col`/`.edr` sidecar or an Ink/Stitch `.txt` threadlist.** It is trivial to write, read by the one consumer verified to use colour, and leaves the DST bytes (ADR-012/025, the goldens) untouched. It costs a second UTType or a ZIP, which interacts with ADR-026's single-file share.
- **Second, gated: the `TC:` header.** It needs an ADR, an explicit 512-byte overflow rule (pyembroidery has none), and a hardware tolerance test.
- **Colour on home machines means a native format**, which is out of scope for the DST-only promise (ROADMAP E7).

