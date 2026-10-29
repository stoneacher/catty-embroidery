#!/usr/bin/env python3
"""Summarise one US-316 capture trace (docs/us-316-device-handoff.md, brief D6/D9).

Usage: python3 -I scripts/us316_trace_summary.py <run.trace> [<run.trace> ...]

For each trace, prints the run's own result line (the `result` Points-of-Interest event the app
emits) and what the Animation Hitches trace saw **inside the `capture` signpost window**:
the hitch count, the hitches over 33.3 ms and the worst hitch, plus per-interval CPU totals for
the stage's signposts (plan, segmentPath, stroke, dotPath, fill).

`xctrace export` writes each repeated value once with an `id` and refers back to it with `ref`
(us309-device-handoff.md, note 4); a parser that ignores the refs silently drops most rows'
durations. Every element is resolved through the id table here.
"""

import json
import subprocess
import sys
import xml.etree.ElementTree as ET

DROPPED_FRAME_NS = 33.3e6
STAGE_INTERVALS = ("plan", "segmentPath", "stroke", "dotPath", "fill")


def export(trace, schema):
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    out = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
        capture_output=True, text=True, check=True,
    ).stdout
    return ET.fromstring(out)


def rows(root):
    """Yield each row as {mnemonic: (text, fmt)}, refs resolved."""
    node = root.find("node")
    if node is None:
        return
    schema = node.find("schema")
    mnemonics = [col.findtext("mnemonic") for col in schema.findall("col")]
    seen = {}

    def resolve(element):
        ref = element.get("ref")
        if ref is not None:
            return seen[ref]
        value = ("".join(element.itertext()), element.get("fmt"))
        if element.get("id") is not None:
            seen[element.get("id")] = value
        # Nested ids (e.g. a pid inside a process) are registered too, so later refs resolve.
        for child in element.iter():
            if child is not element and child.get("id") is not None and child.get("id") not in seen:
                seen[child.get("id")] = ("".join(child.itertext()), child.get("fmt"))
        return value

    for row in node.findall("row"):
        cells = [resolve(cell) for cell in row if cell.tag != "sentinel"]
        yield dict(zip(mnemonics, cells))


def number(cell):
    return int(cell[0]) if cell and cell[0].strip().lstrip("-").isdigit() else None


def summarise(trace):
    intervals = list(rows(export(trace, "OSSignpostIntervals")))
    captures = [r for r in intervals if r.get("name", ("",))[0] == "capture"]
    if len(captures) != 1:
        return {"trace": trace, "error": f"{len(captures)} capture windows"}
    start = number(captures[0]["start"])
    end = start + number(captures[0]["duration"])

    inside = []
    for hitch in rows(export(trace, "hitches")):
        at = number(hitch["start"])
        if start <= at <= end:
            inside.append(number(hitch["duration"]))

    stage = {}
    for name in STAGE_INTERVALS:
        durations = [
            number(r["duration"]) for r in intervals
            if r.get("name", ("",))[0] == name and start <= number(r["start"]) <= end
        ]
        stage[name] = {
            "count": len(durations),
            "total_ms": round(sum(durations) / 1e6, 3),
            "max_ms": round(max(durations) / 1e6, 3) if durations else 0,
        }

    events = list(rows(export(trace, "PointsOfInterestEvents")))
    lines = [
        cell[0] for event in events for cell in event.values()
        if cell and cell[0] and cell[0].startswith("US316 ")
    ]
    return {
        "trace": trace,
        "result": lines[0] if lines else None,
        "window_s": round((end - start) / 1e9, 3),
        "hitches": len(inside),
        "hitches_over_33ms": sum(1 for d in inside if d > DROPPED_FRAME_NS),
        "worst_hitch_ms": round(max(inside) / 1e6, 3) if inside else 0,
        "stage_intervals": stage,
    }


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(json.dumps(summarise(path)))
