/// Which way an `.accessibilityAdjustableAction` was swiped.
///
/// A named pair rather than SwiftUI's `AccessibilityAdjustmentDirection`, because
/// `StagePreview` is Foundation-only (ADR-022) and because "increment" says nothing about
/// which way a *zoom* goes. The app maps one onto the other in one line.
public enum StageZoomAdjustment: Hashable, Sendable {
    case zoomIn
    case zoomOut
}
