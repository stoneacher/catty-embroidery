import StagePreview
import SwiftUI

// The interaction layer: what a gesture currently is, what a fit animation currently is, and
// the wrapper that re-renders the canvas at each step of one.
//
// Split out of `StageCanvas` when that file crossed SwiftLint's hard 400 lines (CI runs
// `--strict`). The seam is a real one — everything here describes an interaction *in
// progress*, where `StageCanvas` is the stage itself.

/// A gesture's absolute state since it began. See `StageCanvas.live`.
struct LiveGesture: Equatable {
    /// Whether a gesture is actually in flight.
    ///
    /// **Lifecycle, not values, and the difference has now bitten twice.** Liveness was first
    /// inferred from `current == committed` and then from `live != LiveGesture()`; both are
    /// value comparisons, and both report "settled" for a gesture that is still very much
    /// happening — a centred pinch taken to 2× and returned to exactly 1× with no pan is
    /// `LiveGesture()` again while both fingers are down (Codex rounds 2 and 3). SwiftUI sets
    /// this in `.updating` and resets it for us when the gesture ends, including a
    /// system-cancelled one, so it tracks the thing itself rather than a symptom of it.
    var isActive = false

    var magnification: CGFloat = 1
    var anchor: UnitPoint = .center

    /// The drag's translation, **including the recognizer's threshold distance**.
    ///
    /// An earlier version subtracted the first callback's translation so the content would
    /// not jump by the ~10 pt threshold when a pan starts. That was wrong in a way only
    /// measurement found: `@GestureState` has already reset by the time `onEnded` runs, so
    /// the origin read there was always `nil` and the *commit* used the raw translation while
    /// the *live* offset had subtracted it — moving the content forward by the threshold at
    /// finger-lift, which is a worse artefact than the one it was avoiding and the opposite
    /// of what the comment claimed (`swift-code-reviewer`, measured at 101 pt committed for a
    /// 101 pt drag whose live offset had shown 91).
    ///
    /// Not subtracting anywhere is the fix: live and committed are then the *same* number by
    /// construction rather than by two pieces of code agreeing. The price is the jump the
    /// subtraction existed to avoid, now paid at pan **start**, where it reads as the drag
    /// catching rather than as the content slipping after the finger stops.
    var pan: CGSize = .zero
}

extension MagnifyGesture.Value {
    /// The pinch anchor's two components, so the package never sees a `UnitPoint`.
    var anchorUnitX: Double {
        startAnchor.x
    }

    var anchorUnitY: Double {
        startAnchor.y
    }
}

/// A fit animation in flight: where it started, where it is going, and how far along it is.
struct SettlingFit: Equatable {
    let from: StageTransform
    let to: StageTransform
    var progress: Double
}

/// Re-renders its content at an interpolated transform for each step of an animation.
///
/// **The reason this exists rather than a `.scaleEffect`.** SwiftUI can only animate values it
/// can interpolate, and a `StageTransform` is not one — `Canvas` re-strokes from whatever it is
/// handed. Conforming to `Animatable` on a plain `Double` gives SwiftUI something it *can*
/// interpolate, and the body then asks the package for the transform at that point. The result
/// is that the canvas is genuinely re-drawn at each step, which is what lets a zoom-out reveal
/// content that was previously outside the canvas's bounds.
///
/// `progress` is passed straight through when no animation is running (`from == to`), so this
/// costs a closure call and nothing else in the common case.
struct StageInterpolatedCanvas<Content: View>: View, Animatable {
    var progress: Double
    let from: StageTransform
    let to: StageTransform
    @ViewBuilder let content: (StageTransform) -> Content

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        content(from.interpolated(to: to, progress: progress))
    }
}
