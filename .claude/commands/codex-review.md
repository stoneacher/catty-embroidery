---
description: Cross-vendor Codex review of the current branch — adversarial semantics pass, complementary to swift-code-reviewer
allowed-tools: Read, Edit, Bash, Grep, Glob
---

# /codex-review — independent cross-vendor review

Run OpenAI Codex as the second, independent reviewer of the current story branch. This deliberately does **not** repeat the swift-code-reviewer checklist (idiom, concurrency, HIG) — Codex's value is a different model with different blind spots, pointed at what matters most here: the byte-level semantics. Do not skip this because the in-loop review was clean; the two reviews look in different places.

## 1. Check the binary

`codex --version` — if missing or logged out, stop and tell Sebastian (install via Homebrew; `codex login` is interactive, suggest he types `! codex login`).

## 2. Run the review (read-only, non-interactive, in the background)

Run from the repo root against the branch's diff vs `main`. Use the Bash tool's background mode — a review takes minutes; watch for the completion notification instead of polling.

Use plain `codex exec` (not the `review` subcommand — it rejects a custom prompt combined with `--base`) and put the diff scope in the prompt:

```
codex exec -s read-only -C "$PWD" -o /tmp/codex-review-verdict.md \
  "Review the changes shown by \`git diff main...HEAD\` (run it yourself; also read the touched files for context). You are the independent cross-vendor reviewer for a Swift 6 embroidery engine that emits Tajima DST files. Byte-level semantics are pinned in docs/DECISIONS.md (ADR-012 and ADR-013) — read them first; they are the arbiter, not your priors. Focus adversarially on semantics and correctness: try to construct concrete inputs (stage coordinates, color changes, jumps, boundary values) where the changed code produces wrong DST bytes, diverges from the pinned Catroid semantics, or violates an ADR. Also name test blind spots: real failure modes the suite cannot catch. Do NOT comment on style, formatting, naming, or architecture taste — a separate reviewer covers those. For each finding: severity, file:line, a concrete reproducing input, and why the ADRs say it is wrong."
```

For a workflow/tooling-only diff (no engine code), swap the rubric focus to the automation itself: hook shell-quoting/JSON-escaping bugs, matcher false positives/negatives, documented-command invocation errors, and contradictions with existing project docs.

## 3. Triage — the ADRs are the arbiter

For each finding in `/tmp/codex-review-verdict.md`:
- Verify it against ADR-012/013 and, where cheap, against the reference implementations. A finding that contradicts a pinned decision is **invalid** — note it as such, do not "fix" it.
- Valid findings: fix in-scope ones on the branch (normal commit/push/CI flow); track out-of-scope ones explicitly (journal + PR note), like the ±121 boundary-trap precedent.

## 4. Record the verdict

- Append a short **Codex review** section to the PR description (`gh pr view <n> --json body`, append, `gh pr edit <n> --body-file`): findings count, what was fixed, what was rejected-with-reason, what is tracked.
- Journal a delegation entry in `docs/workflow-journal.md` (thesis data): what Codex found that the in-loop review didn't, and vice versa.

The PR is ready for handover only after this verdict is recorded.
