# US-106 — DST file generator with golden-file verification

**Epic**: E2 Engine | **Estimate**: ~4 h | **Depends on**: US-103, US-104, US-105

**Status**: Done — 2026-07-09, PR #8. `stitch.dst` byte-identical; `color_change.dst` verified through the ADR-013 two-byte flag transposition (Catroid flag placement, decided during planning).

**Story**: As a user of the engine, I want a complete `EmbroideryStream → Data` DST serializer, so that a stitch stream becomes a machine-readable `.dst` file.

## Acceptance criteria
- [x] `DSTFileGenerator` (or similar) produces: 512-byte header + one 3-byte record per stitch (relative coordinates computed from the previous point) + terminator `0x00 0x00 0xF3`. *(Shipped as `DSTFile`, mirroring the `DSTHeader`/`DSTStitchRecord` value-struct idiom.)*
- [x] Output for the reference stitch sequences is **byte-identical** to BOTH Catty golden files: `stitch.dst` (interpolation case) and `color_change.dst` (the only reference bytes exercising a color change: CO:2, name "EmbroideryStitc") — fixtures copied into test resources with provenance noted, loaded via `Bundle.module`. (The fixtures themselves were viewer-verified in US-101 — they are *self-golden* Catty output, so trust was established before this story.) *(Amended by ADR-013, decided this story: `color_change.dst` is compared through a documented two-byte flag transposition because Catroid flag placement wins over Catty's; `stitch.dst` is matched byte-identically as written.)*
- [x] Golden-test failures report the **offset and hex context of the first mismatching byte** (a small test helper) — byte-diff debugging without it is where days go.
- [x] The generator's primary API returns in-memory `Data` (tests compare bytes directly, staying parallel-safe); the write-to-URL convenience is a thin wrapper, tested against a unique temp URL per test.
- [x] A minimal DST *reader* (header fields + record decoding via US-103's decoder) exists in the test target and round-trips: read(write(stream)) reproduces stitch count, extents, flags and positions.
- [x] Public API documented; this is the engine's first stable entry point.

## Test-first plan
1. Golden-file byte comparison test (written first, red until the pieces integrate).
2. Round-trip property test through the test reader.
3. Structural tests: empty stream (header + terminator only), single stitch, stream with color changes and jumps.
4. Manual sanity check (not automated): open a generated file in an embroidery viewer and record the result in the PR description.

## References
- `Catroid/.../embroidery/DSTFileGenerator.java`, `DSTFileGeneratorTest.java`, `EmbroideryFileExporterTest.java`
- `Catty/src/CattyTests/Resources/EmbroideryReference/stitch.dst`
