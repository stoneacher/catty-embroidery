---
description: Session-end checklist — sync DECISIONS/ROADMAP/workflow-journal with this session and close out the current user story
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# /finish — close out the session

Work through this checklist against what actually happened in this session and the branch's diff (`git log --oneline main..HEAD`, `git diff main...HEAD --stat`). Update files only where reality requires it — never invent content to satisfy the checklist, and never tick a box you haven't verified.

## 1. Current user story

- Identify the story from the branch name (`US-<id>-<slug>` → `docs/user-stories/*/US-<id>-*.md`).
- For every acceptance criterion, verify it is actually met (tests, code, CI evidence) before ticking `[x]`. Leave unmet criteria unchecked and call them out in the report.
- If all criteria are met, mark the story done with a status line directly under the metadata line at the top:
  `**Status**: Done — YYYY-MM-DD, PR #<n>`
- **Prove it**: after editing, run `grep -n 'Status.*Done\|- \[' <story file>` and quote the Status line and ticked criteria verbatim in the step-8 report. A report without the quoted Status line is an incomplete /finish (US-110 was handed over unclosed on 2026-07-16 because this step left no visible trace — see the journal entry of that date).

## 2. docs/DECISIONS.md

- Did this session make a decision an ADR should pin — architecture, semantics, process-with-consequences — that isn't derivable from the code, or that contradicts an existing ADR? If yes, append an ADR in the established format (context → decision → consequences, newest at the bottom, next free number). Tooling fixes and story-scoped choices do **not** get ADRs.

## 3. docs/ROADMAP.md

- Any change to scope, milestones, epics, or engineering standards agreed this session? Reflect it. Otherwise leave the file untouched.

## 4. docs/workflow-journal.md

- Every notable workflow event of this session (delegation win/failure, new hook or rule, tool comparison, agent failure worth noting) has a dated entry in the template format. Add what's missing; keep entries short and factual — they are thesis data.

## 5. Manual Ink/Stitch verification callout

- Decide whether this story's changes affect anything a machine-readable check cannot fully vouch for: DST bytes (header, records, terminator), stitch geometry/interpolation, jump/color-change semantics, or export behavior.
- If yes, tell Sebastian **explicitly and prominently** that a manual check with the Inkscape embroidery plugin (Ink/Stitch) is needed: name the exact file or design to generate/open, and what to look for (e.g. stitch count, colors, physical size in mm, visual shape). Precedent: US-101's "empty" fixture renders — automated tests were green while only a viewer could confirm what a machine would actually sew.
- If no manual check is warranted, state that explicitly too ("no Ink/Stitch verification needed for this story — no DST/geometry output changed"). Never leave it unaddressed.

## 6. Cross-vendor Codex review

- Verify `/codex-review` ran for this branch and its verdict is recorded in the PR description (a "Codex review" section). If it hasn't run, run it now — the PR is not ready for handover without it. (The gh-pr-create hook reminds at creation time; this step catches branches whose PR predates the rule or where the reminder was missed.)

## 7. Ship it

- Engine tests green: `swift test` in `Packages/EmbroideryEngine`.
- Working tree clean: commit any doc updates (concise imperative message, no trailers), push, and watch CI to green (`gh pr checks <pr> --watch`).

## 8. Report

End with a short summary: per file — updated / already correct / nothing to record; the story's Status line **quoted verbatim from the file** (step 1's proof — not paraphrased); CI state; the Ink/Stitch verdict from step 5; the Codex review verdict from step 6; anything left open for the next session.
