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
    /// Internal rather than `private` since US-310, so `+Coarsening.swift` expresses its window
    /// in the same terms instead of re-deriving the same off-by-one in a second file.
    static func lastSegment(before count: Int) -> Int {
        Swift.max(0, count - 1)
    }

    /// Groups one window into strokes and dot runs, joining up to `stride` stitch intervals
    /// into one drawn segment.
    ///
    /// **`stride` is why there are still only two implementations rather than three.** The
    /// coarse window ADR-029's rung 2 asks for is this function at a stride above 1, so the
    /// settled, live and coarse pixels are produced by identical rules — the property the type
    /// doc below rests on. At stride 1 the emitted segments are exactly `i → i + 1`, so no
    /// existing window changes by a byte.
    ///
    /// Walks `colorRuns` rather than the stitches: the runs are a gapless partition of
    /// the indices (`StitchDisplayList` guarantees it), so every drawn segment lies
    /// wholly inside exactly one run and nothing needs a scan to find out which.
    ///
    /// A segment that *crosses* runs is never emitted, because a run contributes only
    /// the segments whose both endpoints it holds — so the suppression rule is
    /// enforced by the iteration, and the classifier's `.suppressed` result is a
    /// second, independent check rather than the only one.
    static func planning(
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

    /// The classified segments of one run's window, split by style.
    ///
    /// A named result rather than a tuple: SwiftLint caps tuple members, and both halves want
    /// names at the one call site. Separate from `strokes(for:of:within:stride:)` because the
    /// walk on its own is at SwiftLint's cyclomatic-complexity limit — assembling strokes in the
    /// same function put it one over, and the split is the honest fix rather than a raised cap.
    private struct WalkedSegments {
        var threaded: [Segment] = []
        var traversed: [Segment] = []
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
            let style = StitchSegmentStyle.classifying(
                from: list.stitches[start], to: list.stitches[start + 1]
            )
            if style == .thread {
                spanned += 1
                if spanned == stride {
                    walked.threaded.append(Segment(from: anchor, to: start + 1))
                    anchor = start + 1
                    spanned = 0
                }
                continue
            }

            // Travel and a colour boundary both end the span; only travel is itself drawn, and
            // it is drawn as the single interval it is. Merging two jumps would erase the needle
            // penetration between them.
            if spanned > 0 { walked.threaded.append(Segment(from: anchor, to: start)) }
            if style == .traversal {
                walked.traversed.append(Segment(from: start, to: start + 1))
            }
            anchor = start + 1
            spanned = 0
        }
        // A span shorter than the stride still has to be drawn, or the run's thread stops short
        // of its own last stitch — visible as a nibbled end on every colour run.
        if spanned > 0 { walked.threaded.append(Segment(from: anchor, to: candidates.upperBound)) }

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
