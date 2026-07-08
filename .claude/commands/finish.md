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

## 2. docs/DECISIONS.md

- Did this session make a decision an ADR should pin — architecture, semantics, process-with-consequences — that isn't derivable from the code, or that contradicts an existing ADR? If yes, append an ADR in the established format (context → decision → consequences, newest at the bottom, next free number). Tooling fixes and story-scoped choices do **not** get ADRs.

## 3. docs/ROADMAP.md

- Any change to scope, milestones, epics, or engineering standards agreed this session? Reflect it. Otherwise leave the file untouched.

## 4. docs/workflow-journal.md

- Every notable workflow event of this session (delegation win/failure, new hook or rule, tool comparison, agent failure worth noting) has a dated entry in the template format. Add what's missing; keep entries short and factual — they are thesis data.

## 5. Ship it

- Engine tests green: `swift test` in `Packages/EmbroideryEngine`.
- Working tree clean: commit any doc updates (concise imperative message, no trailers), push, and watch CI to green (`gh pr checks <pr> --watch`).

## 6. Report

End with a short summary: per file — updated / already correct / nothing to record; story status; CI state; anything left open for the next session.
