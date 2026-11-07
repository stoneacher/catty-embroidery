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
- **D2. The freeze fires when this feature merges.** It doesn't wait for the first upload, and `rand` is not added first.
  - The ADR-037 amendment explicitly supersedes the 2026-10-18 "first distributed build" trigger with this stricter one, so the two are never active at once.
  - **The census byte-pins a canonical maximal-v1 document** (changed by the brief's Codex round). One program holds every case:
    - `ProgramDocument.encode(maximalV1)` must equal a checked-in `FrozenV1.json`;
    - decoding those frozen bytes must equal `maximalV1`.

    A key set alone would miss a same-key change an old reader misparses: `{}` becoming `null`, a raw-value or custom-Codable change, an omitted default field, a different number shape. A round trip only proves that the *new* writer and reader agree.
  - Exhaustive case-tag switches (no `default:`) over `Brick`, `Formula` and `ScriptHeader`, plus `allCases` for the leaf enums, prove the document covers the whole vocabulary. A new case fails to compile, or it's missing from the frozen bytes.
  - `Mirror` property labels of `Program`, `Scene`, `Object`, `Script` and `Variable` stay as a secondary alarm for a stored field the maximal encoding leaves out.
  - Rejected: counting cases (it misses renames), and a key-only census (Codex round, High).
- **D3. The haptic map is an observable pulse on `AppModel`.** `haptic: HapticPulse?` holds a kind and a serial, and one `.sensoryFeedback` at the window root plays it.
  - Every window has its own `AppModel` (ADR-023), so a pulse can't play in another window.
  - The serial makes two same-kind pulses in a row distinct triggers.
  - An injected `UIFeedbackGenerator` protocol is rejected: it adds a protocol, a live implementation and a test double to copy a mechanism the app already has.
  - **The terminal seam carries its reason** (Codex round). `RunViewModel.onRunTerminated` becomes `(RunCompletion, EmbroideryStream)`; today it carries only the stream. `AppModel`'s handler then:
    1. prepares the export;
    2. reads the resulting state and its eligibility;
    3. emits at most one terminal pulse.
  - **selection:** a palette insert the editor accepts (buttons and accessibility activation share the `addFromPalette` funnel), and a reorder drop through a new `AppModel.dropRows` that changes the program. Today `.onMove` calls `editor.moveRows` directly. Accessibility moves, undo/redo, delete, replace, parameter edits and rename produce nothing.
  - **success:** a run that ends `.programFinished` with a `.ready` export that is **eligible under ADR-026** (`count > 1`; Codex round). Export is prepared eagerly at run end, and a `ShareLink` reports nothing back, so run-complete *is* export success.
    - A naturally finished zero- or one-stitch program, or one with an invalid name, gets no pulse.
    - A user stop and the stitch limit never get success: the first is deliberately partial, the second a protective truncation, and HIG success means a completed task (confirmed in the Codex round).
  - **error:** **each failed preparation attempt** (Codex round), whatever ended the run, and on a rename re-prepare. Error replaces success. A rename that fails again from an already-failed state pulses again: one attempt, one pulse. A rename during a run doesn't prepare (`AppModel` defers it to termination), so it doesn't pulse until then.
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
  - *[Reversed 2026-11-07: the icon is Sebastian's Icon Composer file, `AppIcon.icon`.]*
    - **Source:** one layer, Catroid's original cat body with the eye whites cut out and the pupils kept, no stitching (AGPL-3.0, Catroid commit `0cd3e131b`, `embroideryDesigner` `ic_launcher_foreground.xml`). Fill, shadow and translucency are set in Icon Composer.
    - **No project change was needed after all.** The target's `ASSETCATALOG_COMPILER_APPICON_NAME` was already `AppIcon`, and the synchronized folder group made `AppIcon.icon` a member by itself. The `AppIcon.appiconset` was deleted.
    - **Older systems are covered:** for iOS 17–25, Xcode generates flat light, dark and tinted 1024 px images and `AppIcon60x60@2x.png`/`AppIcon76x76@2x~ipad.png` from the `.icon` (checked in the built app's `Assets.car` and `CFBundleIcons`).
    - The PNG route (a converter script and three PNGs) was built, then dropped unmerged. Exploration in the journal.
- **D5b. The home-screen label is "Embroidery"** (Sebastian, 2026-11-07).
  - Until now there was no `CFBundleDisplayName`, so iOS showed the target name, "catrobat_embro…".
  - Catroid's flavor name, "Embroidery Designer", would be truncated at about 12 characters, so the label is the short form, and the store listing keeps the full name.
  - It is set in `Info.plist` and localized in `InfoPlist.xcstrings` with a translator comment.
- **D6. The privacy manifest declares no tracking and no collected data.** It lists exactly the required-reason APIs the release code uses: `UserDefaults` (CA92.1, the app-private last-opened project) and file metadata (C617.1 for the app container, DDA9.1 because modification dates are displayed). 3B52.1 would be wrong: no file comes through a document picker. All of this was confirmed in the Codex round.
  - `ITSAppUsesNonExemptEncryption = NO`.
  - Age rating 4+, not Kids Category.
  - The bundle ID stays `org.catrobat.embroiderydesigner`. Sebastian is getting access to Catrobat's Apple developer team and will create the App Store Connect record and upload himself. That also unblocks the M4 TestFlight checkpoint.

## Acceptance criteria

- [x] Any change to the v1 wire format turns `FrozenV1VocabularyTests` red or fails to compile, and each kind is shown by a mutation:
  - a new `Brick`, `Formula`, `ScriptHeader` or leaf-enum case;
  - a renamed label or coding key;
  - `{}` becoming `null`;
  - a custom leaf-enum representation;
  - an omitted default field;
  - a changed number shape;
  - a new stored field.
- [ ] ADR-037 carries the trigger as an amendment that supersedes the 2026-10-18 one: the freeze fired when this feature merged, with its date.
  *[Open until merge: the amendment is written; the freeze fires and gets its date when this PR merges.]*
- [x] `/release` exists, and its first item is the freeze. A dry run reports every item's state. US-331 leaves the backlog as a record bullet.
- [x] Every event in D3 produces exactly its pulse, and every event outside D3 produces none. A test sweep covers the non-events.
- [ ] No `.sensoryFeedback` remains outside the window root. That's a grep, plus a device check on Sebastian's iPhone: each haptic plays once, none plays at run start, and with two windows (iPad) a pulse plays only for its own window.
  *[The grep is done (one, at `WindowRootView`). The device check is open: Sebastian's iPhone was unavailable on 2026-11-07. Also compare whether a reorder drop feels doubled with UIKit's own lift haptic, and whether a palette add pulses while the palette sheet covers the root (whole-PR review, question 10).]*
- [x] `PrivacyInfo.xcprivacy` ships in the app bundle, with the D6 contents, and `ITSAppUsesNonExemptEncryption` reads `false`, all checked by hosted tests.
- [ ] The app icon appears on the home screen in light, dark and tinted modes (simulator screenshots), and its label reads "Embroidery" (`ReleaseMetadataTests`).
  *[Label done: `displayNameIsEmbroidery`, and seen on the home screen. Icon seen in light mode only (Sebastian's screenshot); dark and tinted are in the built `Assets.car` but not yet screenshotted.]*
- [ ] The pseudo-loc and RTL pass has run on every listed screen, with screenshots. Every finding is fixed or tracked, and the stage is shown unmirrored under RTL.
  *[Ran on the project list, script, palette and stage (journal 2026-11-07); the stage is unmirrored; US-319 tracked. Not reached: the parameter editors and the iPad split, which are carried into `/release` item 5.]*

## Slices and test-first outline

**One PR** (ADR-041). The whole feature is about 450 lines of non-test code. The brief's Codex round rejected the planned two-PR split: ADR-041 splits only past about 1,500 lines, and nothing in the feature touches the format before the merge that freezes it.

1. **Frozen-v1 census** (risky: yes, program format; reviewer plus one Codex slice round when green). It needs no production code.
   - The program is built in `FrozenV1Program.swift`, the tag enums are in `FrozenV1VocabularyTags.swift`, and the tests are in `FrozenV1VocabularyTests.swift`:
     - bytes: `encodingTheMaximalV1ProgramMatchesFrozenBytes`, `frozenBytesDecodeToTheMaximalV1Program` (decode, then re-encode);
     - vocabulary: `maximalProgramCoversEveryCase`, `everyFormulaSlotHoldsAComposite`;
     - declarations: `structFieldsEqualFrozenV1`, `casePayloadsEqualFrozenV1`.
   - Then the ADR-037 amendment.
   - Mutations: the 15 listed in ADR-037's amendment, all red (journal).
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
3. **Haptic pulse model and terminal seam** (risky: no; the app layer, no export bytes). Tests in `HapticMapTests`, using the existing `ExportDoubles` failing writer.
   - Selection:
     - `paletteInsertPulsesSelectionOnce`
     - `refusedPaletteInsertPulsesNothing`
     - `dropThatMovesPulsesSelection`
     - `refusedOrNoOpDropPulsesNothing`
     - `dropBetweenIdenticalRowsPulsesNothing`: added after a mutant that ticked on any applied move survived. Swapping identical rows is applied but changes nothing.
     - `nonDropEditsPulseNothing`: a sweep including insert → undo → redo, a list move outside `dropRows`, an accessibility move and a replace through `editor.apply`, delete and rename. *[Parameter edits are not exercised separately: `pulse` has three callers, none on that path (whole-PR review, 2026-11-07).]*
     - `consecutiveInsertsEachPulse`
   - Success:
     - `programFinishedWithEligibleExportPulsesSuccess`
     - `programFinishedWithIneligibleExportPulsesNothing`: zero or one stitch, or an invalid name.
     - `stopOrStitchLimitWithGoodExportPulsesNothing`
     - `noTerminalPulseWhileTheWriterRuns`: the writer double observes the pulse still absent.
   - Error:
     - `stopOrStitchLimitWithFailingExportPulsesError`
     - `exportFailureAtRunEndPulsesErrorNotSuccess`
     - `failedExportThenRerunFailingPulsesErrorAgain`
     - `failedExportThenFailingRenamePulsesOncePerAttempt`
     - `renameDuringRunPulsesNothingUntilTermination`
   - Isolation and mapping:
     - `twoWindowModelsPulseIndependently`
     - `hapticKindMapsToSensoryFeedback`
   - Mutations:
     - selection and success swapped;
     - a pulse on a refused insert;
     - success on `stoppedByUser`;
     - success without the eligibility check;
     - success emitted after error, or before `prepare`;
     - an "entering `.failed`" guard instead of per-attempt;
     - a frozen serial;
     - a pulse on any `.applied` move;
     - a pulse on every `programChanged`.
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
6. **App icon and display name** (risky: no). `AppIcon.icon` (D5, as reversed) and `CFBundleDisplayName` (D5b).
   - Test: `displayNameIsEmbroidery` checks both the `Info.plist` value and the localized catalog value.
   - Mutations: "Embroidered" in the catalog only, and in `Info.plist` only. Both are red.
   - The icon itself is verified by build and screenshots.
7. **Pseudo-loc and RTL audit, with fixes** (risky only if a fix touches the stage transform). A fix in code gets a red presentation test first.
   - The stage-independent-of-`layoutDirection` test is written only if the canvas reads that environment. Otherwise it could not fail, so it is skipped and the reason recorded.
   - Optional: a lint that every multi-argument catalog entry uses positional specifiers. It counts only after a mutation shows it red.
   - Budget: 250 lines or less.
   - *[Done 2026-11-07: no code fix needed.]*
     - RTL mirrors correctly on the project list, the script and the stage, and the stage itself doesn't mirror (ADR-007 amendment).
     - Pseudo-loc found no unlocalized string on five screens (about 230 strings).
     - Double-length and AX5 hold, except US-319, which is already in the backlog and reproduced here on the iPhone 17.
     - Gaps, carried into `/release` item 5: the parameter editors and the iPad split.
     - The layout-direction test is skipped, because nothing reads `layoutDirection`. The positional-specifier lint isn't adopted: `AppStringsTests` already covers the literal parts.

## Verification at handover

- Every slice is mutation-checked and recorded. Slice 1 gets `swift-code-reviewer` and a Codex round when green. The PR gets the Codex handover loop (cap 5).
- **Brief review: done 2026-11-05** (1 High, 4 Medium, all adopted; journal). It covered the unpinned semantics: D3's events, stop and stitch limit, precedence, the error rule, and D2's trigger and oracle.
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
