# US-314 — The stage is not frozen under the fingers while the design is still growing

**Epic**: E4 Stage & preview | **Estimate**: ~3 h | **Depends on**: — (M3 `StagePreview`, shipped)
**Discovered**: 2026-09-14, `/codex-review` round 2 on US-313a. **Scheduled into M4**: 2026-09-19.

**Story**: As a user, I want the stage to stay still under my fingers while I pinch, even though the design is still being stitched, so the point I grabbed is the point I am still holding.

## Problem

ADR-028's baseline is `settled ?? fit`, and `fit` is a **per-frame parameter** the view recomputes from the display list's bounds. While the user has never zoomed — `settled == nil`, "following the fit", the state a fresh stage is in — a run whose design grows beyond the hoop changes `StageGeometry.fitTarget(including:)`, and therefore changes the fit, the bake key and the drawn transform **mid-manipulation**. The stage shifts under the fingers.

**Reproduction** (Codex's, at viewport 100 × 100): a fresh interaction, `panBegan`, `pinchBegan` at (20, 20), `pinchChanged(to: 2)`, then render once with `fit.scale == 1` and once with `fit.scale == 0.5` without ending the manipulation. The grabbed stage point maps to x = 20 in the first frame and x = 0 in the second, and `bake` changes between them.

**Why it is not US-313a's**: it is pre-existing — US-307 shipped it and US-313a changed nothing about it. What US-313a did was *claim* the invariant more loudly (its AC10 said "`bake` is identical across every frame of a manipulation"), so that criterion was narrowed to "at a constant fit" rather than left overstating what the code does. This story is what makes the unnarrowed claim true.

## Why it is in M4

**M4 increases its exposure.** ADR-038 makes every applied edit **void** the run — leaving it idle, to be replayed — so "the design grows while the user is manipulating the stage" stops being an edge case and becomes the ordinary rhythm of editing: change a parameter, replay, pinch in to look at the result while it is still going.

**It is not package-only, and the first draft of this plan said it was** *(Codex round 1)*. The scope has to cross into the app, for a reason in the shipped code:

- `StageManipulation`'s begin methods (`panBegan(at:)`, `pinchBegan(…)`) **receive no fitted transform**, so the baseline cannot be captured there from what those methods are given.
- `StageInteraction.beginManipulating(fitting:)` **does** take the fit, so that is where a baseline can be captured — but the existing cancellation path in the app calls only `manipulation?.wrappedValue.cancelled()` (`StageManipulationCoordinator.swift:231`) and touches `StageInteraction` not at all. **A baseline owned by `StageInteraction` therefore has no existing path that clears it on cancel.**
- Concrete consequence: begin at fit A, cancel, render at fit B — the baseline survives the cancel and the stage stays frozen to a gesture that is over.

So the story needs **app wiring plus integration coverage**, and its position moves out of the package-only block's rationale. Its place in the order is unchanged — it depends on nothing M4 builds — but its estimate carries app work, and the buildability table records it as touching both layers.

## Acceptance criteria

- [ ] A **`manipulationBaseline`** is captured at the **first channel's begin** and cleared at commit or cancel, and is read by `baseline`, `rendering`, `transform` and `commit` while a manipulation is live. Where it lives is decided by which type actually receives the fit: `StageInteraction.beginManipulating(fitting:)` does and `StageManipulation`'s begin methods do not.
- [ ] **The cancellation path clears it.** Today `StageManipulationCoordinator.cancel()` calls only `manipulation.cancelled()`; whatever owns the baseline must be reached on cancel too, and the wiring is part of this story rather than assumed.
- [ ] An **integration test at the app layer** covers begin → cancel → render at a changed fit. The package tests below cannot see the coordinator, and the coordinator is where the gap is.
- [ ] The baseline is distinct from `settled`. **Pinning `settled` at gesture start instead is explicitly rejected**: it would take the stage permanently off the fit and contradict ADR-028's rule that an identity gesture must not do that. An identity gesture must still leave `settled == nil` when it started `nil`.
- [ ] Across two frames of one manipulation **at two different fits**, the grabbed stage point maps to the same view point, and `bake` is unchanged.
- [ ] ADR-028 gains a dated amendment recording that "the baseline cannot move while fingers are down" is now **enforced rather than assumed**, and US-313a's narrowed AC10 wording is reconciled with it (ADR-032 invariant 3 — the claim exists in more than one place).
- [ ] No regression in the M3 manipulation suite, which is the real risk: this touches the type US-313a and US-313b both built on.

## Test-first plan

1. **The test every existing test misses**: drive two *different* fits through one manipulation and assert the grabbed point's view position is unchanged. Every current test passes the same `Self.fit` every frame, which is exactly why this defect survived two stories and six review rounds.
2. `bake` is identical across those same two frames.
3. An identity gesture (begin, no movement, end) at a changing fit leaves `settled == nil` — the ADR-028 rule that rules out the cheap fix.
4. A real zoom during a changing fit commits a `settled` derived from the **frozen** baseline, not from the fit at commit time.
5. The baseline is cleared on cancel as well as on commit, so a cancelled manipulation followed by a fit change renders at the new fit.
6. Two channels beginning in either order capture the baseline **once**, at the first — the ordering test, since a pan and a pinch can begin in either order (ADR-031).

**Mutation targets**: capturing the baseline at *each* channel's begin rather than the first (green for a pinch-only gesture, wrong for the pan-then-pinch order); clearing it on the first channel's end rather than at commit, which US-313b already showed is a different moment.

## References

- ADR-028 (the `settled ?? fit` baseline and the identity-gesture rule), ADR-031 (the recogniser pair and the terminal signal), ADR-030 §7
- US-313a's AC10, narrowed rather than met — the claim this story makes true
- `docs/user-stories/backlog.md` — this story's original entry, written at discovery on 2026-09-14
