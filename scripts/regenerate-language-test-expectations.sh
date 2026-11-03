#!/usr/bin/env bash
# Regenerates the language-test runner's pinned expectations (brief D12) from the
# importer and runner, so the 215-entry table is never rebuilt by hand:
#
#   scripts/regenerate-language-test-expectations.sh
#
# Then review `git diff` on the table: every changed line is a test that changed
# class, and a new expected failure needs its owner (an ADR or backlog item) named.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
package="$repo/Packages/EmbroideryEngine"
table="$package/Tests/LanguageTestsTests/LanguageTestExpectations.swift"
output="$(mktemp)"
trap 'rm -f "$output"' EXIT

(cd "$package" && REGENERATE_LANGUAGE_TESTS=1 swift test --filter RegenerateExpectations) >"$output" 2>&1 || {
    echo "error: the generator failed; its output:" >&2
    cat "$output" >&2
    exit 1
}
generated="$(sed -n '/^BEGIN LanguageTestExpectations.swift$/,/^END LanguageTestExpectations.swift$/p' "$output" | sed '1d;$d')"
if [[ -z "$generated" ]]; then
    echo "error: no table in the generator's output" >&2
    exit 1
fi
printf '%s\n' "$generated" >"$table"
echo "wrote $table"
