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
import re
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
    events = list(rows(export(trace, "PointsOfInterestEvents")))
    lines = [
        (number(event.get("time") or event.get("start")), cell[0])
        for event in events for cell in event.values()
        if cell and cell[0] and cell[0].startswith("US316 ")
    ]
    window_source = "capture interval"
    if len(captures) == 1:
        start = number(captures[0]["start"])
        end = start + number(captures[0]["duration"])
    elif not captures and lines:
        # Fallback, seen on a hand run (2026-10-29): only the interval's End reached the trace.
        # The result event is emitted at the Stop, right after that End, and the result line
        # carries the recorder's own window length (one decimal), so the window is
        # [result − window, result]. Marked in the output, never silent.
        end = lines[0][0]
        seconds = re.search(r" · ([0-9.]+) s · ", lines[0][1])
        if end is None or seconds is None:
            return {"trace": trace, "error": "no capture window and no usable result line"}
        start = end - int(float(seconds.group(1)) * 1e9)
        window_source = "result line (capture Begin missing)"
    else:
        return {"trace": trace, "error": f"{len(captures)} capture windows"}

    # The recorder keeps a trailing window of what it records (2026-10-29): in a long
    # recording, the oldest data — signposts *and* display events — falls out. The earliest
    # vsync in the trace is where its continuous display data begins; a capture window that
    # starts before it is not covered, and its "0 hitches" would mean nothing.
    # Both ends: display data must reach from before the window's start to past its end
    # (Codex, PR #83 round 3), and rows whose times do not parse are ignored, not fatal.
    spans = []
    for row in rows(export(trace, "display-vsyncs-interval")):
        at = number(row.get("timestamp"))
        duration = number(row.get("duration"))
        # A row counts only with both fields valid: a stray timestamp without a duration must
        # not stretch the coverage (Codex, PR #83 round 4).
        if at is not None and duration is not None:
            spans.append((at, at + duration))
    coverage_start = min(s for s, _ in spans) if spans else None
    coverage_end = max(e for _, e in spans) if spans else None
    covered = coverage_start is not None and coverage_start <= start and coverage_end >= end

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

    return {
        "trace": trace,
        "result": lines[0][1] if lines else None,
        "window_s": round((end - start) / 1e9, 3),
        "window_source": window_source,
        "window_start_s": round(start / 1e9, 3),
        "display_data_from_s": round(coverage_start / 1e9, 3) if coverage_start is not None else None,
        "display_data_to_s": round(coverage_end / 1e9, 3) if coverage_end is not None else None,
        "window_end_s": round(end / 1e9, 3),
        "window_covered": covered,
        "hitches": len(inside),
        "hitches_over_33ms": sum(1 for d in inside if d > DROPPED_FRAME_NS),
        "worst_hitch_ms": round(max(inside) / 1e6, 3) if inside else 0,
        "stage_intervals": stage,
    }


if __name__ == "__main__":
    for path in sys.argv[1:]:
        print(json.dumps(summarise(path)))
