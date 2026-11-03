# Provenance: Catrobat Language Tests

Every `code.xml` under this directory is the `code.xml` entry of a `.catrobat`
archive from the Catroid repository, copied **verbatim** (AGPL-3.0, © the
Catrobat Team, <https://github.com/Catrobat/Catroid>):

- source: `catroid/src/androidTest/assets/catrobatTests/<path>.catrobat`
- Catroid commit: recorded in `manifest.json` as `catroidCommit`
- last commit touching the assets: `assetsLastCommit`

`manifest.json` lists each test's path, the SHA-256 of its original archive and
of the extracted `code.xml`, and its `catrobatLanguageVersion`.
`FixtureProvenanceTests` checks the files against it.

Only `code.xml` is kept. The archives' other entries (images, sounds,
`permissions.txt`) are not needed by a headless runner.

Regenerate both, deterministically, with:

    scripts/extract-language-tests.sh <path-to-a-Catroid-checkout>

Do not edit a fixture by hand. A fixture that needs changing is a change to the
language tests themselves, which belongs upstream (see the language-test-runner
brief, "Out of scope").
