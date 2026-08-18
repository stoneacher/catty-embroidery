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
    /// What is happening to the stage right now.
    ///
    /// Deliberately **not** a `Bool` pair or a set of optionals: a gesture and a fit animation
    /// are mutually exclusive by construction here, where before they could overlap and the
    /// code that composed them had to decide which won.
    public enum Phase: Equatable, Sendable {
        case idle
        /// A double-tap or the "Fit to Hoop" action, animating from one transform to another.
        ///
        /// **`id` is identity, not bookkeeping, and leaving it out was a real defect.** The
        /// rewrite claimed that making `finishSettling` idempotent replaced the generation
        /// token it deleted. It does not: idempotence protects a late completion only when
        /// *nothing* is settling, and cannot tell "my animation" from "a newer one". Begin A,
        /// interrupt it with a gesture, begin B, and A's completion then finds B's `.settling`
        /// phase and ends it early (Codex round 7). The token was never bookkeeping — it was
        /// ownership — and the improvement over the original is that it now lives *inside the
        /// value*, where a test can reach it, rather than as a `@State` counter in a view.
        case settling(id: Int, from: StageTransform, to: StageTransform, progress: Double)
    }

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
        case let .settling(_, from, to, progress):
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
        guard case let .settling(_, from, to, _) = phase else { return baseline(fitting: fit) }
        return from.interpolated(to: to, progress: progress)
    }

    /// The progress the *model* holds — the endpoint `withAnimation` is moving toward, which
    /// the view's shim interpolates from.
    public var settlingProgress: Double {
        guard case let .settling(_, _, _, progress) = phase else { return 0 }
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
    public mutating func beginSettling(fitting fit: StageTransform) -> Int? {
        // A second activation while the first is still running would otherwise animate from the
        // pre-animation transform and snap backwards past what is on screen.
        interrupt()
        guard !isFollowingFit else { return nil }

        nextSettlingID += 1
        phase = .settling(id: nextSettlingID, from: settled ?? fit, to: fit, progress: 0)
        return nextSettlingID
    }

    /// Drives the animation. Ignored unless a fit animation is actually in flight, so a
    /// completion arriving after an interruption cannot restart one.
    public mutating func settlingProgressed(to progress: Double) {
        guard case let .settling(id, from, to, _) = phase else { return }
        phase = .settling(id: id, from: from, to: to, progress: progress)
    }

    /// Ends the animation `id` by adopting its destination — the fit.
    ///
    /// **Ownership, not merely idempotence.** Being inert when nothing is settling is not
    /// enough: a completion from an interrupted animation would otherwise end whichever
    /// animation happens to be running now (Codex round 7). The id it was handed at
    /// `beginSettling` is what makes "mine" checkable.
    public mutating func finishSettling(_ id: Int) {
        guard case let .settling(current, _, _, _) = phase, current == id else { return }
        phase = .idle
        settled = nil
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
        guard case let .settling(_, from, to, _) = phase else { return }

        phase = .idle
        settled = progress >= 1 ? nil : from.interpolated(to: to, progress: progress)
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
                within: StageZoomBounds(fitting: fit)
            )
            .dragged(by: gesture.pan)
    }
}
