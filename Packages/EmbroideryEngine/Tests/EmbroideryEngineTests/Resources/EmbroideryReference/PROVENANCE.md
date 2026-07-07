# Reference fixtures — provenance

`stitch.dst` and `color_change.dst` are byte-exact copies from the Catrobat
**Catty** repository (AGPL-3.0), path `src/CattyTests/Resources/EmbroideryReference/`,
last touched there in commit `55c704a789e9d50d486e00d8191fea5711ac8155`
("CATTY-573 \"Set thread color to __\" Brick", 2023-01-21).
Source: https://github.com/Catrobat/Catty

SHA-256:

```
a26081dc8c5638f5953c7ce48aac4ef3b7e46644464cad261c0840d0799d699e  stitch.dst
bf8c153ae0ded6cac5dbbbf0320970587ead81ede675a71d32b692d1dfed1dbc  color_change.dst
```

They are Catty-generated "self-golden" files: Catty's own DST writer produced
them, so they inherit any Catty writer bugs. ADR-012 in `docs/DECISIONS.md`
pins which byte-level semantics are authoritative (Catroid wins) and lists the
known Catty bugs; golden tests in US-104/US-106 must be read against that.
## Trust verification (US-101, done 2026-07-07)

Both files contain **no sewn segments**: each is isolated anchor stitches
connected by jump records (any move > 12.1 mm is interpolated into jumps).
A correct viewer therefore renders them as an *empty* canvas — do not mistake
that for corruption when working on golden tests.

Verified with:

- **EmbroideryViewer.xyz** — parses both; canvas size matches header extents
  (500×500 units for `color_change.dst`); renders empty, as expected.
- **Ink/Stitch (Inkscape extension)** — DST import yields no drawable objects,
  correct for designs whose blocks each contain a single trimmed stitch.
- **pyembroidery 1.5.1** (the DST parser Ink/Stitch imports through) — decodes
  the full stitch plan: `stitch.dst` = stitch (0,0) → 5 jumps → stitch (500,0),
  1 color; `color_change.dst` = the same 50 mm jump line, color change,
  jump line back, then 50 mm of jumps upward, 2 colors. Bounds and color
  counts match the headers exactly.
- **Byte-level decode** against the inverse of Catroid's
  `DSTFileConstants.CONVERSION_TABLE`: every record is producible by the
  canonical encoder; the record stream matches ADR-012's pinned interpolation
  pattern (duplicate-of-previous as jump, intermediates as jumps, target as
  jump, then target as plain stitch) and all header fields (ST, CO, ±X/±Y,
  AX/AY) are consistent with the decoded records.
