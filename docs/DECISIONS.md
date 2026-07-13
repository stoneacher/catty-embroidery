# Decision log

Lightweight ADRs. Newest at the bottom. Format: context → decision → consequences.

## ADR-001 — App scope: embroidery-focused block app (2026-07-06)
**Context**: On Android, "Embroidery Designer" is the full Pocket Code app (complete Catrobat language + interpreter + stage) shipped as a Gradle flavor. A full port exceeds bachelor-project scope; a blocks-free drawing tool would lose the "learn coding" essence of Catrobat.
**Decision**: Build a visual block-programming app restricted to the brick subset needed for embroidery (motion, control/loops, variables/formulas, the eight embroidery bricks) with stage preview and DST export.
**Consequences**: Interpreter is designed for exactly this subset; brick set parity is defined against the Android embroidery bricks, not all of Pocket Code.

## ADR-002 — Stack: native Swift 6 / SwiftUI, engine as SPM package (2026-07-06)
**Context**: Catty (existing iOS app) is UIKit + SpriteKit with an Obj-C/Swift mix on iOS 13 — dated. Catrobat plans to port its apps to Flutter over the coming months (Paintroid-Flutter is the newest org codebase), which was weighed explicitly.
**Decision**: Stay native: pure Swift 6, SwiftUI UI, minimum iOS 17. The engine (stitch domain, patterns, DST writer, interpreter) lives in a platform-independent Swift Package testable with `swift test`. SpriteKit/Canvas only where stage rendering needs it. Reconfirmed against the Flutter option — the thesis assignment is a modern *native* standalone iOS app.
**Consequences**: Best-in-class iOS experience and TDD-friendly engine without a simulator; diverges from the org's Flutter direction, so eventual maintenance stays a separate native track. Paintroid-Flutter is still mirrored for repo hygiene (CI, lint, conventions), not for code.

## ADR-003 — Project format: native JSON first, .catrobat later (2026-07-06)
**Context**: `.catrobat` files are ZIPs containing a versioned, quirky `code.xml`; full compatibility from day one adds heavy early effort.
**Decision**: Own Codable/JSON project format with a version field. The program model is kept close to Catrobat concepts (scene/object/script/brick/formula) so a `.catrobat` importer/exporter can be added as a later story.
**Consequences**: DST is the only interoperability requirement for core scope; Share-platform interop is a stretch goal.

## ADR-004 — Minimum iOS version: 17.0 (2026-07-06)
**Context**: Trade-off between device coverage and modern SwiftUI APIs.
**Decision**: iOS 17 — covers the vast majority of active devices and unlocks the Observation framework.
**Consequences**: No need for pre-Observation state management workarounds.

## ADR-005 — DST semantics ported from Catroid, verified against Catty fixtures (2026-07-06)
**Context**: Two reference implementations exist: Catroid's `org.catrobat.catroid.embroidery` (canonical, Java/Kotlin) and Catty's `src/Catty/Embroidery/` (Swift). Catty ships a real reference file (`CattyTests/Resources/EmbroideryReference/stitch.dst`).
**Decision**: Treat Catroid as the semantic source of truth (512-byte header, 3-byte records with conversion table, jump bit 0x80, color-change 0xC0, max 121 units/stitch, pixel→unit factor 2.0, terminator 00 00 F3); use Catty's fixtures and tests as golden files for our TDD suite. Port concepts, do not copy code wholesale (all reference code is AGPL-3.0; our project is AGPL-3.0 as well).
**Consequences**: Engine tests are written against known-good bytes before any implementation exists.

## ADR-006 — App-layer architecture: @Observable MVVM, no TCA (2026-07-06)
**Context**: The Composable Architecture was explicitly evaluated (TestStore's TDD fit, block-editor state complexity, effect management) against: solo thesis developer, ≤5h stories, and handover to the Catrobat org, which is not a TCA shop. Most undo-worthy, test-critical complexity already lives in the pure SPM package, which is exactly what TCA would otherwise discipline.
**Decision**: Plain `@Observable` view models on `@MainActor`; zero third-party architecture dependencies. Adopt three TCA-inspired patterns without the framework: (1) editor mutations modeled as a pure `EditAction` enum applied to the value-type program via a single `apply(_:)` funnel — views never mutate the program tree directly; (2) app-layer side effects (file I/O, DST export/share, clock, UUID/date) behind small initializer-injected interfaces with deterministic test doubles; (3) editor tests assert the entire resulting `Program` value, not just the touched field.
**Consequences**: Undo/redo = bounded in-memory snapshot stack (value semantics make it nearly free), coalesced per gesture, bridged to `UndoManager` for shake/Cmd-Z; the undo stack is never persisted. Maintainable by any iOS developer, including Catrobat reviewers and thesis examiners.

## ADR-007 — Stage coordinate space and physical units (2026-07-06)
**Context**: DST units are 0.1 mm, and the engine's pixel→unit factor of 2.0 means 1 stage point = 0.2 mm — stage size determines the *physical* embroidered size, bounded by real hoops (~100×100 mm consumer machines). US-102/US-104 and the M2 virtual needle bake in a coordinate convention long before any UI exists.
**Decision**: Center origin, y-up, fixed virtual stage of 500×500 points (≈ 100×100 mm hoop at 1 pt = 2 DST units = 0.2 mm). The engine applies **no y-flip** when converting to DST units (matching both references); flipping for screen display is purely a rendering concern in M3. Angle convention: degrees, 0° = up (Catroid convention; x via sin, y via cos).
**Consequences**: Engine domain types carry this space explicitly; the M3 canvas, zoom math, and export size validation inherit a deliberate choice instead of an accident.

## ADR-008 — Script representation: flat brick list with paired control bricks (2026-07-06)
**Context**: Catroid scripts are flat ordered brick lists where loops are begin/end brick pairs rendered by indentation; a nested-tree model would force custom nested drag-and-drop in SwiftUI (a multi-week build), whereas a flat list maps directly onto `List` + `.onMove` (free reorder, free VoiceOver reorder actions, free swipe-to-delete).
**Decision**: Scripts are flat ordered brick lists with paired enter/exit control bricks, Catroid-compatible. Nesting is a rendering concern (indentation), not a model structure. Moving a control brick moves its matched pair and enclosed range as one unit — this invariant lives in the model with tests (M2), not in the view (M4).
**Consequences**: M4's editor builds on standard SwiftUI list interactions; the model stays close to `code.xml` semantics for a later `.catrobat` importer.

## ADR-009 — Stage rendering: SwiftUI Canvas with batched paths (2026-07-06)
**Context**: Catty draws one `SKShapeNode` per stitch — a known SpriteKit performance trap that collapses at tens of thousands of stitches. Catroid batch-renders with a single libGDX `ShapeRenderer`.
**Decision**: SwiftUI `Canvas` (Metal-backed) drawing one stroked `Path` for threads and one for stitch points per color run; settled stitches rasterized to a cached image once counts grow, only the live tail redrawn per frame. Zoom/pan is a `CGAffineTransform` applied to the context (unit-testable math). The renderer sits behind a protocol taking `(stitches, transform)` so a Metal escape hatch stays open. Do **not** port Catty's node-per-stitch approach.
**Consequences**: Stack stays pure SwiftUI; M3 exit criterion includes a synthetic 50k-stitch design animating at 60 fps on an A15-class device. `ImageRenderer` over the same renderer gives PNG sharing nearly free (E7).

## ADR-010 — Device family: universal, iPhone-first (2026-07-06)
**Context**: Catrobat's school context makes iPads common; editor-beside-stage is the natural iPad layout. Deciding in M6 would mean rebuilding the navigation skeleton.
**Decision**: Universal app. iPhone-first design priority; the M3 navigation skeleton is size-class adaptive from the start (compact: sequential editor/stage; regular: side-by-side split).
**Consequences**: No navigation rework later; M3 stories include both size-class layouts at skeleton fidelity.

## ADR-011 — Privacy: fully offline, no accounts, no tracking (2026-07-06)
**Context**: The target audience is largely minors (13–18); GDPR-K/COPPA and App Store age-rating implications.
**Decision**: No network access, no accounts, no analytics or tracking of any kind. All data stays on-device; the only data egress is the user-initiated share sheet (DST/image export).
**Consequences**: Simplifies App Store review (age rating, no tracking declaration), removes consent UX entirely, and is a genuine selling point for schools.

## ADR-012 — DST semantics: Catroid is authoritative; known Catty divergences are not ported (2026-07-06)
**Context**: The two references disagree at byte level in places, and the Catty golden fixture is *self-golden* (generated by Catty's own implementation, covering only origin-start, positive-quadrant, single-color-boundary cases). Sharpens ADR-005.
**Decision**: Where the references diverge, Catroid's semantics win. Golden strategy: byte-identical against `stitch.dst` and `color_change.dst`, with the fixture itself verified in an embroidery viewer *before* the golden test is trusted. Specifics pinned now:
- **CO header field counts color blocks, starting at 1** (changes + 1), per both references and both fixtures.
- **Interpolation** follows the references exactly: splitCount = ceil(maxAxisDistance/121); emits duplicate-of-previous-point as jump, intermediates as jumps, target as jump, then target again as a plain stitch; intermediates rounded in stage coordinates *before* unit conversion.
- **Rounding** = `floor(x + 0.5)` (Java `Math.round`; differs from Swift `.rounded()` on negative halves). Relative deltas are computed between individually converted absolute positions (round-then-subtract), never from rounded differences.
- **Extents** are written relative to the first stitch, magnitudes only (per DST spec; equals Catroid's behavior for origin-start designs). A non-origin-start test case covers what the fixtures cannot.
- **Known Catty bugs — do not port**: rejects legal ±121 deltas (fatalError guard uses strict comparison); truncates name to 16 chars instead of 15; writes signed −X/−Y extents; computes extents relative to start point with a sign bug; 4-point sew-up. Catroid's 5-point sew-up (center/ahead/center/behind/center) and 15-char name limit are authoritative.
- **Workspace dedup**: an identical consecutive stitch command from the same actor at the same position emits nothing (Catroid `DSTStitchCommand.act`).
- **Deliberate divergence from Android**: Catroid's Set Thread Color brick only sets a sprite property and never emits a DST color change mid-script (color stops arise only from sprite/layer switches) — in our mostly single-object app that would make the brick a machine-level no-op. We emit a color-change record whenever the newly set color actually differs from the current thread color.
**Consequences**: Every M1 story's acceptance criteria cite these semantics; a future story cannot "fix" a red test by consulting the wrong reference.

## ADR-013 — Color-change flag placement on interpolated moves follows Catroid; the color_change golden is compared through a documented flag transposition (2026-07-09)
**Context**: Discovered during US-105 (journal 2026-07-09): when a color change precedes a long interpolated move, Catty consumed the pending flag on the *first* interpolation jump (the duplicate-of-previous record, at the old position — `color_change.dst` record 9 = `00 00 C3`), while Catroid applies pending flags to the target point before interpolating, so the flag lands on the *final plain stitch* at the new position. ADR-012 didn't pin this case; the sewn output is identical either way (jumps sew nothing — only the machine's pause position differs), but the bytes are not, so US-106's byte-identity criterion against `color_change.dst` cannot hold together with Catroid semantics.
**Decision**: Catroid placement wins (Sebastian, 2026-07-09) — the deciding concern is the Catroweb workflow: a program shared on the Catrobat platform must produce the same DST bytes on iOS as Android's Embroidery Designer. `EmbroideryStream` keeps capturing pending flags before interpolation and emitting them on the final plain stitch. The `color_change.dst` golden test therefore compares against the fixture with a **documented two-byte flag transposition** (the post-color-change move's duplicate-jump record byte 2 `C3→83`, its final plain-stitch record byte 2 `03→C3`), derived and asserted inside the test with a reference to this ADR.
**Consequences**: The transposed expected bytes are no longer the viewer-verified Catty original, so US-106's manual check re-verifies a *freshly generated* color-change file in Ink/Stitch (color stop must pause at the new position). `stitch.dst` is unaffected and stays byte-identical.

## ADR-014 — Pattern-layer arithmetic is Double; sub-resolution divergence from Catroid's float is accepted (2026-07-13)
**Context**: Catroid's stitch patterns compute in Java `float`; the engine's patterns (US-107 `RunningStitchPattern`, US-108 `ZigzagStitchPattern`) compute in `Double` — engine-native and matching Catty's prior art. Codex review of US-107 (journal 2026-07-10) produced a verified repro where the widths diverge by one stage unit after rounding (length 1, (−10,−10)→(−148,81): interpolated stitch 98 lands at (−93,44) in Double vs (−93,45) in float). US-108 makes the gap test-visible for the first time: zigzag offsets go through `sin`/`cos`, whose Double results carry ~1e-16 residue (`sin(180°)` = 1.22e-16, not 0), so Catroid's integer-exact expected coordinates cannot be asserted with `==`.
**Decision**: Pattern-layer geometry stays `Double`. Last-ulp divergences from Android's float output are accepted: they are orders of magnitude below embroidery resolution (1 unit = 0.5 stage points) and are absorbed by the ADR-012 `javaRound` at unit conversion in all but adversarially constructed cases. Pattern tests assert stage-space coordinates within an absolute tolerance (1e-9 — far above transcendental noise, far below resolution) instead of exact equality. Folded in from US-107: the degenerate-input guards (non-positive length, non-finite positions/width/heading emit nothing and leave state untouched) are a deliberate divergence from Catroid, whose float arithmetic NaN-poisons its anchor and goes permanently dead where Swift would trap. Same policy for astronomical stitch counts (US-108 review find): an update whose whole-length count exceeds 1,000,000 emits nothing — Java's `(int)` cast saturates to `Integer.MAX_VALUE` and Android hangs materializing the stitches, Swift's `Int(_:)` would trap; neither accident is ported.
**Consequences**: This does **not** weaken ADR-012 — byte identity still governs `EmbroideryStream`/DST output, where all values are integer embroidery units. A future story that needs bit-exact parity with Android program output (e.g. Catroweb round-trip validation) would have to revisit this with `Float` pattern arithmetic; until then, pattern tests cite this ADR for their tolerance helpers.
