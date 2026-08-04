# Backlog — specified but not yet scheduled

Stories that are fully analysed but have no milestone yet. They live here rather than in a
milestone folder so a closed milestone's "all N stories merged" claim stays true, and so the
analysis is captured while it is fresh instead of being re-derived at the next planning
session. Precedent for why that matters: the ±121 coordinate trap sat as a journal
carry-forward from 2026-07-09 to M2 planning, and was then mis-scoped twice by review before
it became US-210.

Milestone planning picks these up and assigns them a place; the ID stays stable so existing
ADR and journal references keep resolving.

---

**Currently empty.** The mechanism worked as designed and is worth recording:

- **US-211 — DST serialization field-width chokepoint.** Specified here at discovery time on
  2026-07-31, scheduled into M3 on 2026-08-04 →
  [`milestone-3/US-211-dst-field-width-chokepoint.md`](milestone-3/US-211-dst-field-width-chokepoint.md).
  Its status line said "Candidate for M3, where the export path forces the decision this
  story needs", and that is exactly what happened: the three-way choice (clamp / throwing
  init / bound at the app layer) was resolved during M3 planning once the export path existed
  to be the caller, and two facts that only surfaced then changed the answer — ADR-007's stage
  bounds do not exist as code, and `DSTHeader.init` is a second public trapping entry point
  this file never listed. Deciding it in isolation would have picked the wrong option.

Also settled by M3 planning, though they were ADR-020 consequences rather than backlog
entries: the `hasValidPattern`-vs-replay export-gating divergence and the adversarial-coordinate
question are now placed in
[`milestone-3/US-308`](milestone-3/US-308-design-name-and-dst-export.md) and
[`milestone-3/US-211`](milestone-3/US-211-dst-field-width-chokepoint.md) respectively.
