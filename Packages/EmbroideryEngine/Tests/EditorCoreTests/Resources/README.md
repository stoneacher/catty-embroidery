# EditorCoreTests resources

## `FrozenV1.json`: the program format v1, frozen

US-331, ADR-037 amendment of 2026-11-05. These are the exact bytes `ProgramDocument.encode` writes for `FrozenV1.program`, a program holding every case of the v1 vocabulary (`FrozenV1VocabularyTests.swift`). The test requires the encoder to reproduce them byte for byte, and requires them to decode back to the same program.

**Never regenerate or hand-edit this file.** If a change makes the test red, it changes what v1 bytes look like, and a build already in someone's hands would misread the result. Such a change is a format v2: bump `Program.currentFormatVersion` and build ADR-037's admission operations. The new version gets its own frozen fixture beside this one, and this file stays as the v1 reader's contract.
