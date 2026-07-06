# US-103 — DST stitch record encoder

**Epic**: E2 Engine | **Estimate**: ~5 h | **Depends on**: US-102

**Story**: As the DST writer, I need each stitch encoded as a 3-byte Tajima DST record from relative coordinates, so that embroidery machines can read our output.

## Acceptance criteria
- [ ] Encoder converts a delta (dx, dy in embroidery units, each within ±121 **inclusive** — Catty's strict-comparison guard that rejects legal ±121 is a bug, do not port; ADR-012) into the 3-byte DST record. Port Catroid's 243-entry `CONVERSION_TABLE` **verbatim as data** (AGPL-compatible, provenance comment) rather than hand-deriving the encoder from the bit diagram; the algorithmic derivation exists only as a test that regenerates the table.
- [ ] Relative deltas are computed **between individually converted absolute positions** (round-then-subtract), never by converting the difference (ADR-012).
- [ ] Byte 3 flags: jump stitch sets `0x80`; color change sets `0xC0`; plain stitch sets the base bits per spec.
- [ ] Deltas outside ±121 are rejected at this layer via `precondition` (unreachable once US-105's interpolation is a stream invariant), tested.
- [ ] Decoder for the same 3-byte records lives in the **test target only** — no product feature reads DST in M1–M6 (if E7's export validation ever means re-reading files, promote it then as its own story). Encode/decode round-trips.

## Test-first plan
1. Known-vector tests first, as a parameterized Swift Testing test — `@Test(arguments: zip(deltas, expectedBytes))` (use `zip`, not two bare collections, to avoid an accidental Cartesian product): hand-computed encodings for (0,0), (1,0), (0,1), (−1,−1), (121,0), (0,−121) verified against Catroid's `DSTStitchPointTest` expectations.
2. Jump and color-change flag tests.
3. Exhaustive round-trip in a single test body: loop dx, dy over −121...121 and `#expect(decode(encode(dx,dy)) == (dx,dy))` (a plain loop, not `@Test(arguments:)` — 243×243 parameterized cases would drown the test report).
4. Out-of-range rejection tests.

## References
- `Catroid/.../embroidery/DSTStitchPoint.java`, `DSTFileConstants.java` (CONVERSION_TABLE), `androidTest/.../embroidery/DSTStitchPointTest.java`
- `Catty/src/Catty/Embroidery/EmbroideryDSTService.swift`
- DST format: https://edutechwiki.unige.ch/en/Embroidery_format_DST
