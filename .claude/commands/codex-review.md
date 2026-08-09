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

Use plain `codex exec` (not the `review` subcommand — it rejects a custom prompt combined with `--base`) and put the diff scope in the prompt.

**Redirect stdin from `/dev/null`, and keep the prompt in a file.** Two traps, both found the hard way in US-209 (2026-07-31):

1. `codex exec` reads stdin *even when the prompt is passed as an argument* — it prints "Reading additional input from stdin..." and blocks. In the Bash tool's background mode stdin is an open pipe that never reaches EOF, so the run hangs **forever at 0% CPU with no session log**, looking exactly like a slow review. Two runs were lost to this (~20 min and ~2 min) before the cause was found. `< /dev/null` is the whole fix. A foreground smoke test does *not* reproduce it, because there stdin gets immediate EOF — so "codex works fine" is not evidence against this.
2. Do not pipe the command through `tail`: it buffers all output until the process exits, so the log stays empty and a hang is indistinguishable from progress. (`head` does *not* buffer — it prints and exits immediately — but avoid it too, since it truncates the log and can kill the producer via SIGPIPE. Corrected in round 2 after an earlier version of this file gave `head` the wrong failure mechanism.) Let it stream, and `Read` the task output file to check on it.

Prompts are long and contain backticks; write the prompt to a file and pass `"$(cat …)"` rather than inlining it. Put that file in **this session's scratchpad directory** — the absolute path is given in the system prompt; do not use `/tmp` or the repo. Set a shell variable for it in the same command, since nothing defines one for you:

```
SCRATCH="<the session scratchpad path from the system prompt>"
# … write the prompt to "$SCRATCH/codex-prompt.txt" …
codex exec -s read-only -C "$PWD" -o /tmp/codex-review-verdict.md \
  "$(cat "$SCRATCH/codex-prompt.txt")" < /dev/null
```

With `SCRATCH` unset this silently reads `/codex-prompt.txt` and the review dies before Codex starts (Codex US-209 round 2 found exactly that hole in this file).

The prompt file's content (adapt the rubric per story):

```
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

## 5. Verification round — re-review whenever the triage changed the branch

If any finding led to commits on the branch (code *or* docs/ADR changes), run Codex again after those fixes land (adopted 2026-07-13 after US-108, where the re-round caught a divergence in the very line added to satisfy round 1). If every finding was rejected as invalid and nothing changed, skip this — there is nothing to verify.

Same invocation shape, output to `/tmp/codex-review-verdict-2.md` (increment per round), but restructure the prompt:
1. **List each prior finding with the claimed fix** (file:line, one sentence) and ask Codex to FIRST verify each fix is correct and complete — explicitly including whether the fix *itself* introduces new divergence from the pinned Catroid semantics or new edge cases.
2. THEN hunt adversarially for anything new in the current `git diff main...HEAD`, same rubric and exclusions as step 2.
3. End with: "If everything holds, say so explicitly."

Triage per step 3, then append a **Codex round N** section to the PR verdict (prior findings confirmed-fixed or not, new findings + triage) and a journal entry for the round's outcome.

**Stop condition** — the loop ends when **either** holds:

1. **This round's triage produced no *code* changes.** Rejected findings and doc/comment-only corrections end the loop.
2. **Severity has fallen for two consecutive rounds.** Take the highest severity in each round: two successive strict decreases (e.g. High → Medium → Low, or High → Medium → clean) means the loop is converging and the remaining findings are not the kind that ship defects. A flat run — High → High, or Medium → Medium — is **not** convergence and does not stop the loop, however many rounds have passed.

**Hard cap: 10 rounds.** At 10, stop and escalate to Sebastian rather than continuing. Also escalate *early*, without waiting for the cap, if severity has been flat or rising for three rounds — that pattern means the loop is not converging and more rounds are unlikely to fix it on their own.

**Record, every round**: the round's highest severity and whether it produced code changes. The stop condition is now a function of that history rather than a count, so the history has to be written down — the PR verdict section and the journal entry are where it goes.

### Why this replaced a fixed count (2026-08-09, US-302)

The cap was 3, then 5, and both were wrong in the same way: a fixed count is a proxy for convergence, and it stops the loop on the wrong axis.

- **US-108** converged in two rounds (High → Medium-no-code-bugs) — a count of 5 would have wasted three rounds.
- **US-207** was a **test-only** story and stayed flat (Medium → Medium → Medium), each round finding a real gap in the *previous round's fix*. It hit the cap while still producing findings; the last round's fixes reached handover verified only by self-authored mutation tests. (That is why the cap went 3 → 5 on 2026-07-25.)
- **US-302** ran Medium → High → High → High → High/Medium → **High** → **Medium**, and 21 findings across the eight rounds, none rejected. It hit the 5-round cap *one round before its most valuable finding*: round 6 caught that round 5's "fix" had **lowered the standard** — I concluded an overflow was unfixable, weakened the documented contract, and wrote the failure into a characterisation test, converting a bug into a specification. Round 7 then found a gap in round 6's fix, and severity finally fell.

Two things follow. **Severity trend beats round count** as a convergence signal: US-302's first genuine downward move came at round 7, and no count short of that would have found the round-6 defect. And **expect slower convergence when the diff is test code or numerically hostile code** — every new assertion is itself new surface, and a function over an unbounded input domain (`Double`, coordinates) has far more places to hide than byte-semantics work does. Extra rounds are cheap next to a golden that silently stops discriminating, or a defect written into a test as if it were intended.

**US-302 was then run to the rule, and it is the first branch the rule closed.** An earlier version of this paragraph noted that its round 7 (High → Medium, one decrease, code changed) did *not* satisfy the stop condition and that the loop should continue. It did: **round 8 returned no findings at all**, ending the loop on condition 1 — the first clean round on the branch, after seven consecutive rounds that each produced valid findings.

That is the cleanest available evidence for the change. Under the old fixed cap the branch would have been handed over at round 5 with a High-severity defect still latent (the round-6 characterisation test that had converted a bug into a specification) and no clean round anywhere in its history. Under this rule it ran three more rounds, found two further real defects, and terminated on a genuine signal instead of an arbitrary count.

Final shape: **8 rounds, 21 findings, none rejected**, severity Medium → High → High → High → High/Medium → High → Medium → **none**.

The 10-round ceiling exists so a genuinely pathological branch escalates to a human instead of looping indefinitely; it is not a target.

The PR is ready for handover only after the final round's verdict is recorded and its CI is green.
