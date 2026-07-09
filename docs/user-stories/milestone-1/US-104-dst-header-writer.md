# US-104 — DST header writer

**Epic**: E2 Engine | **Estimate**: ~4 h | **Depends on**: US-102

**Status**: Done — 2026-07-09, PR #6

**Story**: As the DST writer, I need the 512-byte Tajima header generated from stream metadata, so that machines and viewers accept our files.

## Acceptance criteria
- [x] Header is exactly 512 bytes, ASCII: `LA:` design name (truncated to **15** chars — Catroid rule, not Catty's 16), `ST:` stitch count, `CO:` **color-block count = color changes + 1** (both references initialize it to 1; the fixtures show CO:1 with zero changes), `+X/−X/+Y/−Y` extents, `AX/AY` = last stitch − first stitch, `MX/MY` zero, `PD:*****` (five stars).
- [x] Byte-level formatting per Catroid `DSTFileConstants.DST_HEADER`: numeric fields are left-justified and padded with **NUL 0x00** (not spaces); the `LA:` label keeps real space padding; each field terminated with `\n` + 0x1A (SUB); remainder filled with 0x20 to 512.
- [x] Extents are written **relative to the first stitch, magnitudes only** (ADR-012; equals Catroid's behavior for origin-start designs — do not port Catty's signed/start-relative variant).
- [x] Field values derive from `EmbroideryStream` metadata (count, color changes, bounding box, **first and last stitch positions** — US-102 exposes all of these); no caller-supplied redundancy.
- [x] Name sanitization: empty names, >15 chars, non-ASCII → deterministic, tested behavior.

## Test-first plan
1. Golden test first, with **concrete literal inputs** (this story does not depend on interpolation — US-105): metadata ST=8, CO=1, +X=500, −X=0, +Y=0, −Y=0, AX=500, AY=0, name "stitch" must reproduce the 512 header bytes of the fixture `stitch.dst` exactly. (The end-to-end header-from-stream check lives in US-106.)
2. Second golden: the `color_change.dst` fixture header (CO:2, name "EmbroideryStitc" — also exercises the 15-char truncation).
3. Field-level tests: NUL vs space padding, `\n`+0x1A terminators, negative extents (magnitude output), non-origin first stitch (AX/AY and extents correct — the fixtures cannot cover this).
4. Length invariant: exactly 512 bytes for all inputs.

## References
- `Catroid/.../embroidery/DSTHeader.kt`, `DSTFileConstants.java` (DST_HEADER format string), `test/.../embroidery/DSTHeaderTest.kt`
- `Catty/src/CattyTests/Resources/EmbroideryReference/stitch.dst`, `color_change.dst`
- ADR-012 in `docs/DECISIONS.md`
