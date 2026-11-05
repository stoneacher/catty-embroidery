# EditorCoreTests resources

## `FrozenV1.json`: the program format v1, frozen

US-331, ADR-037 amendment of 2026-11-05. These are the exact bytes `ProgramDocument.encode` writes for `FrozenV1.program` (`FrozenV1Program.swift`), a program holding every case of the v1 vocabulary. It puts a nested formula in every formula slot, every JSON escape class in its strings, and default-valued fields beside non-default ones. `FrozenV1VocabularyTests` requires:
- the encoder to reproduce the bytes exactly;
- the bytes to decode back to the same program;
- the decoded program to re-encode to the same bytes.

**Never regenerate or hand-edit this file for a format change.** If a change makes the test red, it changes what v1 bytes look like, and a build already in someone's hands would misread the result.

**The one exception is a presentation-only difference.** A newer Foundation may spell the same JSON values differently (spacing, number spelling), and the test's failure message says whether the difference is presentation only. Only then may the fixture be replaced, in its own journaled, reviewed commit that quotes that message. Any other difference is a format change. Such a change is a format v2: bump `Program.currentFormatVersion` and build ADR-037's admission operations. The new version gets its own frozen fixture beside this one, and this file stays as the v1 reader's contract.
