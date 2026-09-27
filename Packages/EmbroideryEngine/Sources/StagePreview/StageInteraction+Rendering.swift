/// What to draw: the read-only half of `StageInteraction`.
///
/// In its own file for the reason `StageInteraction+Magnification.swift` gives — the main file
/// sits at SwiftLint's 400-line limit under `--strict`, and what can move is what only *reads*.
/// Everything that writes `settled` stays in `StageInteraction.swift`, whose `private(set)` keeps
/// its writers in one file. That is *not* the invariant "settled is not written while fingers
/// are down": none of those writers is told whether a manipulation is live, and ADR-028's US-314
/// amendment records the double tap and accessibility actions that can still reach one.
/// `transform(with:…)` stays there too: it calls the private `moved(by:…)`.
public extension StageInteraction {
    /// The committed transform, as the current phase has it.
    ///
    /// During a fit animation this is the interpolated value, so a gesture starting mid-spring
    /// continues from what is on screen rather than from where the spring began.
    func baseline(fitting fit: StageTransform) -> StageTransform {
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
    func baseline(fitting fit: StageTransform, settlingAt progress: Double) -> StageTransform {
        guard case let .settling(_, from, to, _, _, _) = phase else { return baseline(fitting: fit) }
        return from.interpolated(to: to, progress: progress)
    }

    /// The progress the *model* holds — the endpoint `withAnimation` is moving toward, which
    /// the view's shim interpolates from.
    var settlingProgress: Double {
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
    func rendering(
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
            bake: settled ?? self.fit(for: gesture, current: fit),
            current: transform(
                with: gesture, fitting: fit, in: viewport, settlingAt: progress
            )
        )
    }

    /// The fit a frame is drawn against: the frozen one while a gesture is present, the one on
    /// screen otherwise.
    ///
    /// An at-rest frame never gets here — `rendering` returns `.settled` at the live fit first.
    /// What the gesture check protects is every *other* gesture-less read of a frozen fit that
    /// outlived its manipulation (a view torn down without a cancel): `transform(with: nil…)`,
    /// the spoken `magnification`, and the bake of a fit animation running with no fingers down.
    internal func fit(for gesture: StageGesture?, current fit: StageTransform) -> StageTransform {
        gesture == nil ? fit : manipulationFit ?? fit
    }
}
