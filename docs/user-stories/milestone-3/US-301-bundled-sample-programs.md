# US-301 — Bundled sample programs as a package product

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~4 h | **Depends on**: —

**Status**: Done — 2026-08-09. Implemented 2026-08-07; closed out after the
manual Ink/Stitch verification the milestone requires at this story (Sebastian,
2026-08-09 — both samples trusted, see `PROVENANCE.md`).

**Story**: As the app, I want ready-made, visually appealing embroidery programs available as a linkable product, so that M3 can run something real and M5 can turn the same content into projects on disk.

There is no sample builder anywhere in a library target today — `polygonProgram` and friends live only in `Tests/InterpreterTests/`, and SwiftPM forbids a test target depending on another test target. Catroid has no bundled sample *files* either: it generates one starter project imperatively at first launch. So this story is new content, not a port, and it comes first because US-302's tests need a real program to run (see the milestone README's buildability note).

Per ADR-022, samples live in a new `Samples` target depending on `ProgramModel` only. Swift builders are the single source of truth; a checked-in JSON encoding ships alongside as a resource, guarded by a round-trip test. M3 loads the builders (no decode, no error path); M5 copies the JSON into Documents to create real projects, so ADR-003's JSON format is inherited rather than redone.

## Acceptance criteria
- [x] New `Samples` target and library product in `Package.swift`, depending on `ProgramModel` **only** — no `EmbroideryEngine`, no `Interpreter`. The ADR-016 DAG stays a straight line inward.
- [x] `SampleLibrary.all: [SampleProgram]`, each carrying a stable `id`, a String Catalog key for its display name and description, and a `program: Program` builder.
- [x] **Sample 1 reproduces Catroid's `DefaultExampleProject` verbatim**: `setVariable("Inner Loop", 8)`, `setVariable("Outer Loop", 8)`, `zigZagStitch(length: 2, width: 10)`, then nested `repeatLoop`s over those variables with `moveNSteps(100)` + `turnRight(360 / "Inner Loop")` inside and `turnRight(360 / "Outer Loop")` outside — eight rotated octagons. Verbatim because it makes our stitch output cross-platform comparable against the shipping Android app, a validation channel we otherwise lack.
- [x] **Sample 2 exercises `tripleStitch` and a mid-program `setThreadColor`**, ends with `sewUp`, and produces `CO == 2`.
- [x] Every sample: `Script.validate()` passes (ADR-008 paired-control invariant), the interpreter finishes inside a bounded tick budget, and the design's bounding box fits inside ADR-007's 500×500 stage.
- [x] Every sample takes **≥ ~120 ticks**, so it animates for ≥ 2 s at one tick per frame. A sample that finishes in 39 ticks (0.65 s) is not a preview, it is a flash.
- [x] Each sample's per-tick stitch maximum is recorded in the test output — this is the number US-306's stitch budget is sized against.
- [x] Each sample's `Program` round-trips through `JSONEncoder`/`JSONDecoder` unchanged, and the checked-in JSON resource decodes equal to its builder, so a `formatVersion` bump fails a test instead of rotting a resource.
- [x] **ADR-019 screening applied to both samples.** Sample 1 walks 100-step sides at zigzag length 2 — an exact integer ratio, i.e. sitting *on* a `floor(distance / length)` threshold. Compute the along-motion ulp distance; if either sample lands inside half an ulp, add a tripwire test naming the dependency, exactly as US-208's star did. Do not assume safety because the numbers look round — that assumption is what ADR-019 exists to stop.
- [x] `PROVENANCE.md` beside the resources records sample 1's Catroid origin (AGPL-3.0 attribution) and the exact source file it was transcribed from.

## Test-first plan
1. `Script.validate()` succeeds for every sample.
2. Sample 1 golden run: tick count, stitch-event count, `CO == 1`, bounding box in millimetres, and DST byte length. Expected from a planning-session measurement — **139 ticks, 3194 stitches, 98.6 × 98.6 mm, 10 097 bytes** — but re-derive these rather than trusting them; they are a sanity target, not an oracle. The mm figure doubles as a check that ADR-007's stage really is a ~100 mm hoop.
3. Sample 2: `CO == 2`, and the assembled stream contains at least one triple-stitch triplet.
4. Every sample's bounding box is within ±250 stage points on both axes.
5. Every sample's tick count ≥ 120; per-tick stitch maximum recorded.
6. JSON round-trip equality per sample, and `decode(Bundle.module resource) == builder()`.
7. Every sample builds a `DSTFile` without trapping — a cheap early canary for US-211.
8. ADR-019 ulp-distance screening for both samples, with a tripwire test if either is inside half an ulp.

## References
- `Catroid/catroid/src/embroideryDesigner/java/org/catrobat/catroid/common/defaultprojectcreators/DefaultExampleProject.java` — sample 1's source
- ADR-003 (JSON project format), ADR-007 (stage bounds), ADR-008 (paired control), ADR-016 (target DAG), ADR-019 (threshold screening), ADR-022 (this milestone's target layout)
- `docs/user-stories/milestone-2/US-208-golden-program-star.md` — the tripwire pattern to copy if screening fails
- ROADMAP M5 ("bundled sample designs") — what this story's JSON resources feed

## Outcome

`Samples` is the package's fourth library product. 403 tests in 51 suites green,
40 of them new, across three cross-vendor review rounds. All four of the planning session's sample-1 figures re-derived
exactly — 139 ticks, 3194 stitch events, 98.57 × 98.57 mm, 10 097 bytes — which
is the first time an M3 planning measurement has been confirmed by
implementation rather than adjusted by it.

**Sample 2 is a square coil, not a rosette.** 44 sides in triple stitch, two
colours, 137 ticks, 2976 records, peak 132 stitches per tick, `CO 2`, 9443 bytes.
Chosen over a second circular design on two grounds: a picker showing two dense
rosettes teaches a first-time user nothing, and the coil is the only bundled
content that drives motion from a *variable*, so `changeVariableBy` and a
variable-valued `moveNSteps` are exercised somewhere. Its three geometry
constants are picked together so every side is congruent to 3 modulo the stitch
length — exactly halfway between `floor` boundaries, measured at 5.2 × 10¹³ ulps
of margin.

Three findings worth carrying forward:

- **The ADR-019 screening was not a formality, and its answer has a third term.**
  Sample 1's boundary-free count is 3201; it emits 3194, reconciling as
  `1 anchor + 54 × 50 + 10 × 49 + 3 × 1`. Ten sides come up an interval short,
  seven of them decided by libm's rounding of `hypot` rather than by geometry.
  The `3 × 1` is not predicted anywhere in ADR-019: **a `turnRight` brick can
  emit a stitch.** A turn moves the needle zero distance but still reaches the
  pattern, and when a short side has left the anchor exactly one stitch length
  behind, that zero-distance update emits a catch-up point — which is why a lost
  interval shifts the anchor instead of accumulating into a deformed shape.
  Pinned by `theRosetteDependsOnLibmRoundingOfHypot`.
- **The AC's justification for verbatim reproduction is over-stated and is now
  scoped in `PROVENANCE.md`.** Catroid computes `(float) Math.hypot(...)`
  (`RunningStitchType.java:35-37`) and carries every coordinate as `float`, so
  the ~1e-14 residue costing us ten intervals is nine orders of magnitude below
  its resolution. This is ADR-014's existing "no bit-exact Android parity"
  becoming *structurally* visible instead of sub-resolution: same program, same
  semantics, same design, but Android is **not a byte-identical oracle** for it.
  Equality cannot be promised, so a mismatch is not evidence of a bug on either
  side — which is weaker than "byte comparison is impossible", a claim that does
  not follow and that two drafts made anyway (Codex rounds 1–2). Verbatim
  transcription is still right, for the design-level comparison and the
  provenance.
- **SwiftPM does not compile String Catalogs.** An `.xcstrings` in a package
  target is copied into the resource bundle verbatim — `xcstringstool` is never
  invoked — so every lookup falls back to the key under `swift test`. Measured on
  Swift 6.3.3 with a throwaway package, both via `String(localized:bundle:)` and
  `LocalizedStringResource`. The samples ship `en.lproj/Localizable.strings`
  instead, which resolves correctly and keeps the strings testable inside the
  package. US-303 should not assume the app-target catalog behaves the same way
  the package's resources do.

**Manual Ink/Stitch verification: done, both samples trusted** (Sebastian,
2026-08-09). Shapes correct — the rosette's eight octagons fan around one shared
corner, the coil's amber is the outer third. Dimensions matched exactly
(98.6 × 98.6 mm and 53.4 × 52.8 mm).

The viewer's stitch counts came back 3195 and 2978 against our 3194 and 2976, and
it reported one jump in the coil where our tests assert none. **Both are its
counting convention, confirmed by decoding the bytes rather than by argument**:
it counts the 3-byte end-of-file terminator as a stitch, and it expands the
single `0xC3` colour-change record into two commands while also reporting its
`0x80` bit as a jump. Neither file contains a jump-only record, and both `ST:`
header fields read exactly our numbers. Full reconciliation in `PROVENANCE.md`.
