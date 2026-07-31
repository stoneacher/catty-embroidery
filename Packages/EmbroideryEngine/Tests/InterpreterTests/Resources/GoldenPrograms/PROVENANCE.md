# Golden program fixtures — provenance

Unlike `EmbroideryEngineTests/Resources/EmbroideryReference/`, whose fixtures are
byte-exact copies from Catrobat **Catty**, the files here are **our own engine's
output**: an interpreted program serialized by `DSTFile`. That makes them
*self-golden*, so per ADR-012 in `docs/DECISIONS.md` they are trusted only after
one-time external verification — recorded below. Without that section filled in,
a file here proves only that the output has not changed, not that it is correct.

## `square.dst` (US-209)

Generated from US-207's golden square program — the same `GoldenSquare.program`
the tests run, so the fixture is reproducible from the repository alone:

| | |
|---|---|
| Program | `whenStarted` → `setThreadColor(#00ff00)` → `runningStitch(length: 5)` → `repeatLoop(4)[moveNSteps(20), turnRight(90)]` → `sewUp` → `writeEmbroideryToFile("square")` |
| Design name | `square` (from the program's own brick, not restated by the test) |
| Geometry | 20 × 20 stage units = 4 × 4 mm, stitch interval 1 mm, ±0.6 mm bar tack |
| Records | 22 stitches, no jumps, no colour changes → `ST = 22`, `CO = 1` |
| Size | 581 bytes (512-byte header + 22 × 3 + 3-byte end-of-file record) |

**Regeneration**: build `DSTFile(stream: <interpreter run to completion>.assembledStream(), name: "square")`
and write `.data`. `GoldenSquareBytesTests.interpreterBytesEqualTheCommittedGolden`
is the check that the committed bytes still match; if it goes red, decide whether
the *change* is correct before regenerating — regenerating is how a golden test
gets silently defeated.

SHA-256:

```
4a76c57d586ae715877dbf1dc6bc6d3e8b7d721c22dc89232ec9f577ec2674ff  square.dst
```

## Trust verification (US-209)

**Status: verified — this fixture is trusted** (2026-07-30). Both halves passed: an
independent byte-level decode and an embroidery-viewer check, which agree with each
other and with the golden's literals.

- **Independent byte-level decode — pass** (2026-07-30). Decoded with the
  repository's own `DSTFileReader` / `DSTRecordDecoder`
  (`Tests/EmbroideryEngineTests/`), which read straight off the DST bit chart with
  hard-coded layout constants precisely so they share no definitions with the
  writer that produced this file. Results: 581 bytes; 22 records; 0 jumps; 0
  colour changes; accumulated positions exactly the 22 hand-derived records of
  `goldenSquareRecords`; header `LA square`, `ST 22`, `CO 1`, `+X 40`, `-X 0`,
  `+Y 40`, `-Y 6`, `AX 0`, `AY 0`, `MX 0`, `MY 0`, `PD *****`.
- **Embroidery viewer — pass** (Sebastian, 2026-07-30). Loads without error and
  renders a closed square walked from the bottom-left corner upwards
  (heading 0 = +y, `turnRight` ⇒ clockwise: up, right, down, left). Reported
  **design dimensions 4.00 × 4.60 mm, 22 stitches, 0 colour changes, 0 jumps,
  0 trims, 0 stops** — one colour block, and every figure agreeing with the decode
  above.

  **The one thing that looks wrong and is not**: a short stroke hangs *downwards*
  below the square's start corner. That is the `sewUp` bar tack, and it is the
  expected shape rather than an artefact. The tack is Catroid's five-point tie-off
  — centre / ahead / centre / behind / centre — laid along the **closing heading**,
  which after four `turnRight(90)`s is 0° again, i.e. +y. So its `ahead` leg runs
  6 units straight up *along the square's own left edge* and is invisible, while
  its `behind` leg runs 6 units down, outside the design. Only one leg of a tack at
  this corner can ever be visible, and it is the downward one. ADR-012 pins the
  five-point sew-up (over Catty's four-point) as authoritative.

  The viewer's own dimensions are the arithmetic proof: 4.00 mm is the 40-unit
  square (`+X 40`, `-X 0`), and 4.60 mm is 46 units — the square's 40 plus exactly
  the 6 the tack hangs below (`+Y 40`, `-Y 6`). A tack drawn anywhere else, or with
  the wrong leg length, could not produce 4.60.

  Also noted, because it was predicted and did not happen: the viewer did **not**
  collapse the zero-delta 18th record (the tack's leading centre, present only
  because of the trig dust `tackCentreIsNotTheLastPathPoint` documents). It counted
  all 22. The prediction was a precaution, not a known behaviour.

  Unlike the Catty fixtures in
  `../../../EmbroideryEngineTests/Resources/EmbroideryReference/PROVENANCE.md`,
  which correctly render as an empty canvas, this one contains genuinely **sewn**
  segments — so "renders nothing" would here have been a real finding.

Note what this design does *not* exercise, so a later story does not assume it
does: ADR-013 colour-change flag placement (single colour), long-move
interpolation (every gap is 10 units against a 121-unit threshold), and
`javaRound`'s negative-half asymmetry (no stage value here is a negative half).
