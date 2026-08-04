# US-308 — Design name, DST export via share sheet, exported UTType, gating

**Epic**: E7 Export & sharing | **Estimate**: ~5 h | **Depends on**: US-211, US-306, US-303

**Status**: Not started

**Story**: As a user, I want to name my design and send the `.dst` file out through the share sheet, so I can get it onto an embroidery machine.

Catroid's stage-menu Share button is the exact structural analogue — gate → build the DST → hand it to the system share UI — and this story reproduces that shape while improving on essentially every detail below it. Two facts set the bar low and the value high: **Catty's shipping app exports every `.dst` with a blank `LA:` field** (only its unit tests ever pass a name), and **neither reference declares a `.dst` type at all**. So design naming and the UTType are real functionality with no working precedent on either platform.

## Acceptance criteria
- [ ] `DesignName` is a pure value type: ≤ 15 characters, ASCII only, non-empty, with the whitespace rule pinned explicitly rather than left to chance. Surfaced as a **live counter, not a post-hoc error** (Catroid silently `take(15)`s the project name and mangles non-ASCII to `?` bytes under `US_ASCII`).
- [ ] The **file name is sanitised independently of the header label** — they are unrelated fields in the format. Rejects `/` and empty (Catroid's `sanitizeFileName` has no empty check and produces a file literally named `.dst`). A 15-char label with a longer file name is legal.
- [ ] `UTExportedTypeDeclarations` in `Info.plist`: identifier under a domain we control, conforming to `public.data`, extensions `dst` and `DST`, localised description. No `LSHandlerRank` ambitions (ADR-011 — we open nothing). The structural template is Catty's `.catrobat` declaration (`App-Info.plist:102-123`), the only prior art available.
- [ ] `DSTDesign: Transferable` with `FileRepresentation(exportedContentType:)`, shared via SwiftUI `ShareLink` — which gives iPad popover anchoring and activity exclusions for free, replacing Catty's manual `UIActivityViewController` plumbing. ⚠️ `UTType(exportedAs:)` **traps at runtime if the identifier is not declared in Info.plist**, so the plist entry and this line must ship in the same commit.
- [ ] Export goes through an injected `DSTFileWriting` interface (ADR-006 pattern 2) that calls `DSTFile.write(to:)` — the package's only I/O. **The app writes no bytes itself.** The temp file is cleaned up (Catty never cleans up). This is Catty's proven `shareDST(embroideryService:)` + `EmbroideryServiceMock` shape, which is the one thing in that file worth porting.
- [ ] **Gating is `exportModel.count > 1` on the post-replay assembled stream**, not `hasValidPattern` (which counts recorded *ops* the replay may reject) and not the display-list count (op-derived, same defect). This closes the divergence ADR-020 left "for whoever wires up export to decide" and matches Catroid's `validPatternExists()`, which counts points in the *built* streams.
- [ ] **The export gate and the render empty-state may legitimately disagree**, and the app says so specifically. Catroid keeps one predicate for both so they agree by construction; for us they diverge exactly in ADR-020's rejected-coordinate case — ops recorded and drawn, every one rejected at replay. When they disagree the message is "nothing in this design can be embroidered", not a header-only file. Catty ships a valid-looking 515-byte header-plus-EOF file with zero stitches; we do not.
- [ ] `ExportState` is `idle | preparing | ready(URL) | failed(ExportError)`. This is where the roadmap's `failed` case actually belongs — US-306 explains why the *run* has none.
- [ ] US-211's overflow errors surface as a specific localised message naming the limit, with the design still on screen and still resettable. Not `print("File could not be written!")`, which is Catty's actual error handling.
- [ ] **Story-specific definition of done**: the name field's counter moves below the field at AX1 rather than truncating; the share affordance's disabled state carries a localised `.accessibilityHint` saying *why*; export success is **not** haptic (M6 owns the haptic map).
- [ ] Close-out pins **ADR-026**: the gating rule, the UTType identifier, the temp-file policy, and the design-name rules.

## Test-first plan
1. `DesignName`: 15 chars accepted, 16 rejected with the count surfaced, non-ASCII rejected naming the offending character, empty rejected; the leading/trailing-whitespace decision pinned by a test either way.
2. File-name sanitisation is independent of the header label; `/` and empty rejected; a 15-char label with a longer file name is legal.
3. A recording `DSTFileWriting` double receives the expected `DSTFile` and file name; a throwing double produces `.failed` with the error surfaced and the design intact on screen.
4. Gating: 0 or 1 assembled stitches → not exportable; ≥ 2 → exportable. **And the divergence case**: a program whose every coordinate is rejected (`placeAt(1e300, 0)` then `stitch`) is not exportable even though the display list is non-empty.
5. Export after `.stoppedByUser` produces byte-identical output to export at the same point of a completed run — Catty's teardown hazard, closed.
6. A US-211 overflow (100 colour blocks) produces the specific error rather than a trap.
7. `UTType(exportedAs:)` resolves at runtime in the app test target — the canary proving the Info.plist declaration is actually wired, since the failure mode is a runtime trap.
8. **Manual**: the exported file opens in Ink/Stitch with the expected `LA:` name and the expected colour stops.

## References
- `Catroid/.../ui/dialogs/StageDialog.java:146-167` (`shareEmbroideryFile` — the shape) and `:96-105` (the gate driving button visibility); `ui/ExportLaunchers.kt:35-54` (`type = "text/*"` for a binary file, hardcoded unlocalized chooser title — anti-goals); `embroidery/DSTHeader.kt:33,80` (silent truncation, `US_ASCII` mangling); `utils/Utils.java:284-287` (no empty-name check)
- `Catty/src/Catty/ViewController/Stage/StagePresenterViewControllerShareExtension.swift` (the temp-URL shape to port; the blank-name and fake-gate anti-goals); `CattyTests/Mocks/EmbroideryServiceMock.swift` (the injected-seam pattern); `Catty/src/Catty/Supporting Files/App-Info.plist:102-123` (the only UTType template)
- ADR-006 (injected side effects), ADR-011 (offline, no tracking), ADR-012, ADR-020 (`rejectedOnlyPatternAssemblesEmpty` — the gating divergence), ADR-025 (US-211's throwing initializers), ADR-026 (this story's close-out)
