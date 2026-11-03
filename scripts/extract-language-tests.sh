#!/usr/bin/env bash
# Extracts the Catrobat Language Tests from a Catroid checkout into the engine's
# LanguageTestsTests fixtures (language-test-runner brief, D11).
#
#   scripts/extract-language-tests.sh <path-to-Catroid-checkout>
#
# For every catroid/src/androidTest/assets/catrobatTests/<path>.catrobat it writes
# <fixtures>/<path>/code.xml (the archive's code.xml, byte for byte) and one
# manifest.json naming the Catroid commit, each archive's and code.xml's SHA-256
# and the language version. The output is deterministic: entries are sorted and
# the JSON is written with sorted keys, so re-running on the same commit is a
# no-op in git. Fixtures for tests that no longer exist are removed.
#
# The checkout is only read. It must be clean, so the recorded commit is the
# commit the files actually came from.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <path-to-Catroid-checkout>" >&2
    exit 64
fi

catroid="$(cd "$1" && pwd)"
repo="$(cd "$(dirname "$0")/.." && pwd)"
assets_rel="catroid/src/androidTest/assets/catrobatTests"
out="$repo/Packages/EmbroideryEngine/Tests/LanguageTestsTests/Resources/catrobatTests"

if [[ ! -d "$catroid/$assets_rel" ]]; then
    echo "error: $catroid/$assets_rel not found; is this a Catroid checkout?" >&2
    exit 66
fi
if [[ -n "$(git -C "$catroid" status --porcelain -- "$assets_rel")" ]]; then
    echo "error: $assets_rel has local changes; extract from a clean checkout" >&2
    exit 65
fi

python3 -I - "$catroid" "$assets_rel" "$out" <<'PY'
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile

catroid, assets_rel, out = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
assets = catroid / assets_rel

def git(*args):
    return subprocess.run(["git", "-C", str(catroid), *args], check=True,
                          capture_output=True, text=True).stdout.strip()

version_pattern = re.compile(rb"<catrobatLanguageVersion>([^<]*)</catrobatLanguageVersion>")
entries = []
for archive in sorted(assets.rglob("*.catrobat")):
    rel = archive.relative_to(assets).as_posix()
    path = rel.removesuffix(".catrobat")
    with zipfile.ZipFile(archive) as zf:
        xml = zf.read("code.xml")
    match = version_pattern.search(xml)
    if match is None:
        sys.exit(f"error: {rel} has no catrobatLanguageVersion")
    target = out / path / "code.xml"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(xml)
    entries.append({
        "path": path,
        "zip": rel,
        "zipSHA256": hashlib.sha256(archive.read_bytes()).hexdigest(),
        "codeXMLSHA256": hashlib.sha256(xml).hexdigest(),
        "languageVersion": match.group(1).decode("utf-8"),
    })

# Remove fixtures whose test is gone, then any directories left empty.
keep = {e["path"] for e in entries}
for xml in out.rglob("code.xml"):
    if xml.parent.relative_to(out).as_posix() not in keep:
        xml.unlink()
for directory in sorted((p for p in out.rglob("*") if p.is_dir()), reverse=True):
    if not any(directory.iterdir()):
        directory.rmdir()

manifest = {
    "catroidCommit": git("rev-parse", "HEAD"),
    "assetsLastCommit": git("log", "-1", "--format=%H", "--", assets_rel),
    "assetsPath": assets_rel,
    "tests": entries,
}
(out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
print(f"extracted {len(entries)} tests from {manifest['catroidCommit'][:9]} into {out}")
PY
