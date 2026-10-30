#if DEBUG
    import CoreGraphics
    import Foundation

    /// Where US-316's scripted gesture is at a given moment (brief D4).
    ///
    /// **A pure function of the time since the gesture began.** The driver samples it at each
    /// display link's `targetTimestamp`, so a stalled frame makes the next sample jump the way a
    /// moving finger does, instead of slowing the gesture to the renderer's pace and hiding the
    /// stall.
    ///
    /// The pan traces a circle through its starting point: it begins at rest like a recogniser,
    /// moves on every frame (so every frame redraws), and never carries the design more than
    /// twice its radius from where it began. The mixed script adds a pinch around a scale of 1.
    struct GestureScript {
        enum Kind: Equatable {
            case pan
            case mixed
        }

        let kind: Kind

        /// The circle's radius, in view points.
        static let radius: CGFloat = 60

        /// One lap every two seconds: about 190 pt/s, a brisk drag.
        static let panPeriod: Double = 2

        /// The pinch swings ±20 % every three seconds, out of phase with the pan.
        static let pinchAmplitude: CGFloat = 0.2
        static let pinchPeriod: Double = 3

        /// The recogniser's translation from where the gesture began.
        func translation(at seconds: Double) -> CGPoint {
            let angle = 2 * Double.pi * seconds / Self.panPeriod
            return CGPoint(
                x: Self.radius * CGFloat(sin(angle)),
                y: Self.radius * CGFloat(1 - cos(angle))
            )
        }

        /// The recogniser's scale relative to where the gesture began.
        func scale(at seconds: Double) -> CGFloat {
            switch kind {
            case .pan:
                1
            case .mixed:
                1 + Self.pinchAmplitude * CGFloat(sin(2 * Double.pi * seconds / Self.pinchPeriod))
            }
        }
    }
#endif
