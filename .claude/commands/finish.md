---
description: Session-end checklist — sync DECISIONS/ROADMAP/workflow-journal with this session and close out the current feature (or the session's slice of it)
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# /finish — close out the session

Work through this checklist against what actually happened in this session and the branch's diff (`git log --oneline main..HEAD`, `git diff main...HEAD --stat`). Update files only where reality requires it — never invent content to satisfy the checklist, and never tick a box you haven't verified.

A feature usually spans several sessions (ADR-041). Run this at the end of every session; steps 1, 5 and 6 only apply in full at the session that hands the feature over.

## 1. Feature brief

- Identify the feature from the branch name (`feature/<slug>` → `docs/features/<slug>.md`).
- Tick each acceptance criterion that is **verified** met (tests, code, CI or simulator evidence). Leave the rest unchecked.
- **At handover only**: if every criterion is met, set the brief's status line to `**Status**: Done — YYYY-MM-DD, PR #<n>` and prove it in the report:
  - `grep -n '^\*\*Status\*\*: Done' <brief>` — quote the output verbatim.
  - `grep -n '^- \[ \]' <brief>` — must print nothing.
  A brief that is closed without this proof is not closed (precedent: US-110, 2026-07-16).
- Mid-feature: report which criteria were ticked this session and what is next.

## 1b. Slice quality gates

For every slice finished this session, verify — and list in the report — that:
- its tests were seen red before the implementation;
- it was **mutation-checked** (ADR-032 invariant 2): name the mutations tried and confirm each turned a test red; a surviving mutant is either killed by a new test or recorded with a reason;
- if it was a **risky slice** (DST bytes, engine, interpreter, program format), its `swift-code-reviewer` pass and Codex slice round ran and are recorded in the PR.

Also check the PR's size: `git diff main...HEAD --stat -- . ':(exclude)*Tests*'`. Past roughly 1,500 lines of non-test code, say so and propose where to split.

## 2. docs/DECISIONS.md

- Did this session make a decision an ADR should pin — architecture, semantics, process-with-consequences — that isn't derivable from the code, or that contradicts an existing ADR? If yes, append an ADR (context → decision → consequences, next free number, roughly 20 lines; review history goes in the journal) **and add its row to the index at the top**. If it amends or supersedes an older ADR, update that ADR's `**Status**` line and its index row, and mark any sentence it overrules inline. Tooling fixes and choices local to one slice do **not** get ADRs.

## 3. docs/ROADMAP.md

- Update the feature's row in the feature table (status, PR). Scope or standards changes agreed this session go in too; otherwise leave the file alone.

## 4. docs/workflow-journal.md

- The journal is exhaustive thesis data: every notable workflow event of this session (delegation win/failure, review round, new hook or rule, tool comparison, defect found by a surprising route, agent failure) is recorded. Group events into as many dated entries as make sense — one for a quiet session, several when distinct things happened — and write each so it reads on its own. Append-only.

## 5. Manual Ink/Stitch verification callout

- Did the feature change anything a machine check cannot fully vouch for: DST bytes, stitch geometry/interpolation, jump/color-change semantics, export behavior, or a new path by which a design reaches the writer? If yes, tell Sebastian **explicitly** that an Ink/Stitch check is needed: which design to build or export, and what to look for (stitch count, colors, size in mm, shape). If no, say so explicitly. Never leave it unaddressed.

## 6. Cross-vendor Codex review (handover only)

- Verify `/codex-review` ran and its verdict, with each round's highest severity, is in the PR description. If not, run it now. Cap: 5 rounds (ADR-041).

## 7. Ship it

- Engine tests green (`swift test` in `Packages/EmbroideryEngine`); app builds if app code changed.
- Commit doc updates (stage explicit paths), push, and watch CI to green (`gh pr checks <pr> --watch`).

## 8. Report

Short summary: per file — updated / already correct / nothing to record; step 1's state (or proof at handover); CI state; Ink/Stitch verdict; Codex verdict (at handover); what the next session picks up.
