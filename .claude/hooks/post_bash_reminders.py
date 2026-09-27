#!/usr/bin/env python3
r"""PostToolUse(Bash) reminders: push + watch CI after a commit, and when to run /codex-review.

Reads the hook payload on stdin and prints a `hookSpecificOutput.additionalContext` JSON object,
or nothing. Moved out of an inline `settings.json` one-liner on 2026-09-28 (PR #60) because the
inline version matched regexes against the *whole unparsed command*, and Codex round 2 showed
five misfires: `gh pr create -d` read as ready, a title containing "--draft" read as a draft,
`--draft;` missed, `env X=1 gh pr ready` missed, and `git commit -m "... gh pr ready"` read as a
ready PR. This version tokenises with `shlex` (quote-aware, with `;`/`&&`/`||`/`|` split out) and
classifies each command segment by its leading words, so quoted prose can never trigger a match.

Like ADR-023's commit gate, this is a convenience that matches command *text* — shell expansion
and unusual spellings can still slip past it. It is a reminder, not an enforcement boundary.
**Accepted limits** (Sebastian, 2026-09-28, closing PR #60's review loop after three Medium rounds
on this file): commands inside `( … )`, `$( … )` or backticks, or behind `sudo`/`command`/`exec`,
are not recognised, so their reminder is missed; and a word used as a redirection target (`>&git push`) is misread as a command, so a reminder can appear spuriously. Handled: quoting, `;`/`&&`/`||`/`|`/newlines,
`VAR=` and `env` prefixes, git's global options, `-d`/`--draft[=value]`, `--undo[=value]`,
`--dry-run`, heredoc bodies (dropped, so data never reads as a command), and `\`-newline
continuations. Any unexpected input is silent rather than a traceback.
"""

import re

import json
import shlex
import sys

CODEX_REMINDER = (
    "Project rule: run /codex-review (cross-vendor Codex review of this branch) now, triage its "
    "findings, and record the verdict in the PR before handing it over for merge."
)
MESSAGES = {
    "pr_ready_created": "A PR was just created. " + CODEX_REMINDER,
    "pr_draft_created": (
        "A draft PR was just opened, so CI now runs for this branch (ci.yml runs push on main "
        "only). Do not run /codex-review yet: it runs at handover, when the PR is marked ready "
        "with gh pr ready."
    ),
    "pr_marked_ready": "The PR was just marked ready for review. " + CODEX_REMINDER,
    "push": (
        "A git push just ran. Before treating this work as done: check the CI result for the "
        "pushed commit (gh run watch --exit-status <run-id>, or gh pr checks <pr> --watch) and "
        "report the outcome. If CI is red, investigate and fix before moving on."
    ),
    "commit": (
        "A git commit just ran. Project rule: push this commit to the remote now (git push) and "
        "watch the CI result, so problems surface immediately instead of piling up."
    ),
}

SEPARATORS = {";", "&&", "||", "|", "&", "\n"}
# git options that take a separate value, so the subcommand is the word after them.
GIT_VALUE_OPTIONS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}


HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def without_heredoc_bodies(command):
    """Drops every heredoc body, so text fed to `cat <<EOF` is never read as a command."""
    kept, terminators = [], []
    for line in command.split("\n"):
        if terminators:
            if line.strip() == terminators[0]:
                terminators.pop(0)
            continue
        kept.append(line)
        terminators.extend(match.group(2) for match in HEREDOC.finditer(line))
    return "\n".join(kept)


def segments(command):
    """The command split into simple commands, quotes respected."""
    command = without_heredoc_bodies(command.replace("\\\n", " "))
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=";&|")
    lexer.whitespace_split = True
    current = []
    for token in lexer:
        if token in SEPARATORS or set(token) <= set(";&|"):
            if current:
                yield current
            current = []
        else:
            current.append(token)
    if current:
        yield current


def strip_prefixes(words):
    """Drop leading `VAR=value` assignments and an `env [VAR=value ...]` wrapper."""
    index = 0
    while index < len(words) and "=" in words[index] and not words[index].startswith("-"):
        index += 1
    if index < len(words) and words[index] == "env":
        index += 1
        while index < len(words) and "=" in words[index] and not words[index].startswith("-"):
            index += 1
    return words[index:]


def git_subcommand(words):
    index = 1
    while index < len(words) and words[index].startswith("-"):
        index += 2 if words[index] in GIT_VALUE_OPTIONS else 1
    return words[index] if index < len(words) else None


def flag_is_set(arguments, *names):
    """Whether a boolean flag is on: bare (`-d`), or with a value (`--draft=true`, `-d=false`)."""
    on = False
    for argument in arguments:
        for name in names:
            if argument == name:
                on = True
            elif argument.startswith(name + "="):
                on = argument.split("=", 1)[1].lower() not in ("false", "0", "no")
    return on


def classify(command):
    """The set of events the command contains, in a stable order."""
    found = []
    try:
        parsed = [strip_prefixes(words) for words in segments(command)]
    except ValueError:
        # Unbalanced quotes: nothing trustworthy to classify; stay silent rather than guess.
        return found
    for words in parsed:
        if words[:3] == ["gh", "pr", "create"]:
            arguments = words[3:]
            if flag_is_set(arguments, "--help", "-h") or flag_is_set(arguments, "--dry-run"):
                continue
            draft = flag_is_set(arguments, "-d", "--draft")
            found.append("pr_draft_created" if draft else "pr_ready_created")
        elif words[:3] == ["gh", "pr", "ready"]:
            if not flag_is_set(words[3:], "--undo", "--help", "-h"):
                found.append("pr_marked_ready")
        elif words[:1] == ["git"]:
            sub = git_subcommand(words)
            if sub == "push":
                found.append("push")
            elif sub == "commit":
                found.append("commit")
    # A push supersedes the commit reminder, as the inline hook had it.
    if "push" in found:
        found = [event for event in found if event != "commit"]
    ordered = []
    for event in found:
        if event not in ordered:
            ordered.append(event)
    return ordered


def main():
    try:
        payload = json.load(sys.stdin)
        command = (payload.get("tool_input") or {}).get("command") or ""
        events = classify(command) if isinstance(command, str) else []
    except Exception:  # A reminder hook must never surface a traceback; missing one is fine.
        return
    if events:
        context = " ".join(MESSAGES[event] for event in events)
        print(json.dumps({
            "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": context}
        }))


if __name__ == "__main__":
    main()
