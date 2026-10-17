#!/usr/bin/env bash
# Brick dispatch probe (Brick backend, slice 0).
#
# Proves that every package site dispatching over `Brick` is an exhaustive
# switch: a copy of the package gets a temporary `Brick.dispatchProbe` case, and
# the compiler's "switch must be exhaustive" diagnostics are asserted *by file*
# against the expected site list below. A site that regains a swallowing
# `default:` drops out of the diagnostics, and the probe fails naming it. A bare
# "the probe does not compile" check could not tell: the other sites keep it red.
#
# Modules are built one at a time, because errors in `ProgramModel` stop its
# dependents from compiling: stage 1 checks ProgramModel's own site, then patches
# it so stages 2 and 3 can check Interpreter and EditorCore.
#
# Not part of `swift test` (spawning SwiftPM there deadlocks on its build lock,
# US-401) and not in CI: it is the evidence for a refactor, re-run when the
# dispatch sites change. Usage: scripts/brick-dispatch-probe.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rsync -a --exclude .build "$repo_root/Packages/EmbroideryEngine/" "$work/pkg/"
cd "$work/pkg"

# Insert the probe case after the last Brick case; fail loudly if the anchor moved.
insert_after() { # file anchor line
    grep -qF "$2" "$1" || { echo "probe: anchor not found in $1: $2" >&2; exit 2; }
    awk -v anchor="$2" -v line="$3" '{ print } index($0, anchor) { print line }' "$1" >"$1.new"
    mv "$1.new" "$1"
}
insert_after Sources/ProgramModel/Brick.swift \
    "case writeEmbroideryToFile(name: String)" "    case dispatchProbe"

failures=0

# Builds one target and compares its exhaustiveness diagnostics, per file,
# with the expected list ("File.swift" entries, one per expected site).
check() { # target expected-file...
    local target="$1"; shift
    local log="$work/$target.log"
    # Release builds whole-module: one frontend type-checks every file, so a
    # failing file cannot stop the build system from compiling the next site.
    # (`-Xswiftc -wmo` is refused by SwiftPM's build system.)
    swift build -c release --target "$target" >"$log" 2>&1 && {
        echo "probe: $target compiled with dispatchProbe — no exhaustive site at all" >&2
        failures=$((failures + 1)); return
    }
    local actual expected
    actual="$(sed $'s/\x1b\\[[0-9;]*m//g' "$log" \
        | { grep -E '\.swift:[0-9]+:[0-9]+: error: switch must be exhaustive' || true; } \
        | sed -E 's|^.*/([^/]+\.swift):([0-9]+):[0-9]+:.*$|\1:\2|' | sort -u \
        | sed -E 's|:[0-9]+$||' | sort | uniq -c | sed -E 's/^ +//')"
    expected="$(printf '%s\n' "$@" | sort | uniq -c | sed -E 's/^ +//')"
    if [[ "$actual" == "$expected" ]]; then
        echo "probe: $target ok"
        printf '%s\n' "$actual" | sed 's/^/    /'
    else
        echo "probe: $target MISMATCH" >&2
        echo "  expected (count file):" >&2; printf '%s\n' "$expected" | sed 's/^/    /' >&2
        echo "  actual (count file):" >&2; printf '%s\n' "${actual:-<none>}" | sed 's/^/    /' >&2
        echo "  last build lines:" >&2; tail -n 5 "$log" | cut -c1-200 | sed 's/^/    /' >&2
        failures=$((failures + 1))
    fi
}

check ProgramModel Script+PairedControl.swift

# Handle the probe in ProgramModel so its dependents can compile.
insert_after Sources/ProgramModel/Script+PairedControl.swift \
    "case .repeatLoop, .forever: true" "        case .dispatchProbe: false"

check Interpreter Instruction.swift VirtualNeedle+Brick.swift Interpreter+Step.swift
# BrickParameter's `replacing(_:with:)` switches over a (brick, slot, value)
# triple, where `default:` is the only total answer (ADR-035); its one expected
# diagnostic is `parameters`, the exhaustive switch above it.
check EditorCore BrickKind.swift BrickParameter.swift ProgramDocument.swift

if ((failures > 0)); then
    echo "probe: $failures target(s) failed" >&2
    exit 1
fi
echo "probe: every Brick dispatch site is exhaustive"
