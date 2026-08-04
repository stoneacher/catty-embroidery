# US-301 — Bundled sample programs as a package product

**Epic**: E6 Projects & persistence (thin) | **Estimate**: ~4 h | **Depends on**: —

**Status**: Not started

**Story**: As the app, I want ready-made, visually appealing embroidery programs available as a linkable product, so that M3 can run something real and M5 can turn the same content into projects on disk.

There is no sample builder anywhere in a library target today — `polygonProgram` and friends live only in `Tests/InterpreterTests/`, and SwiftPM forbids a test target depending on another test target. Catroid has no bundled sample *files* either: it generates one starter project imperatively at first launch. So this story is new content, not a port, and it comes first because US-302's tests need a real program to run (see the milestone README's buildability note).

Per ADR-022, samples live in a new `Samples` target depending on `ProgramModel` only. Swift builders are the single source of truth; a checked-in JSON encoding ships alongside as a resource, guarded by a round-trip test. M3 loads the builders (no decode, no error path); M5 copies the JSON into Documents to create real projects, so ADR-003's JSON format is inherited rather than redone.

## Acceptance criteria
- [ ] New `Samples` target and library product in `Package.swift`, depending on `ProgramModel` **only** — no `EmbroideryEngine`, no `Interpreter`. The ADR-016 DAG stays a straight line inward.
- [ ] `SampleLibrary.all: [SampleProgram]`, each carrying a stable `id`, a String Catalog key for its display name and description, and a `program: Program` builder.
- [ ] **Sample 1 reproduces Catroid's `DefaultExampleProject` verbatim**: `setVariable("Inner Loop", 8)`, `setVariable("Outer Loop", 8)`, `zigZagStitch(length: 2, width: 10)`, then nested `repeatLoop`s over those variables with `moveNSteps(100)` + `turnRight(360 / "Inner Loop")` inside and `turnRight(360 / "Outer Loop")` outside — eight rotated octagons. Verbatim because it makes our stitch output cross-platform comparable against the shipping Android app, a validation channel we otherwise lack.
- [ ] **Sample 2 exercises `tripleStitch` and a mid-program `setThreadColor`**, ends with `sewUp`, and produces `CO == 2`.
- [ ] Every sample: `Script.validate()` passes (ADR-008 paired-control invariant), the interpreter finishes inside a bounded tick budget, and the design's bounding box fits inside ADR-007's 500×500 stage.
- [ ] Every sample takes **≥ ~120 ticks**, so it animates for ≥ 2 s at one tick per frame. A sample that finishes in 39 ticks (0.65 s) is not a preview, it is a flash.
- [ ] Each sample's per-tick stitch maximum is recorded in the test output — this is the number US-306's stitch budget is sized against.
- [ ] Each sample's `Program` round-trips through `JSONEncoder`/`JSONDecoder` unchanged, and the checked-in JSON resource decodes equal to its builder, so a `formatVersion` bump fails a test instead of rotting a resource.
- [ ] **ADR-019 screening applied to both samples.** Sample 1 walks 100-step sides at zigzag length 2 — an exact integer ratio, i.e. sitting *on* a `floor(distance / length)` threshold. Compute the along-motion ulp distance; if either sample lands inside half an ulp, add a tripwire test naming the dependency, exactly as US-208's star did. Do not assume safety because the numbers look round — that assumption is what ADR-019 exists to stop.
- [ ] `PROVENANCE.md` beside the resources records sample 1's Catroid origin (AGPL-3.0 attribution) and the exact source file it was transcribed from.

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
