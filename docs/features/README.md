# Feature briefs

From 2026-10-09 the unit of work is a **feature**, not a ≤ 5 h user story ([ADR-041](../DECISIONS.md)). One feature = one branch (`feature/<slug>`), one PR, one review cycle. Its brief lives here as `<slug>.md`. The story files under [`user-stories/`](../user-stories/) stay as the record of M1–M4 and are still cited by ADRs and the journal.

A brief is short on purpose. When the feature's semantics are not already pinned by ADRs or a reference, the brief gets one Codex round before any test is written (ADR-041). It says what "done" means and in what order to prove it, not how long it will take. Detailed design goes in ADRs where it pins a decision, and otherwise in the code and tests.

## Template

```markdown
# <Feature name>

**Status**: Planned — YYYY-MM-DD | **Epic**: E<n> | **Branch**: `feature/<slug>`

**Goal**: one paragraph — what the user can do afterwards that they cannot do now.

**In scope / out of scope**: bullets. Name anything deliberately left for a later feature.

## Acceptance criteria

- [ ] Observable, verifiable outcomes. Properties ("every X …") where the claim is about everything the user can do.

## Slices and test-first outline

Ordered slices, each red → green on its own. Per slice: the tests that go red first, the ADRs they encode, whether it is **risky** (DST bytes, engine, interpreter, program format → reviewer + one Codex round when green), and the mutations that must turn its tests red.

1. **<slice>** (risky: yes/no) — tests: … — mutations: …

If the slices add up to more than ~1,500 lines of non-test code, group them into PRs here.

## Verification at handover

- Every slice mutation-checked and recorded; risky slices reviewed when green.
- Simulator screenshots (UI), manual accessibility pass, Ink/Stitch check if DST output or its provenance changed, Codex loop (cap 5).

## References

ADRs, reference-repo files (`Catroid/...:line`), predecessor stories.
```
