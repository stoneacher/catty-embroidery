import EmbroideryEngine

/// The three windows a frame needs, and the single planner behind them.
///
/// One planner parameterised by two windows, rather than three implementations:
/// settled and live pixels must be produced by the same rules or the seam at the
/// watermark will differ visibly in cap shape, width or alpha, and no unit test would
/// notice.
public extension StitchDrawPlan {
    /// Everything in the list — the no-raster path, and what a frame draws while the
    /// design is still small enough that baking costs more than it saves.
    static func entire(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.count,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.count),
            stride: 1
        )
    }

    /// What the cached raster bakes: strictly *inside* the watermark.
    static func settled(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: 0 ..< list.settledCount,
            segmentsFrom: 0,
            upTo: lastSegment(before: list.settledCount),
            stride: 1
        )
    }

    /// What each frame redraws over the raster.
    ///
    /// **It starts one segment earlier than the dots do, and that is the point.** The
    /// watermark splits *stitches*, but a segment joins two of them, so segment
    /// `(k−1, k)` straddles it and belongs to neither window under the obvious
    /// reading — leaving a permanent one-segment gap in the thread at every watermark
    /// advance. (US-305's own test plan asked for exactly that obvious reading; the
    /// story records the correction.)
    ///
    /// Sound because the display list is append-only **per element**, not merely per
    /// prefix: stitch `k − 1` can never change once appended, so redrawing its
    /// outgoing segment every frame is free of risk, and when the watermark passes it
    /// the raster picks the segment up. The two windows stay disjoint, so a
    /// traversal's alpha is never composited twice.
    ///
    /// Note this needs stitch `k − 1`, which is *outside* `liveTail`. Indexing
    /// `stitches` is correct here; reaching for the slice and keeping it is what
    /// ADR-021 forbids.
    static func live(of list: StitchDisplayList) -> StitchDrawPlan {
        planning(
            list,
            dotting: list.settledCount ..< list.count,
            segmentsFrom: lastSegment(before: list.settledCount),
            upTo: lastSegment(before: list.count),
            stride: 1
        )
    }

    /// The number of segments wholly below `count` stitches: `count − 1`, floored at
    /// zero so an empty or one-stitch list stays total. Both windows are expressed in
    /// terms of this, so the off-by-one lives in one place.
    ///
    /// **`internal`, spelled out.** It was `private` until US-310, which needed it from
    /// `+Coarsening.swift`; dropping `private` inside a `public extension` makes a member
    /// **public**, which is not what the change intended and is what review caught. The keyword
    /// is explicit here so the next edit cannot widen it by omission.
    internal static func lastSegment(before count: Int) -> Int {
        Swift.max(0, count - 1)
    }

    /// Groups one window into strokes and dot runs, joining up to `stride` stitch intervals
    /// into one drawn segment.
    ///
    /// **`stride` is why there are still only two implementations rather than three.** The
    /// coarse window ADR-029's rung 2 asks for is this function at a stride above 1, so the
    /// settled, live and coarse pixels are produced by identical rules — the property the type
    /// doc below rests on. At stride 1 the emitted segments are exactly `i → i + 1`, so no
    /// existing window changes which stitches it draws or in what order — *not* "by a byte",
    /// since the representation itself deliberately changed from an index to a pair
    /// (`/codex-review` round 2, finding 3).
    ///
    /// Walks `colorRuns` rather than the stitches: the runs are a gapless partition of
    /// the indices (`StitchDisplayList` guarantees it), so every drawn segment lies
    /// wholly inside exactly one run and nothing needs a scan to find out which.
    ///
    /// A segment that *crosses* runs is never emitted, because a run contributes only
    /// the segments whose both endpoints it holds — so the suppression rule is
    /// enforced by the iteration, and the classifier's `.suppressed` result is a
    /// second, independent check rather than the only one.
    /// **`internal`, spelled out**, for the reason `lastSegment(before:)` records: undecorated
    /// members of a `public extension` are public, and a *public* `planning` would be a public
    /// constructor for arbitrary plans at a caller-chosen window and stride — which is precisely
    /// the chokepoint `Stroke` and `DotRun` give up their memberwise initializers to keep
    /// (`StitchDrawPlan`'s type doc). It also made `stride: 0` and `stride: .max` reachable from
    /// outside the module.
    internal static func planning(
        _ list: StitchDisplayList,
        dotting dotted: Range<Int>,
        segmentsFrom firstSegment: Int,
        upTo lastSegment: Int,
        stride: Int
    ) -> StitchDrawPlan {
        var plan = StitchDrawPlan()
        let segments = firstSegment ..< lastSegment

        for run in list.colorRuns {
            plan.strokes += strokes(for: run, of: list, within: segments, stride: stride)
        }
        for run in list.colorRuns {
            if let indices = run.range.clamped(within: dotted) {
                plan.dots.append(DotRun(color: run.color, indices: indices, stride: stride))
            }
        }
        return plan
    }

    /// The at-most-two strokes one colour run contributes: traversal first, so travel
    /// hints sit *under* the thread rather than over it.
    ///
    /// **The coarse-span rule, and it is the whole of US-310's correctness.** A thread segment
    /// is emitted only when every stitch interval it spans classifies `.thread`, so an open
    /// span is *closed* at anything else rather than drawn through it:
    ///
    /// - `.thread` extends the span, and closes it once it holds `stride` intervals.
    /// - `.traversal` closes the span, then emits the traversal **verbatim** as one interval.
    ///   Travel is never coarsened: merging two jumps would erase the needle penetration
    ///   between them, and joining across one would draw thread where the machine only travels
    ///   — precisely the defect ADR-024 records in *both* references and that we do not
    ///   reproduce.
    /// - `.suppressed` cannot arise inside a run (see `planning`) and closes the span anyway,
    ///   so the second, independent check stays a check rather than becoming the only one.
    ///
    /// Nothing here needs a scan to find a segment's owner: the runs are a gapless partition of
    /// the indices, and a run contributes only the segments whose *both* endpoints it holds, so
    /// no span can cross a colour change.
    private static func strokes(
        for run: StitchDisplayList.ColorRun,
        of list: StitchDisplayList,
        within window: Range<Int>,
        stride: Int
    ) -> [Stroke] {
        // Segment `i` belongs to this run only if it holds both `i` and `i + 1`.
        let owned = run.range.lowerBound ..< Swift.max(run.range.lowerBound, run.range.upperBound - 1)
        guard let candidates = owned.clamped(within: window) else { return [] }

        let walked = walking(candidates, of: list, stride: Swift.max(1, stride))

        var strokes: [Stroke] = []
        if !walked.traversed.isEmpty {
            strokes.append(Stroke(style: .traversal, color: run.color, segments: walked.traversed))
        }
        if !walked.threaded.isEmpty {
            strokes.append(Stroke(style: .thread, color: run.color, segments: walked.threaded))
        }
        return strokes
    }

    /// Whether the interval between two stitches may be *merged into* a longer segment.
    ///
    /// Only about representability, never about style: the classifier decides what a thread is,
    /// this decides what may be joined. A joined segment carries only its two ends, so the
    /// renderer's per-subpath `isDrawable` guard can no longer see the vertex in between — which
    /// makes joining over an unreachable stitch draw thread across ground the machine never
    /// visits.
    ///
    /// **The predicate is "can the machine go there", not "is the coordinate finite"**, and the
    /// difference is a defect `/codex-review` round 3 found. A *finite* coordinate can still map
    /// to a non-finite view point: `1e307` at `StageTransform.maximumScale` overflows, so the
    /// fine plan draws neither adjacent interval while a coarse span joined straight over it —
    /// the same ADR-024 violation as round 1's, reached through the transform instead of the
    /// coordinate. `EmbroideryPoint(converting:)` is the right test because it is **exactly what
    /// `EmbroideryStream.requiresTraversal` consults** (ADR-020's range guard, `Int(exactly:)`
    /// over the rounded stage value): a stitch it rejects is one the replay never reaches, so no
    /// span may cross it.
    ///
    /// **Why acceptance is *sufficient*, spelled out because the whole fix rests on it.**
    /// `EmbroideryPoint.embroideryUnits(fromStageValue:)` is `Int(exactly: javaRound(value * 2))`,
    /// so it accepts a magnitude of at most about 4.6 × 10^18 — `Int64.max / 2`. `StageTransform`
    /// guarantees a scale within `[minimumScale, maximumScale]` (0.05 … 50) and a translation that
    /// is finite by construction, so an accepted coordinate maps to at most about 2.3 × 10^20:
    /// finite by a factor of 10^288, and therefore drawable. So a stitch this predicate accepts is
    /// one `segmentPath` will draw at *every* transform the type can represent, which is what
    /// makes a transform-free joinability rule safe against a transform-dependent renderer guard.
    ///
    /// This keeps the plan **transform-free**, which `StitchDrawPlan`'s type doc requires —
    /// panning and zooming must not invalidate a plan, so joinability cannot be a function of the
    /// transform even though the defect was found through one.
    private static func isJoinable(_ first: PreviewStitch, _ second: PreviewStitch) -> Bool {
        EmbroideryPoint(converting: first.position) != nil
            && EmbroideryPoint(converting: second.position) != nil
    }

    /// The classified segments of one run's window, split by style.
    ///
    /// A named result rather than a tuple: SwiftLint caps tuple members, and both halves want
    /// names at the one call site. Separate from `strokes(for:of:within:stride:)` because the
    /// walk on its own is at SwiftLint's cyclomatic-complexity limit — assembling strokes in the
    /// same function put it one over, and the split is the honest fix rather than a raised cap.
    private struct WalkedSegments {
        var threaded: [Segment] = []
        var traversed: [Segment] = []

        /// Emits the open span, if there is one, and marks it closed.
        ///
        /// One method for all three closing sites, because **dropping one of them is invisible**:
        /// review found that deleting the mid-run close left all 750 tests green, which on screen
        /// is up to `stride − 1` intervals of missing thread before every jump and every colour
        /// change. `spanned` is `inout` so a caller cannot close the span and forget to reset it.
        mutating func close(_ spanned: inout Int, from anchor: Int, to vertex: Int) {
            defer { spanned = 0 }
            guard spanned > 0 else { return }
            threaded.append(Segment(from: anchor, to: vertex))
        }
    }

    /// Walks one run's owned segments, joining up to `stride` consecutive thread intervals into
    /// one drawn segment and closing the open span at anything that is not thread.
    private static func walking(
        _ candidates: Range<Int>,
        of list: StitchDisplayList,
        stride: Int
    ) -> WalkedSegments {
        var walked = WalkedSegments()

        // The open span: `anchor` is the vertex it starts at, `spanned` how many intervals it
        // already holds. `spanned == 0` means there is no open span, which is why closing is
        // conditional rather than unconditional.
        var anchor = candidates.lowerBound
        var spanned = 0

        for start in candidates {
            // **A `switch`, not two `if`s.** The `if` form this replaced (US-310, first draft)
            // silently treated a *new* `StitchSegmentStyle` case as "close the span and draw
            // nothing"; exhaustiveness makes a fourth case a compile error here, which is how
            // `main` had it before this story and how the renderer still has it
            // (`swift-code-reviewer`).
            switch StitchSegmentStyle.classifying(
                from: list.stitches[start], to: list.stitches[start + 1]
            ) {
            case .thread:
                // **A span may not step over a stitch the renderer cannot draw**
                // (`/codex-review` round 1). ADR-021 lets a coordinate the stream *rejects* into
                // the display list, and `requiresTraversal` answers `false` for it — it cannot
                // compute a distance — so both intervals touching such a point classify
                // `.thread`. The fine plan emits them and `segmentPath` then skips each subpath
                // on `isDrawable`, drawing nothing across a gap the machine merely travels. A
                // span joining over that vertex has two *finite* endpoints, so it would be drawn:
                // one solid line straight across the travel, which is precisely the ADR-024
                // defect coarsening must not reintroduce.
                //
                // **Such an interval is not planned at all**, and that is a correction to this
                // story's first fix, which emitted it as its own unit segment to keep the coarse
                // plan's *interval* coverage identical to the fine plan's. That trade was wrong
                // in one direction (`/codex-review` round 2): for a design of 50 000 rejected
                // coordinates — which ADR-021 permits — every interval is unjoinable, so the
                // coarse plan came out with 49 999 segments and ADR-030's bound was defeated by
                // exactly the input coarsening exists to survive.
                //
                // Omitting them costs no pixels: `segmentPath` skips any subpath with a
                // non-drawable endpoint, so these intervals were never drawn in *either* plan.
                // What the coarse plan therefore matches is the fine plan's **drawn** coverage,
                // not its emitted coverage, and the bound holds for every input.
                // **`stride > 1` first, and that ordering is the whole point** (`/codex-review`
                // round 4). Joinability answers "may this interval be *merged*", never "may it be
                // *drawn*". Consulting it at stride 1 dropped intervals from `.entire`,
                // `.settled` and `.live` — a behaviour change in the fine windows, against
                // ADR-021's rule that the display list shows what the program *requested*, and
                // against this story's own claim that those windows draw what they drew before.
                // Conversion rejection does not imply view-space undrawability, and the two
                // cases differ in what dropping costs: a **non-finite** coordinate maps to a
                // non-finite view point and is skipped in every plan, so dropping it costs no
                // pixels — while a **finite but unconvertible** one (past `Int64.max / 2`) still
                // maps finitely at a small scale, so the fine plan genuinely draws it and
                // dropping it costs a segment ~10^17 view points off-screen. At stride 1 nothing
                // merges, so nothing may be dropped either way; above it the drop is what keeps
                // ADR-030's bound true, and the lost segment is a fidelity trade a live frame is
                // already making.
                if stride > 1, !Self.isJoinable(list.stitches[start], list.stitches[start + 1]) {
                    walked.close(&spanned, from: anchor, to: start)
                    anchor = start + 1
                } else {
                    spanned += 1
                    if spanned == stride {
                        walked.threaded.append(Segment(from: anchor, to: start + 1))
                        anchor = start + 1
                        spanned = 0
                    }
                }
            case .traversal:
                // Travel ends the open span and is then drawn as the single interval it is.
                // Merging two jumps would erase the needle penetration between them.
                walked.close(&spanned, from: anchor, to: start)
                walked.traversed.append(Segment(from: start, to: start + 1))
                anchor = start + 1
            case .suppressed:
                // Cannot arise inside a run (see `planning`); closing anyway keeps the second,
                // independent check a check rather than the only one.
                walked.close(&spanned, from: anchor, to: start)
                anchor = start + 1
            }
        }
        // A span shorter than the stride still has to be drawn, or the run's thread stops short
        // of its own last stitch — visible as a nibbled end on every colour run.
        walked.close(&spanned, from: anchor, to: candidates.upperBound)

        return walked
    }
}

private extension Range<Int> {
    /// The overlap with `other`, or `nil` when they do not meet.
    ///
    /// Not `Range.clamped(to:)`, which returns an *empty* range rather than `nil` for
    /// disjoint inputs — and an empty range is exactly what the plan's "no stroke is
    /// ever empty" invariant needs to distinguish from a real one.
    func clamped(within other: Range<Int>) -> Range<Int>? {
        let lower = Swift.max(lowerBound, other.lowerBound)
        let upper = Swift.min(upperBound, other.upperBound)
        return lower < upper ? lower ..< upper : nil
    }
}
