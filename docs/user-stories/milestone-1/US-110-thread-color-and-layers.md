# US-110 — Thread color changes and layer assembly

**Epic**: E2 Engine | **Estimate**: ~3 h | **Depends on**: US-102, US-103

**Story**: As a program, I want to change thread color and have multiple stitch layers assembled in order, so that multi-color designs export with correct color-stop signals for the machine.

## Acceptance criteria
- [ ] Thread color settable on the workspace (hex string → color, default black), carried on each stitch — mirroring `Sprite.embroideryThreadColor` / `SetThreadColorAction`.
- [ ] Setting a color that **differs** from the current thread color emits a DST color-change record (deliberate divergence from Android, where the brick never emits machine-level changes — ADR-012); setting the same color is a no-op.
- [ ] **Workspace dedup rule (this story owns it)**: an identical consecutive stitch command from the same actor at the same position emits nothing, matching `DSTStitchCommand.act` (affects US-109's sew-up interplay). *(US-109 landed the single-actor slice at the public `EmbroideryStream.addStitch` seam; this story adds the actor/layer/color dimensions. ⚠️ Catroid's sprite-change path emits the workspace position twice consecutively at stream level — below the dedup. That emission must go through the stream's private dedup-free `append(stitchAt:)` seam, not public `addStitch`, or the second point is silently swallowed; do not weaken the public dedup to compensate.)*
- [ ] Layer manager assembling multiple streams in z-order with color changes inserted between layers, matching `DSTPatternManager`'s TreeMap-of-layers behavior. (In M1 "layers" are engine-level; multiple objects arrive with the interpreter in M2.)

## Test-first plan
1. Hex parsing tests ("#FF0000", lowercase, invalid input → deterministic fallback), ported from `SetThreadColorAction` semantics.
2. Mid-stream color change: stitch sequence carries the flag on the correct record; header **CO == changes + 1** (CO counts color *blocks*, starting at 1 — both references and both fixtures confirm; see US-104).
3. Setting the identical color emits nothing; dedup test: identical consecutive command from the same actor emits nothing.
4. Two-layer assembly test: stitches concatenate in layer order with exactly one color change at the boundary, ported from `DSTPatternManagerTest`.

## References
- `Catroid/.../embroidery/DSTPatternManager.java`, `DSTPatternManagerTest.java`, `DSTStitchCommandTest.java`
- `Catroid/.../content/actions/SetThreadColorAction.java`
