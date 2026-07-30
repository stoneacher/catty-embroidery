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

**Status: one half done, one half outstanding.** The numeric check has passed; the
embroidery-viewer check has not been run yet, so this fixture is a *regression*
anchor only — it pins that the bytes have not changed, not yet that they are
right. Do not cite it as externally validated until the viewer line below is
filled in.

- **Independent byte-level decode — pass** (2026-07-30). Decoded with the
  repository's own `DSTFileReader` / `DSTRecordDecoder`
  (`Tests/EmbroideryEngineTests/`), which read straight off the DST bit chart with
  hard-coded layout constants precisely so they share no definitions with the
  writer that produced this file. Results: 581 bytes; 22 records; 0 jumps; 0
  colour changes; accumulated positions exactly the 22 hand-derived records of
  `goldenSquareRecords`; header `LA square`, `ST 22`, `CO 1`, `+X 40`, `-X 0`,
  `+Y 40`, `-Y 6`, `AX 0`, `AY 0`, `MX 0`, `MY 0`, `PD *****`.
- **Embroidery viewer (Ink/Stitch) — OUTSTANDING.** What to check: the file loads
  without error; it renders a **closed square** with the tie-off spur at the start
  corner (zoom hard — the design is 4 × 4 mm, 1 mm stitches, ±0.6 mm tack legs);
  and it reports 22 stitches and one colour block.

  Two observations to expect and *not* read as defects: a viewer may collapse or
  drop the zero-delta 18th record (the tack's leading centre — a real stitch the
  machine will sew, present only because of the trig dust
  `tackCentreIsNotTheLastPathPoint` documents), and short-stitch/density warnings
  on the sub-millimetre tack legs are normal. The authoritative counts are the
  decode above, not the viewer's stitch-plan summary — the US-101 precedent in
  `../../../EmbroideryEngineTests/Resources/EmbroideryReference/PROVENANCE.md` is
  a viewer legitimately rendering a correct file as nothing.

  Unlike those Catty fixtures, this one contains genuinely **sewn** segments, so
  "renders empty" would here be a real finding, not the expected outcome.

Note what this design does *not* exercise, so a later story does not assume it
does: ADR-013 colour-change flag placement (single colour), long-move
interpolation (every gap is 10 units against a 121-unit threshold), and
`javaRound`'s negative-half asymmetry (no stage value here is a negative half).
