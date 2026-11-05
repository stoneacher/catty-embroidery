# Release readiness (M6 polish)

**Status**: Planned — 2026-11-05 | **Epic**: E8 | **Branch**: `feature/release-readiness`

**Goal**: the app can go to its first TestFlight build without silently breaking anything afterwards:
- the program format is frozen at v1 by a test, so the first vocabulary change after distribution forces a version bump;
- a `/release` checklist runs at the moment of release instead of being remembered;
- the app has its icon, a privacy manifest and the export-compliance key;
- it plays exactly the roadmap's haptic map;
- it has passed a repeatable pseudo-localization and RTL audit.

M6's brick parity is already delivered by the Brick backend and Variables features. This is the "polish is an **audit**, not a build-out" half of M6 (ROADMAP), plus US-331.

**In scope**
- US-331: the frozen-v1 vocabulary census and its ADR-037 trigger; the `/release` command.
- The haptic map: success on run-complete (which is export success; see D3), a selection tick on brick add and reorder-drop, an error on export failure. Nothing else.
- The pseudo-loc and RTL pass, with fixes.
- The app icon, in light, dark and tinted variants.
- The privacy manifest, `ITSAppUsesNonExemptEncryption`, and the App Store notes (age rating 4+, not Kids Category).

**Out of scope**
- `rand` (ADR-046 defers it). After the freeze it costs format v2.
- Real translations: Crowdin, after the transfer.
- The upload itself, the App Store Connect record, the questionnaire, the privacy label and the version bump. Those are human items, listed in `/release`.
- The pre-beta manual accessibility review. `/release` lists it, and it runs at the first release, not inside this feature.

## Decisions (Sebastian, 2026-11-05, on swift-architect's plan)

- **D1. The release checklist lives in `.claude/commands/release.md`,** beside `finish.md`, with a roadmap pointer under the TestFlight checkpoint. A roadmap-only section would be remembered rather than run, which is US-331's exact failure.
- **D2. The freeze fires when the census test merges** (PR 1). It doesn't wait for the first upload, and `rand` is not added first.
  - The census encodes one maximal v1 program and compares every JSON key, recursively, with a checked-in list. It also compares the property labels (`Mirror`) of `Program`, `Scene`, `Object`, `Script` and `Variable`, because a new optional field that encodes as absent would otherwise be invisible.
  - `Brick`, `Formula` and `ScriptHeader` are bound by exhaustive switches, so a new case fails to compile.
  - Counting cases is rejected: it misses renames and new leaf-enum cases.
- **D3. The haptic map is an observable pulse on `AppModel`.** `haptic: HapticPulse?` holds a kind and a serial, and one `.sensoryFeedback` at the window root plays it. An injected `UIFeedbackGenerator` protocol is rejected: it adds a protocol, a live implementation and a test double to copy a mechanism the app already has.
  - **selection:** a palette insert that the editor accepts, and a reorder drop through a new `AppModel.dropRows` that changes the program. Today `.onMove` calls `editor.moveRows` directly. Accessibility moves, undo/redo, delete, replace, parameter edits and rename produce nothing.
  - **success:** a run that ends `.programFinished` with its export ready. Export is prepared eagerly at run end (ADR-026), and a `ShareLink` reports nothing back, so run-complete *is* export success; there is no later event to hang it on. A user stop and the stitch limit produce nothing (to be confirmed by the brief's Codex round).
  - **error:** the export state *entering* `.failed`, at run end or on a rename re-prepare. Error replaces success at run end. Later keystrokes in an already-failed state don't pulse again.
  - **Audit finding:** `StageView.swift:157` plays `.start` on every run and `.stop` on every finish, which is outside the map. It is removed.
- **D4. The pseudo-loc and RTL pass is a launch-argument procedure,** recorded in `/release` so it can be repeated. There is no second scheme and no snapshot framework.
  - `-NSSurroundLocalizedStrings YES`: an unbracketed string is unlocalized. A UI-hierarchy dump is grepped for it, excluding user content.
  - `-NSDoubleLocalizedStrings YES`: string length.
  - `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`: RTL, also run at AX5.
  - The screens are listed in `/release`, compact and regular.
  - **New pin: the stage never mirrors.** It is a physical plane (ADR-007), so this covers the canvas, the recognisers and the directional pan actions. Formula text stays left-to-right.
- **D5. The icon is converted from Catroid's `embroideryDesigner` vector adaptive icon,** not upscaled from its 192 px PNG.
  - The light variant is the gradient background with the white glyph. Dark and tinted are derived from the same layers.
  - Provenance (AGPL-3.0, files, commit) is recorded, and the conversion script is kept in `scripts/`.
  - Icon Composer is rejected: it needs pbxproj changes.
- **D6. The privacy manifest declares no tracking and no collected data.** It lists exactly the required-reason APIs the release code uses: `UserDefaults` (CA92.1) and file timestamps (C617.1, DDA9.1).
  - `ITSAppUsesNonExemptEncryption = NO`.
  - Age rating 4+, not Kids Category.
  - The bundle ID stays `org.catrobat.embroiderydesigner`. Sebastian is getting access to Catrobat's Apple developer team and will create the App Store Connect record and upload himself. That also unblocks the M4 TestFlight checkpoint.

## Acceptance criteria

- [ ] Adding a `Brick`, `Formula`, `ScriptHeader` or leaf-enum case, renaming an associated-value label, or adding a stored field to the program structs turns `FrozenV1VocabularyTests` red (or fails to compile). Each is shown by a mutation.
- [ ] ADR-037 carries the trigger as an amendment: the freeze fired on the census merge, with its date.
- [ ] `/release` exists, and its first item is the freeze. A dry run reports every item's state. US-331 leaves the backlog as a record bullet.
- [ ] Every event in D3 produces exactly its pulse, and every event outside D3 produces none. A test sweep covers the non-events.
- [ ] No `.sensoryFeedback` remains outside the window root. That's a grep, plus a device check on Sebastian's iPhone that each haptic plays once and that none plays at run start.
- [ ] `PrivacyInfo.xcprivacy` ships in the app bundle, with the D6 contents, and `ITSAppUsesNonExemptEncryption` reads `false`, all checked by hosted tests.
- [ ] The app icon appears on the home screen in light, dark and tinted modes (simulator screenshots).
- [ ] The pseudo-loc and RTL pass has run on every listed screen, with screenshots. Every finding is fixed or tracked, and the stage is shown unmirrored under RTL.

## Slices and test-first outline

**PR 1: the freeze (about 40 lines of non-test code, plus docs).**

1. **Frozen-v1 vocabulary census** (risky: yes, program format; reviewer plus one Codex slice round when green). It needs no production code.
   - Tests in `EditorCoreTests/FrozenV1VocabularyTests.swift`:
     - `encodedVocabularyEqualsFrozenV1`
     - `structFieldLabelsEqualFrozenV1`
     - `maximalProgramCoversEveryBrickCase`
     - `maximalProgramRoundTrips`
     - `keyCollectorDescendsIntoArraysAndNestedObjects`
   - Then the ADR-037 amendment.
   - Mutations:
     - a dummy case in `Sensor` and in `UnaryFunction`;
     - a dummy case in `Brick` (a compile failure);
     - `var note: String?` on `Variable`;
     - `arc`'s `radius` label renamed;
     - one literal entry deleted;
     - a non-recursive collector;
     - one `allCases` leg dropped from the builder.
2. **`/release` command and roadmap section** (risky: no; docs). The items:
   - the freeze;
   - the version bump (human, in Xcode);
   - the manifest and plist tests;
   - the icon;
   - the D4 pass;
   - the pre-beta accessibility review;
   - the graph drift check;
   - the Release-config compile;
   - the upload (human);
   - App Store Connect: the label "Data Not Collected", the age questionnaire, the privacy-policy URL and export compliance (human).

   Also re-grep the required-reason APIs, since DEBUG-only timing code could leave its `#if DEBUG`. Verified by a dry run. US-331 is recorded out of the backlog.

**PR 2: polish (about 400 lines of non-test code).**

3. **Haptic pulse model** (risky: no). Tests in `HapticMapTests`, using the existing `ExportDoubles` failing writer:
   - Tests:
     - `paletteInsertPulsesSelectionOnce`
     - `refusedPaletteInsertPulsesNothing`
     - `dropThatMovesPulsesSelection`
     - `refusedOrNoOpDropPulsesNothing`
     - `nonDropEditsPulseNothing`
     - `programFinishedWithReadyExportPulsesSuccess`
     - `stopAndStitchLimitPulseNothing`
     - `exportFailureAtRunEndPulsesErrorNotSuccess`
     - `renameIntoFailurePulsesErrorOnce`
     - `consecutiveInsertsEachPulse`
     - `hapticKindMapsToSensoryFeedback`
   - Mutations:
     - selection and success swapped;
     - a pulse on a refused insert;
     - a pulse on `stoppedByUser`;
     - success emitted after error;
     - no transition guard;
     - a frozen serial;
     - a pulse on any `.applied` move.
4. **View wiring** (risky: no). This adds the root `.sensoryFeedback`, removes `StageView`'s, and routes `.onMove` through `dropRows`. No test can fail on the modifier itself, so it is checked by review and on the device (ADR-032).
5. **Privacy manifest and encryption key** (risky: no). Start from the committed `Info.plist`: the working tree's Xcode edit only stripped its comment and reordered keys.
   - Tests in `ReleaseMetadataTests`:
     - `privacyManifestShipsInTheBundle`
     - `manifestDeclaresNoTrackingAndNoCollection`
     - `manifestDeclaresExactlyTheRequiredReasonCategoriesUsed`
     - `infoPlistDeclaresNoNonExemptEncryption`
   - Mutations:
     - the file moved out of the synchronized folder (this proves the bundle test);
     - the key removed;
     - tracking set to true;
     - an extra category.
6. **App icon** (risky: no). Three PNGs and `Contents.json`, verified by build and screenshots.
7. **Pseudo-loc and RTL audit, with fixes** (risky only if a fix touches the stage transform). A fix in code gets a red presentation test first.
   - The stage-independent-of-`layoutDirection` test is written only if the canvas reads that environment. Otherwise it could not fail, so it is skipped and the reason recorded.
   - Optional: a lint that every multi-argument catalog entry uses positional specifiers. It counts only after a mutation shows it red.
   - Budget: 250 lines or less.

## Verification at handover

- Every slice is mutation-checked and recorded. Slice 1 gets `swift-code-reviewer` and a Codex round when green. Each PR gets the Codex handover loop (cap 5).
- **This brief gets one Codex round before any test,** on the unpinned semantics: the meaning of each D3 event, the stop and stitch-limit question, error/success precedence, the transition rule, and D2's trigger.
- Screenshots: the icon in three modes, and every D4 screen. The haptics are checked on the device. No Ink/Stitch check is needed, because DST bytes don't change.
- For the pre-beta accessibility review:
  - Do haptics duplicate VoiceOver announcements?
  - Does the RTL stage read correctly with VoiceOver's directional pan actions?

## ADRs

- **ADR-052, the haptic map** (D3), new.
- **ADR-037 amendment:** the freeze trigger and its census (D2).
- **ADR-011 amendment:** App Store prep (D6).
- **An ADR-007 amendment, only if the audit confirms the stage never mirrors** (D4).

## References

- ROADMAP M6 and the M4 TestFlight checkpoint.
- Backlog US-331.
- The ADRs: 006, 007, 011, 023, 026, 032, 037 (2026-10-18 amendment), 041 and 046.
- Project management brief D10.
- `../Catroid/catroid/src/embroideryDesigner/res/drawable/ic_launcher_foreground.xml` and `drawable-v24/ic_launcher_background.xml`.
- The census precedents: `FormulaCensusTests` and `UndoEnumerationTests`.
- The architect's full plan is summarised here. Its detail (screen list, key estimates) is reproduced in the slices as they are built.
