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
(pending — filled in with the verified file)
```

## Trust verification (US-209)

(pending — the fixture is not trusted, and must not be relied on, until this
section records an embroidery-viewer check plus an independent decode.)
