---
description: Release checklist — run before every build that leaves the developer's devices (TestFlight or App Store): format freeze, metadata, icon, localization/RTL pass, accessibility review, drift check, Release compile, upload
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# /release — before a build leaves the developer's devices

Run this before **every** build that someone else will install (TestFlight, App Store, an ad-hoc build for a usability session). It exists because the format freeze was once handed to "a release checklist" that did not exist (US-331, ADR-037's 2026-11-05 amendment). A rule that is only remembered gets missed at exactly this moment.

Work through the items in order. **Never tick an item you haven't verified this run.** Each item says whether it is machine-checked (run it and quote the output), Claude-run (do it and attach the evidence), or human (ask Sebastian and record his answer). End with the report in step 12.

## 1. Format freeze (machine): first, always

- `cd Packages/EmbroideryEngine && swift test --filter FrozenV1VocabularyTests` must pass. Quote the summary line.
- No commit may touch `Packages/EmbroideryEngine/Tests/EditorCoreTests/Resources/FrozenV1.json` after the freeze, the merge of the Release readiness PR (ADR-037, 2026-11-05 amendment). Find that merge with `git log --oneline --grep '#90' main` (the PR number holds whether it was merged with a merge commit or squashed), then check that `git log --oneline <that merge>..main -- <the fixture>` prints nothing. Any output means the frozen bytes were replaced. That is lawful only as a presentation-only replacement (ADR-037, 2026-11-05 amendment): its commit must quote the test's "presentation only" message and have a journal entry. Anything else un-freezes v1, so stop the release and raise it.
- **On the first release only:** if ADR-037's 2026-11-05 amendment doesn't yet name the freeze's merge commit and date, add them now. Release readiness carried this here, because the date doesn't exist before the merge.
- If `Program.currentFormatVersion` is above 1, check that ADR-037's three admission operations exist and that each version has its own frozen fixture.

## 2. Version numbers (human, in Xcode)

- `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in the pbxproj, which Claude never edits. Ask Sebastian to bump them in Xcode, and record the new values.

## 3. Release metadata (machine)

- The app's `ReleaseMetadataTests` must pass: the privacy manifest is in the bundle with the declared contents, and `ITSAppUsesNonExemptEncryption` is false.
- **Re-grep the required-reason APIs** in release code, because DEBUG-only timing code can leave its `#if DEBUG`. Release code lives in **both** `catrobat_embroidery_ios/catrobat_embroidery_ios/` and `Packages/EmbroideryEngine/Sources/`; the declared uses are in the package's `Projects` target. Grep for:
  - `UserDefaults`;
  - file timestamps and metadata: `creationDate`, `modificationDate`, `contentModificationDate`, `fileModificationDate`, `attributesOfItem`, `stat(`, `fstat(`, `getattrlist`;
  - boot time: `systemUptime`, `mach_absolute_time`, `CACurrentMediaTime`;
  - disk space: `volumeAvailableCapacity`, `systemFreeSize`, `statfs`;
  - `activeInputModes`.

  Any hit outside `#if DEBUG` that the manifest doesn't declare blocks the release (ADR-011 amendment).

## 4. App icon (Claude-run)

- The icon is `AppIcon.icon`, an Icon Composer file (Release readiness D5, as reversed on 2026-11-07).
- Build and install on the simulator, then screenshot the home screen. Switch appearance with long-press › Edit › Customize: light, dark and tinted. The icon must show in all three, with the label "Embroidery".
- **On the first release, and after any Xcode upgrade,** run once on an iOS 17 or 18 simulator as well. There the icon comes from the flat images Xcode generates from the `.icon`, not from the `.icon` itself.
- **Haptics, on a device:** a palette add ticks once, a reorder drop ticks, a finished run gives success, and run start and a user stop give nothing (ADR-052). **On the first release, also on an iPad with two windows:** only the window acted in gives feedback. Release readiness carried this check here, because no iPad was at hand.

## 5. Pseudo-localization and RTL pass (Claude-run)

Launch with each argument set (XcodeBuildMCP or `simctl launch … --`), and screenshot every screen listed below, on iPhone (compact) and iPad (regular split):
- **(a)** `-NSSurroundLocalizedStrings YES`: every localized string shows `[# … #]`.
  - Dump the hierarchy (`snapshot_ui`) and grep for labels and values without `[#`.
  - User content (design names, variable names, formula text) is excluded.
  - Anything else is an unlocalized string, and a clipped bracket means truncation.
- **(b)** `-NSDoubleLocalizedStrings YES`: string length and layout.
- **(c)** `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`: RTL.
- **(d)** (c) at the AX5 Dynamic Type size.

Screens:
- the project list (empty, filled, and with a refused-file badge);
- the script list with control blocks;
- the palette;
- each parameter editor (number, comparison, colour grid, variable menu);
- the stage (idle, running, finished);
- the export row in every reachable state;
- the autosave banner and the refusal alert.

**RTL pins:**
- **The stage never mirrors.** That covers the canvas, the pinch/pan, and the directional pan actions (ADR-007).
- Script indentation and leading icons do mirror.
- Formula text stays left-to-right.

Every finding is fixed or tracked before upload.

**Known limits of these flags** (first run, 2026-11-07). Don't file these as defects:
- **(a) and (b) break format strings before substitution.** Rows with a plural variant render as `[# %#@value@ #]`. Doubled positional formats render as `1$@ × 2$@`, and a title as `@ Design Design`. Normal runs render all of them correctly. Plural resolution itself is covered by `AppStringsTests`.
- **The app's own name** comes from `InfoPlist.strings`, which (a) doesn't bracket, so "Embroidery" shows unbracketed.
- **(b) persists doubled defaults:** a new design created during the run is saved under a name like "Design Design". Use a throwaway simulator, or delete it afterwards.
- **At AX5 the examples sit below the fold:** scroll the project list before tapping a sample.
- **The parameter editors and the iPad split** were not reached on 2026-11-07. Cover them on the first release run.
- **Known and tracked:** US-319 (the stage's name field squeezed out at AX4–AX5). It is below the AX1 bar, so not a release blocker.

## 6. Pre-beta manual accessibility review (human-led): first release only, then when a release adds a screen

The review ADR-041's 2026-10-17 amendment parked until "before beta". It covers:
- VoiceOver on every screen;
- Dynamic Type up to AX5;
- Reduce Motion;
- keyboard and Switch Control reachability;
- the questions each feature brief listed for it. Collect them with `grep -rn "pre-beta" docs/features/`.

Record the findings in the journal, and fix or track each one.

## 7. Knowledge-graph drift check (Claude-run)

- `/graphify . --update`, then triage every `semantically_similar_to` edge with a document endpoint (ADR-041, 2026-10-17 and 2026-10-28 amendments). The step is done when those edges are triaged, not when the tool has run. Journal the outcome, including "none, N edges triaged".

## 8. Release-configuration compile (machine)

- `release-build.yml` is the only gate that compiles with `DEBUG` undefined. It runs on pull requests and **tag pushes**, not on pushes to `main`. A dry run on 2026-11-05 caught an earlier version of this item asking for a `main` run that cannot exist.
- So tag the commit being archived, push the tag, and watch it:
  - `git tag release/v<version>-<build> <commit>`
  - `git push origin release/v<version>-<build>`
  - `gh run list --workflow release-build.yml --limit 1`, then `gh run watch <id> --exit-status`

  The tag also records exactly what was uploaded. Creating and pushing the tag is outward-facing, so confirm it with Sebastian first.

## 9. Archive and upload (human)

- Sebastian archives in Xcode and uploads under Catrobat's Apple developer team, with bundle ID `org.catrobat.embroiderydesigner` (Release readiness D6). Record who uploaded, the team, the version and the build number.

## 10. App Store Connect (human)

- App Privacy: **Data Not Collected**, no tracking (ADR-011).
- Age rating questionnaire: expected **4+**; **not** in the Kids Category.
- A privacy-policy URL: Catrobat's.
- Export compliance: no non-exempt encryption, consistent with the Info.plist key.

## 11. Record

- A journal entry for the release: the version, each item's result, and anything waived and by whom.
- After the **first** release, check that ADR-037's freeze amendment still matches what happened.

## 12. Report

Per item: verified (with the evidence), waived (by Sebastian, with the reason), or blocked. The release goes ahead only when items 1, 3 and 8 are verified and nothing is blocked.
