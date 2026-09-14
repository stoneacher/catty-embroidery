/// Where the stage is, and what is currently happening to it — one value, one owner.
///
/// **Why this type exists, stated plainly, because it replaces a working implementation.**
/// US-307's first design spread the same information across five things in the view: a
/// `@GestureState` of live gesture values, a `@State` fit animation, a `@State` generation token
/// to disarm stale completions, the committed transform, and three derived expressions
/// (`isInteracting`, the live transform, the `.settled`/`.live` choice). The invariants between
/// them were maintained by hand in four separate methods, and **none of them was reachable by a
/// test** — the whole interaction lived in a SwiftUI view.
///
/// The cross-vendor review found a defect in that arrangement in six consecutive rounds, and
/// four of them were the *same* conceptual mistake: asking "is an interaction happening?" by
/// comparing values rather than by asking the lifecycle. `current == committed` is true when a
/// gesture returns to its baseline; `live != LiveGesture()` is false for a pinch back to exactly
/// 1×; `next != fit` is defeated by one ULP; and faking a baseline with `overriding` erased
/// "following the fit" so the guard could not fire at all. Each fix was local, correct, and
/// followed by the next instance one round later. That is a representation problem, not six
/// bugs — and patching it a seventh time would have been the wrong move.
///
/// So: one value, holding both the committed transform and the phase, where every question the
/// view used to answer by comparison is a single method here — and every one of them is now a
/// pure function under `swift test`, which is the deeper win. The view keeps only what SwiftUI
/// must own: a `@GestureState` whose *presence* is the gesture's lifecycle.
public struct StageInteraction: Equatable, Sendable {
    /// The user's explicit transform, or `nil` while the stage follows the fit.
    ///
    /// `nil` rather than a snapshot: a stored fit freezes at the viewport it was taken in, so a
    /// rotation, an iPad resize, or a design growing outside the hoop mid-run would leave the
    /// design framed for a viewport that no longer exists.
    public private(set) var settled: StageTransform?

    public private(set) var phase: Phase = .idle

    /// Hands out the next animation's identity. Monotonic, so an id is never reused and a
    /// completion from an animation two interruptions ago cannot match.
    private var nextSettlingID = 0

    /// One activation of the adjustable action, as a **multiplicative** factor.
    ///
    /// Multiplicative because the range spans three orders of magnitude (0.05 … 50): an
    /// additive step usable at 0.05 is imperceptible at 50, and vice versa. 1.5 reaches the
    /// maximum from a typical in-hoop fit (about 0.6) in roughly eleven activations and the
    /// floor in six — enough resolution to frame a region, few enough presses that a Switch
    /// Control user is not on a treadmill. 1.25 needs four activations to double; 2.0 overshoots
    /// in two the ~3× ceiling ADR-027 records for the needle's legibility.
    public static let adjustmentStep: Double = 1.5

    /// What one double-tap zooms to, as a multiple of the fit.
    ///
    /// 2× rather than the adjustable action's 1.5, because this is one gesture and not a
    /// repeatable step: a double tap is a *destination*, and Photos' fit-to-filled toggle is the
    /// reference. Deliberately modest — the tap says "closer", the pinch says how much.
    public static let toggleStep: Double = 2

    public init() {}

    public var isFollowingFit: Bool {
        settled == nil
    }

    public var isSettling: Bool {
        phase != .idle
    }

    // MARK: - What to draw

    /// The committed transform, as the current phase has it.
    ///
    /// During a fit animation this is the interpolated value, so a gesture starting mid-spring
    /// continues from what is on screen rather than from where the spring began.
    public func baseline(fitting fit: StageTransform) -> StageTransform {
        switch phase {
        case .idle:
            settled ?? fit
        case let .settling(_, from, to, progress, _, _):
            from.interpolated(to: to, progress: progress)
        }
    }

    /// The baseline with the animation's progress supplied from outside.
    ///
    /// **The view owns the interpolation, because only SwiftUI can produce it.** A
    /// `StageTransform` is not animatable and a `Canvas`'s drawing closure is not either, so
    /// `withAnimation` around a mutation of this value animates *nothing* — it snaps. The view
    /// wraps the canvas in an `Animatable` shim whose `animatableData` is the progress, and
    /// feeds the interpolated value back in here, which is what makes the reset re-stroke at
    /// each step rather than jump. (The first rewrite deleted that shim and, with it, the
    /// animation; the tests could not see it because they only ever observed progress 0 and 1 —
    /// Codex round 7.)
    public func baseline(fitting fit: StageTransform, settlingAt progress: Double) -> StageTransform {
        guard case let .settling(_, from, to, _, _, _) = phase else { return baseline(fitting: fit) }
        return from.interpolated(to: to, progress: progress)
    }

    /// The progress the *model* holds — the endpoint `withAnimation` is moving toward, which
    /// the view's shim interpolates from.
    public var settlingProgress: Double {
        guard case let .settling(_, _, _, progress, _, _) = phase else { return 0 }
        return progress
    }

    /// **The one place the bake/draw split is decided.**
    ///
    /// `.settled` only when nothing is happening — never inferred from two transforms being
    /// equal, which is what let a raster rebuild land in the middle of a gesture. While a
    /// gesture or an animation is in flight the frame is re-stroked at `current` and the
    /// raster's key stays on `bake`, so the settled prefix is rasterised once, on commit, and
    /// the frame can still reveal content the canvas had not drawn (ADR-028).
    /// - Parameter settlingAt: the animation's interpolated progress, supplied by the view's
    ///   `Animatable` shim. Ignored unless a fit animation is in flight.
    public func rendering(
        gesture: StageGesture?,
        fitting fit: StageTransform,
        in viewport: ViewSize,
        settlingAt progress: Double = 1
    ) -> StageRenderTransform {
        // **Presence, not movement — and US-313 tried to weaken this and was refuted here.**
        // Going `.live` the instant a finger lands does degrade the image on a stationary frame
        // (US-310 made liveness cost fidelity), and the planning pass proposed gating on
        // `!gesture.isIdentity` on the argument that an unmoved gesture leaves the bake key
        // where it is, so nothing could be re-baked. **The bake key is not the transform alone**:
        // `CanvasStitchRenderer.BakeKey` also carries `settledCount`, which advances while a run
        // is still producing stitches. So a resting frame reporting `canUseRaster` mid-gesture
        // lets a bake fire at a *new* watermark — a full rasterisation of the settled prefix,
        // during the gesture, which is ADR-028's Codex round 2 defect exactly and the expense
        // ADR-009's cache exists to avoid. The two tests below were written for that defect and
        // they caught this.
        guard gesture != nil || isSettling else { return .settled(baseline(fitting: fit)) }
        return .live(
            bake: settled ?? fit,
            current: transform(
                with: gesture, fitting: fit, in: viewport, settlingAt: progress
            )
        )
    }

    /// Where the stage is right now, gesture included.
    public func transform(
        with gesture: StageGesture?,
        fitting fit: StageTransform,
        in viewport: ViewSize,
        settlingAt progress: Double = 1
    ) -> StageTransform {
        let committed = baseline(fitting: fit, settlingAt: progress)
        guard let gesture, !gesture.isIdentity else { return committed }
        return moved(by: gesture, from: committed, fitting: fit, in: viewport)
    }

    /// How far the stage is zoomed relative to the fit — 1.0 means fitted.
    ///
    /// Relative, because this is what gets spoken: view points per stage point means nothing to
    /// a user, and "300 per cent" is something they can act on.
    public func magnification(
        gesture: StageGesture?,
        fitting fit: StageTransform,
        in viewport: ViewSize
    ) -> Double {
        transform(with: gesture, fitting: fit, in: viewport).scale / fit.scale
    }

    // MARK: - Transitions

    /// Folds a finished gesture in.
    ///
    /// An identity gesture is not stored *while following the fit*: the resulting transform is
    /// the fit, and storing it would make `settled` non-`nil` and stop the refit — so a gesture
    /// that did nothing would leave the design framed for a viewport the next rotation replaces.
    /// A user who deliberately zoomed keeps their transform either way, including one that
    /// happens to coincide with the fit, because a later refit must not move something they
    /// placed.
    /// - Parameter settlingAt: the fit animation's *visible* progress, if one is in flight.
    ///   Required because the model's stored progress jumps to 1 the moment `withAnimation`
    ///   runs — only the view's `Animatable` shim holds the interpolated value — so without it
    ///   an interruption adopts the destination and the stage snaps from what the user can see
    ///   to the fit before the gesture applies (Codex round 8).
    public mutating func commit(
        _ gesture: StageGesture,
        fitting fit: StageTransform,
        in viewport: ViewSize,
        settlingAt progress: Double = 1
    ) {
        // A gesture always ends any animation — at what is on screen, not at where the
        // animation was going.
        interrupt(settlingAt: progress)

        guard !(gesture.isIdentity && isFollowingFit) else { return }
        settled = moved(by: gesture, from: settled ?? fit, fitting: fit, in: viewport)
    }

    /// Begins the double-tap / "Fit to Hoop" animation. Returns `false` when there is nothing to
    /// animate, so the caller does not start a spring that would render one frame and stop.
    /// Returns the new animation's identity, or `nil` when there is nothing to animate — the
    /// caller passes it back to `finishSettling(_:)` so a late completion can prove it owns the
    /// animation it is ending.
    /// - Parameter settlingAt: the in-flight animation's **visible** progress. Load-bearing
    ///   since the toggle exists: `interrupt()` at progress 1 adopts the animation's
    ///   *destination*, which used to be the fit for every animation and so was harmless. A
    ///   zoom-in's destination is not the fit, so "Fit to Hoop" pressed mid-zoom-in snapped the
    ///   stage forward to 2× and then animated back (`/codex-review` round 2).
    public mutating func beginSettling(
        fitting fit: StageTransform,
        settlingAt progress: Double = 1
    ) -> Int? {
        // A second activation while the first is still running would otherwise animate from the
        // pre-animation transform and snap backwards past what is on screen.
        interrupt(settlingAt: progress)
        guard !isFollowingFit else { return nil }

        nextSettlingID += 1
        phase = .settling(
            id: nextSettlingID, from: settled ?? fit, to: fit, progress: 0,
            adoptsFit: true, sourceFollowedFit: isFollowingFit
        )
        return nextSettlingID
    }

    /// The double-tap: **fit ↔ `toggleStep` about the tapped point.**
    ///
    /// Maps and Photos zoom *in* at the point you tapped; the stage only ever reset to the fit,
    /// which is a divergence from the very apps a user is comparing it against. So: fitted taps
    /// zoom in about the tap, anything else returns to the fit — which keeps fit exactly one
    /// more tap away, the recovery path the "Fit to Hoop" accessibility action also guarantees.
    ///
    /// Returns the new animation's identity, or `nil` when there is nothing to animate.
    /// - Parameter point: where the user tapped, in view points.
    public mutating func beginToggle(
        about point: ViewPoint,
        fitting fit: StageTransform,
        settlingAt progress: Double = 1
    ) -> Int? {
        // A second activation while the first is still running would otherwise animate from the
        // pre-animation transform and snap backwards past what is on screen.
        interrupt(settlingAt: progress)

        let from = settled ?? fit
        let zoomingIn = isFollowingFit
        let destination = zoomingIn
            ? fit.pinched(by: Self.toggleStep, about: point, within: StageZoomBounds(fitting: fit))
            : fit
        // Nothing to *animate* is not nothing to *do*. Reachable two ways: the fit is already at
        // the maximum scale, so the pinch clamps to where it started; or `settled` is non-`nil`
        // and happens to equal the fit, which two opposing pans or a zero-delta accessibility pan
        // produce. In the second case returning early left the stage pinned to a stale explicit
        // transform that no later refit could move, and repeated double-taps stayed no-ops
        // (`/codex-review` round 1) — so the fit branch adopts the fit regardless.
        guard destination != from else {
            if !zoomingIn { settled = nil }
            return nil
        }

        nextSettlingID += 1
        phase = .settling(
            id: nextSettlingID,
            from: from,
            to: destination,
            progress: 0,
            adoptsFit: !zoomingIn,
            sourceFollowedFit: zoomingIn
        )
        return nextSettlingID
    }

    /// The user's fingers have gone down: end any animation, at what is on screen.
    ///
    /// **ADR-028 says a gesture and a fit animation are mutually exclusive, and until now only
    /// `commit` enforced it — at the gesture's *end*.** In between, the animation kept running
    /// under the fingers, so the visible baseline moved every frame while
    /// `StageManipulation` held magnification limits captured once at `pinchBegan`; the clamped
    /// factor then stopped matching the one `pinched` applies and the next rebase jumped
    /// (`/codex-review` round 3). Calling this at the first channel's begin makes the baseline
    /// something that cannot move under a manipulation, which is what the rebase derivation
    /// assumes.
    ///
    /// Idempotent, and inert when nothing is animating, so a coordinator may call it from every
    /// recogniser's `.began` without tracking which one was first.
    public mutating func beginManipulating(fitting fit: StageTransform, settlingAt progress: Double = 1) {
        interrupt(settlingAt: progress)
    }

    /// One activation of a directional pan accessibility action.
    ///
    /// **The gap this closes was live in the shipped app.** `adjust` zooms about the viewport's
    /// centre, so a user who cannot pinch could reach any magnification and still only ever see
    /// the middle of their design: at 3× the corners were unreachable. This is the same
    /// `dragged(by:)` a finger produces, so the two paths cannot drift apart.
    ///
    /// Unclamped, like the gesture pan — ADR-028 ships it that way and says so. Clamping is a
    /// real gap and its own story; adding it here for one caller would leave the two pans
    /// disagreeing about where the stage may go.
    public mutating func panned(
        by delta: ViewPoint,
        fitting fit: StageTransform,
        settlingAt progress: Double = 1
    ) {
        interrupt(settlingAt: progress)
        settled = (settled ?? fit).dragged(by: delta)
    }

    /// Drives the animation. Ignored unless a fit animation is actually in flight, so a
    /// completion arriving after an interruption cannot restart one.
    public mutating func settlingProgressed(to progress: Double) {
        guard case let .settling(id, from, to, _, adoptsFit, source) = phase else { return }
        phase = .settling(
            id: id, from: from, to: to, progress: progress,
            adoptsFit: adoptsFit, sourceFollowedFit: source
        )
    }

    /// Ends the animation `id` by adopting its destination — the fit.
    ///
    /// **Ownership, not merely idempotence.** Being inert when nothing is settling is not
    /// enough: a completion from an interrupted animation would otherwise end whichever
    /// animation happens to be running now (Codex round 7). The id it was handed at
    /// `beginSettling` is what makes "mine" checkable.
    public mutating func finishSettling(_ id: Int) {
        guard case let .settling(current, _, to, _, adoptsFit, _) = phase, current == id else {
            return
        }
        phase = .idle
        settled = adoptsFit ? nil : to
    }

    /// Ends any animation immediately, at the destination it was heading for.
    ///
    /// Called by anything that takes over — a gesture, an accessibility adjustment, a second
    /// double-tap. One method, so "what happens when you interrupt a fit" has one answer instead
    /// of one per caller.
    /// - Parameter progress: the animation's *visible* progress. At 1 — a completed animation,
    ///   or a caller with nothing on screen to preserve — the destination is adopted and the
    ///   stage goes back to following the fit. Below 1 the interpolated transform becomes the
    ///   user's explicit one, because they took control of a stage that was mid-flight and what
    ///   they see is what they should keep.
    public mutating func interrupt(settlingAt progress: Double = 1) {
        guard case let .settling(_, from, to, _, adoptsFit, source) = phase else { return }

        phase = .idle
        guard progress < 1 else {
            settled = adoptsFit ? nil : to
            return
        }
        // Nothing has moved yet, so nothing about the stage should change — including whether it
        // was following the fit. Storing `from` here would pin a stage that was only ever
        // "wherever the fit is" to one particular fit (`/codex-review` round 3).
        guard progress > 0 || !source else {
            settled = nil
            return
        }
        settled = from.interpolated(to: to, progress: progress)
    }

    /// One activation of the accessibility adjustable action.
    ///
    /// Anchored on the viewport's centre: there is no finger, and the centre is where the fit
    /// put the design's centre, so repeated activations zoom into the middle of the hoop rather
    /// than drifting.
    public mutating func adjust(
        _ direction: StageZoomAdjustment,
        fitting fit: StageTransform,
        in viewport: ViewSize,
        settlingAt progress: Double = 1
    ) {
        interrupt(settlingAt: progress)

        let factor = switch direction {
        case .zoomIn: Self.adjustmentStep
        case .zoomOut: 1 / Self.adjustmentStep
        }
        settled = (settled ?? fit)
            .pinched(by: factor, about: viewport.center, within: StageZoomBounds(fitting: fit))
    }

    /// Back to following the fit, with no animation — a new design, or a reset that should not
    /// be watched.
    public mutating func followFit() {
        phase = .idle
        settled = nil
    }

    private func moved(
        by gesture: StageGesture,
        from baseline: StageTransform,
        fitting fit: StageTransform,
        in viewport: ViewSize
    ) -> StageTransform {
        // Pinch before pan, and the order is observable: the anchor is a view point measured in
        // the gesture's *start* frame, so panning first would anchor the zoom about whatever
        // ended up under that coordinate.
        baseline
            .pinched(
                by: gesture.magnification,
                about: gesture.anchor(in: viewport),
                // Widened to include where the stage already is, so a pinch cannot snap a
                // legitimately out-of-floor transform up to the floor — and, since US-313a
                // clamps the input layer into the matching range, so that a 1× pinch stays 1×
                // (`/codex-review` round 4).
                within: StageZoomBounds(fitting: fit, including: baseline.scale)
            )
            .dragged(by: gesture.pan)
    }
}
