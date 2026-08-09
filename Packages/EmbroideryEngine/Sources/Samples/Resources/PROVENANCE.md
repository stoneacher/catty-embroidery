# Bundled sample programs — provenance

Unlike `EmbroideryEngineTests/Resources/EmbroideryReference/`, whose fixtures are
byte-exact copies from Catrobat **Catty**, and unlike
`InterpreterTests/Resources/GoldenPrograms/`, whose `square.dst` is our engine's
own output pinned **by bytes**, the files here are neither. They are a **JSON
serialization of the Swift builders in `Sources/Samples/`** (ADR-003 format
version 1).

That difference decides how they are guarded. There is deliberately **no SHA-256
below**: `SampleJSONResourceTests.checkedInResourceMatchesTheBuilder` compares
`decode(resource)` against the builder as a *value*, so a re-encoding that
changes whitespace or key order is correctly a non-event, while a changed brick
is correctly a failure. A hash here would fail on the first and is unnecessary
for the second.

**The builders are the single source of truth.** A resource that disagrees with
one is a failing test, not a second opinion. Nothing in M3 reads these files —
the app links the builders directly and has no decode path (US-304). They exist
so the encoding is guarded now, and so M5 can copy one into Documents to create
a real project rather than re-deriving ADR-003's format.

## `OctagonRosette.json` — sample 1

### Origin and licence

Transcribed brick for brick from Catrobat **Catroid**:

| | |
|---|---|
| File | `catroid/src/embroideryDesigner/java/org/catrobat/catroid/common/defaultprojectcreators/DefaultExampleProject.java` |
| Method | `createDefaultProject`, lines 121–171 |
| Copyright | © 2010–2025 The Catrobat Team, AGPL-3.0 |
| Names | `catroid/src/main/res/values/strings.xml:1371,1373,1375` |

This repository is AGPL-3.0, so the licences match; the attribution is recorded
because the *content* is theirs, not merely the concept.

### Transcription

| Catroid statement | Our brick |
|---|---|
| `new SetVariableBrick(new Formula(8), variableInnerLoop)` | `.setVariable(name: "Inner Loop", to: .number(8))` |
| `new SetVariableBrick(new Formula(8), variableOuterLoop)` | `.setVariable(name: "Outer Loop", to: .number(8))` |
| `new ZigZagStitchBrick(new Formula(2), new Formula(10))` | `.zigZagStitch(length: .number(2), width: .number(10))` |
| `new RepeatBrick(repeatUntilFormulaOuterLoop)` | `.repeatLoop(times: .variable("Outer Loop"))` |
| `new RepeatBrick(repeatUntilFormulaInnerLoop)` | `.repeatLoop(times: .variable("Inner Loop"))` |
| `new MoveNStepsBrick(new Formula(100))` | `.moveNSteps(.number(100))` |
| `new TurnRightBrick(DIVIDE(360, innerLoop))` | `.turnRight(.binary(.divide, .number(360), .variable("Inner Loop")))` |
| *(inner loop close)* | `.loopEnd` |
| `new TurnRightBrick(DIVIDE(360, outerLoop))` | `.turnRight(.binary(.divide, .number(360), .variable("Outer Loop")))` |
| *(outer loop close)* | `.loopEnd` |

### Reference facts verified, not assumed

Four things about the reference that a careless transcription gets wrong:

- **The variables are sprite-scoped.** Catroid calls `needle.addUserVariable(…)`
  (`Sprite.addUserVariable`), not `project.addUserVariable`, with **inner declared
  first**. Ours are on `Object.variables` in that order, which the interpreter's
  first-declaration-wins resolution makes observable.
- **The `new Formula(1)` seed is dead code.** Catroid constructs each repeat
  formula as `new Formula(1)` and then calls `setRoot(USER_VARIABLE …)`, which
  discards the literal. The repeat count is a bare variable reference — not 1,
  and not a formula containing 1.
- **The start heading is 90, so the first move goes +x (right).** `Look.java:87-88`
  declares `private float rotation = 90f;` and `private float realRotation =
  rotation;`, and `getMotionDirectionInUserInterfaceDimensionUnit()`
  (`Look.java:484-486`) returns `realRotation` unmodified. `MoveNStepsAction` then
  moves by `steps·sin(θ), steps·cos(θ)` — ADR-007's convention exactly — so a
  fresh sprite walks along +x.

  **An earlier version of this file asserted the opposite** ("the start heading is
  0, not 90") and cited the same line as evidence, which was factually reversed.
  It shipped, and it rotated the whole design a quarter turn. Caught by the
  cross-vendor review (Codex round 1). Worth leaving in the record because the
  claim was not a guess — it was stated as a verified reference fact, with a line
  number, and the line number was right while the reading of it was backwards.
- **The stage units and DST factor match.** Catroid's units are virtual pixels at
  a pixel→unit factor of 2.0, identical to ADR-005/ADR-007, so a 100-step side is
  20 mm on both platforms.

### Deliberate divergence: the names are pinned to English

Catroid *localises* these strings — a Russian user's default project has an
object named `Игла` and variables `Внутренний Цикл` / `Внешний цикл`. We pin the
English literals `Needle`, `Inner Loop`, `Outer Loop`.

A variable name is an **identifier** in our JSON format, not display text: a
program whose identifiers changed with the device locale would not round-trip,
and `Formula.variable("Inner Loop")` would stop resolving. The sample's *display*
name and description are localised properly, in `en.lproj/Localizable.strings`.

### Measured figures

Re-derived from a run by `OctagonRosetteGoldenTests`, not copied from the
planning session — though all four planning figures did reproduce exactly.

| | |
|---|---|
| Ticks | 139 (= 2 + 1 + 8 × (8 × 2 + 1); ADR-018 makes loop bookkeeping zero-tick) |
| Stitch events / records | 3194 (no dedup, no interpolation) |
| Colour blocks | 1 — `CO 1`. Catroid sets no thread colour, so neither do we |
| Jumps | 0. The largest gap is `hypot(2, 10)` = 20.4 units, far under ADR-020's ±121 |
| Extent | 98.6 × 98.6 mm |
| Stage bounds | x and y both [−246.5, +246.5] |
| DST size | 10 097 bytes = 512 + 3 × 3194 + 3 |
| Peak stitches in one tick | 51 |

**The stage margin is 3.5 points — 0.7 mm.** ADR-007's stage allows ±250 and this
design reaches ±246.5. That is a consequence of transcribing verbatim, not a knob
to turn: the side length 100 and the zigzag width 10 are the reference's.
`OctagonRosetteGoldenTests.stageMarginIsThin` asserts the measured value rather
than the limit, so a change announces itself as a specific failure.

### Floating-point pin (ADR-019)

**This design's stitch count depends on Apple platforms' libm.** All 64 sides are
nominally 100 stage points at zigzag length 2 — an exact 50× multiple, i.e.
sitting *on* a `floor(distance / length)` boundary. Being on the boundary is only
the screening question; the deciding question is the along-motion residue in
ulps, and unlike US-207's square (whose residues are purely perpendicular and
cost ~3e-31), this design's are along-motion and large: positions reach ±246,
where `ulp` is 2.84e-14, **twice** `ulp(100)`.

The boundary-free count would be 3201 (1 anchor + 64 × 50). The actual 3194
reconciles in three terms:

```
1 anchor  +  54 × 50  +  10 × 49  +  3 × 1  =  3194
```

Ten sides come up an interval short; **seven** of those are decided by libm's
rounding, the rest by the geometry of the anchor those seven left behind
(~1e-4 short, i.e. 1e10 ulps clear of any boundary).

**The split moves under rotation; the total, measurably, does not.** Correcting
the start heading from 0 to Catroid's 90 changed the shape from `55/9/2` to
`54/10/3` and left the total at exactly 3194 — along with 139 ticks, the
51-stitch peak, the ±246.5 extents and the 10 097 bytes.

It is tempting to explain that by 8-fold symmetry, and an earlier draft did. That
is not a proof and the evidence is in the same sentence: symmetry is a property of
*exact* geometry, this walk runs on `sin`, `cos` and `hypot`, and the split
changing is itself a demonstration that the floating-point behaviour is **not**
equivariant under the rotation. So the coinciding totals are a measurement on
this toolchain, not an invariant — pinned as one by
`OctagonRosetteGoldenTests.totalsAreUnchangedByAQuarterTurn`. What it tells you is
useful either way: the goldens are robust to orientation, the screening histogram
is not, and that is the difference between what the two of them measure.

The `3 × 1` term is not predicted by anything in ADR-019 and is worth stating on
its own: **a `turnRight` brick can emit a stitch.** A turn moves the needle zero
distance but still produces a `.needleMoved` that reaches the pattern, and when a
short side has left the anchor exactly one stitch length behind, that
zero-distance update measures 2.0 and emits one catch-up point. The design
therefore self-corrects — the anchor never falls more than one interval behind,
and a lost interval shifts the anchor instead of deforming the shape.

Guarded by `SampleThresholdTests.theRosetteDependsOnLibmRoundingOfHypot`. A Linux
SwiftPM job can be expected to turn it red; that test will say why.

### What "comparable to the Android app" does and does not claim

The story's acceptance criterion motivates verbatim reproduction as making our
stitch output "cross-platform comparable against the shipping Android app". That
is right in substance and **over-stated as byte comparability**, which this file
records so a later reader does not chase a byte diff that cannot close:

Catroid computes its pattern distance as `(float) Math.hypot(...)`
(`catroid/src/main/java/org/catrobat/catroid/embroidery/RunningStitchType.java:35-37`)
and carries every coordinate as `float`. We compute in `Double` (ADR-014). The
residue that costs this design ten intervals is ~1e-14, roughly nine orders of
magnitude below `ulp(100f)` — so the threshold behaviour that produces our 3194
cannot arise the same way on Android, and their float-level position error is a
different perturbation again.

This is not a new divergence; it is ADR-014's "bit-exact parity with Android is
not guaranteed" showing up in a place where it is *structurally* visible rather
than sub-resolution.

The precise claim, since a looser one was drafted first and is wrong: Android's
output is **not a byte-identical oracle** — equality cannot be promised, and a
mismatch is therefore not evidence of a bug on either side. That is weaker than
"byte comparison is impossible" and weaker than "the record counts cannot
coincide"; neither follows, and float-vs-Double does not prove either (Codex
round 1). A byte comparison remains worth *running* — it just cannot be a golden.
What the two platforms do share is the **same program with the same brick
semantics** producing the **same design**, comparable by shape, size, colour
count and record structure.

## `SquareCoil.json` — sample 2

Our own content. Catroid ships one starter project and no sample files, so there
is no reference and nothing to attribute.

A square spiral: each side is longer than the last, so the walk winds outward in
a nested coil. Deliberately unlike sample 1 in silhouette, stitch type and thread
count — two bundled samples that look alike teach a first-time user nothing — and
the only bundled content that drives motion from a *variable*, so
`changeVariableBy` and a variable-valued `moveNSteps` are exercised somewhere.

| Parameter | Value | Why |
|---|---|---|
| Sides | 44, split 31 / 13 | 3 action bricks per side ⇒ 137 ticks, past the 120 floor without padding |
| First side / growth | 9 / 6 | with the stitch length, puts every side exactly off-boundary |
| `tripleStitch(length:)` | 6 | must be an integer — `interpretInteger` truncates (ADR-017) |
| Turn | 90° | 44 × 90° = 11 × 360°, so the heading closes exactly |
| Colours | `#1d4ed8` → `#f59e0b` | must differ as parsed `ThreadColor`s or ADR-015 makes the second a no-op |

**The three geometry constants are chosen together for ADR-019.** `9 ≡ 3 (mod 6)`
and the growth is a whole multiple of 6, so every side length is congruent to 3
modulo the stitch length — exactly halfway between two `floor` boundaries, the
largest margin the parameter space allows. Measured closest approach over the
whole run: **5.2 × 10¹³ ulps**, against sample 1's ~0. This is ADR-019's "handle
it by choosing inputs off the boundary" clause actually exercised, next to a
sample where the acceptance criterion forbids exercising it.

**The 31/13 split is about thread, not sides.** Cumulative thread after `k` sides
grows as `3k(k+1)/2`, so 31 is the halfway point of 44 — splitting the design
1489 / 1487 stitches instead of the 760 / 2216 a symmetric 22/22 would give. A
balanced split also makes the colour assertion mean something; "a change exists
somewhere" would pass against a change on the second stitch.

| | |
|---|---|
| Ticks | 137 |
| Stitch events / records | 2976 (includes the 5-point `sewUp` tack) |
| Colour blocks | 2 — `CO 2`, one effective change (the leading set is silent, ADR-015) |
| Jumps | 0 |
| Extent | 53.4 × 52.8 mm |
| Stage bounds | x [−132.0, +135.0], y [−135.0, +129.0] |
| DST size | 9443 bytes = 512 + 3 × 2976 + 3 |
| Peak stitches in one tick | 132, on the longest side |

## Regeneration

These files are **generated, never hand-edited**:

```
REGENERATE_SAMPLE_JSON=Sources/Samples/Resources \
  swift test --package-path Packages/EmbroideryEngine
```

`JSONEncoder` with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, so a
builder change reads as a legible diff rather than one reordered line.

When `checkedInResourceMatchesTheBuilder` goes red, **decide whether the builder
change is correct before regenerating.** Regenerating is how a resource guard
gets silently defeated. The regeneration suite is off unless the environment
variable is set, for the same reason: a test that rewrote its own fixture on
every run would compare a file against the builder that had just written it.

## Trust verification

**Status: verified — both samples are trusted** (Sebastian, 2026-08-09). Opened
in an embroidery viewer; both load without error and render the intended design.
An independent byte-level decode reconciles every figure the viewer reported.

| Viewer reported | Octagon Rosette | Square Coil |
|---|---|---|
| Dimensions | 98.6 × 98.6 mm | 53.4 × 52.8 mm |
| Stitches | 3195 | 2978 |
| Colour changes | 0 | 1 |
| Jumps / trims / stops | 0 / 0 / 0 | 1 / 0 / 0 |

**Shapes are right.** The rosette renders as eight octagons fanned around one
shared corner, with the eight sides adjacent to that corner meeting at the centre
— the spoked hub in the render is those sides, not an artefact. The coil renders
as a nested square spiral with the blue core and the amber outer third, matching
the 31/13 split.

### The two count differences are the viewer's convention, not our bytes

Both were checked by decoding the files directly rather than by argument, since
"the viewer disagrees with the golden" is the one result this check exists to
surface. The decode reads the 512-byte header and then 3-byte records, counting
flag bytes:

| | records in file | `ST:` field | flag bytes present |
|---|---|---|---|
| Octagon Rosette | 3195 (3194 stitches + 1 terminator) | **3194** | `0x03`, `0xF3` |
| Square Coil | 2977 (2975 stitches + 1 colour change + 1 terminator) | **2976** | `0x03`, `0xC3`, `0xF3` |

The `ST:` fields are exactly our own numbers, and under ADR-012 that field is the
authoritative in-file count. The viewer's totals reconcile as:

```
rosette:  3194 + 1 (end-of-file record counted as a stitch)                = 3195
coil:     2976 + 1 (end-of-file record)  + 1 (0xC3 counted twice)          = 2978
```

**The reported "Jumps: 1" looks wrong and is not.** There is **no jump-only
record in either file** — the flag histograms above contain no `0x83`. The single
jump is the one `0xC3` colour-change record, and `0xC3` has bit `0x80` set by
construction, so a reader that tests the jump bit before testing the
colour-change bits reports the same record as both. That also explains the coil's
second extra stitch: the same record is expanded into two commands. Nothing
travels un-sewn; a colour change is where the machine *stops*, not a travel move
(ADR-013).

What this check does **not** establish, stated because the rosette's symmetry
makes it tempting to think otherwise: it does not confirm the start heading. The
design has 8-fold symmetry, so heading 0 and heading 90 render identically and
report identical dimensions and counts — which is exactly how the quarter-turn
error survived to the cross-vendor review. That fact is pinned by
`OctagonRosetteGoldenTests.totalsAreUnchangedByAQuarterTurn`, and the heading
itself is pinned only by the reference citation above.

Also corroborated arithmetically: the header extents. The rosette's `+X 493 /
-X 493` and `+Y 483 / -Y 503` sum to 986 units on both axes = 98.6 mm, and the
asymmetry between `+Y` and `-Y` is ADR-012's rule that extents are measured from
the **first stitch**, not from the design centre. The coil's `270/264` and
`258/270` give 534 × 528 units = 53.4 × 52.8 mm, matching the viewer exactly.

### Reproducing the check

To produce the files:

```
DUMP_SAMPLE_DST=1 swift test --package-path Packages/EmbroideryEngine
```

then open the printed paths. What to check:

- **`OctagonRosette.dst`** — eight octagons fanned around one shared corner;
  98.6 × 98.6 mm; 3194 stitches; 0 colour changes; 0 jumps; 0 trims. A viewer
  stitch count other than 3194 means the screening and the golden disagree, and
  that must be resolved rather than regenerated around.
- **`SquareCoil.dst`** — a nested square spiral winding outward, ~53 × 53 mm,
  **2 colour blocks**, 2976 stitches, 0 jumps. Worth an aesthetic judgement as
  well as a numeric one: the colour changes 31 sides in, so the amber is the
  outer third of the coil.
- Optional and high-value: run sample 1 in the Android Embroidery Designer and
  compare. Per the section above, expect the **design** to match; the record
  count may or may not, and a difference there is not evidence of a bug on
  either side.
