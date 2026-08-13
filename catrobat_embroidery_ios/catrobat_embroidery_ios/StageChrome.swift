import EmbroideryEngine
import SwiftUI

/// The stage's own colours — **fixed in both appearances**, unlike everything outside
/// the canvas.
///
/// The story's criterion says thread colours must not adapt to dark mode, because they
/// are design data, and that "only stage chrome is semantic-coloured". Taken literally
/// the second half is unimplementable, and the narrowing is worth stating because it is
/// not obvious: chrome drawn *on top of* a fixed stage field must be fixed too. A
/// semantic hoop outline over a fixed light field is a light line on a light field in
/// dark mode. So the rule that survives is:
///
/// > **Inside the canvas, everything is fixed. Outside the canvas, everything is
/// > semantic.**
///
/// "Contrast checked in both appearances" then becomes a *proof of invariance* inside
/// the canvas — there is one palette, so there is nothing to diverge — plus a real
/// two-appearance check only where the canvas meets the pane.
///
/// A fixed field is also the only way the dark-mode criterion can be honoured at all:
/// if the field adapted, the *same* design would be legible in one appearance and
/// invisible in the other, which is precisely the outcome "thread colours are design
/// data" exists to prevent. Design tools set the precedent — the artboard keeps its
/// colour while the app chrome darkens.
enum StageChrome {
    /// Inside the hoop: the "paper" the design is stitched on.
    ///
    /// A light neutral rather than a mid grey. Mid grey is the intuitive answer to
    /// "keep both black and white thread visible" and it is the wrong one — against the
    /// shipped square-coil palette it drops `#1d4ed8` to about 2:1 and `#f59e0b` to
    /// about 1.6:1, punishing the realistic saturated mid-luminance thread colours to
    /// buy two synthetic extremes. Against this field, black — `ColorState`'s default
    /// and so the app's most common thread — is about 14.6:1.
    static let hoopField = Color(red: 218 / 255, green: 215 / 255, blue: 208 / 255)

    /// Outside the hoop: the "mat".
    ///
    /// Its job is to make the hoop a *substrate* rather than just a line, so
    /// out-of-hoop stitches visibly sit off the fabric and the user learns what the
    /// boundary means on every run, before ever crossing it. Out-of-hoop thread stays
    /// fully legible on it (black is about 10.8:1) — being visible is the entire point
    /// of not clipping.
    static let outsideField = Color(red: 190 / 255, green: 186 / 255, blue: 178 / 255)

    /// The hoop outline and its corner ticks: about 8:1 against the paper and 6:1
    /// against the mat, so the boundary is carried by *contrast*, with the 1.35:1 step
    /// between the two fields as reinforcement only — never as the sole cue.
    static let hoopOutline = Color(red: 58 / 255, green: 56 / 255, blue: 51 / 255)

    /// Travel lines. See `travelOpacity`; the colour is the outline's, so there is one
    /// contrast pair to reason about rather than one per thread hue.
    static let travelLine = hoopOutline

    /// Traversals are drawn at reduced opacity **and** dashed, and the dash is the
    /// load-bearing half.
    ///
    /// The obvious alternative — the run's own colour, dimmed — was rejected on
    /// measurement: `#f59e0b` at 45% over the paper is about 1.2:1, which is nothing at
    /// all, and no single opacity works across every hue. The deeper reason is that a
    /// traversal is **not design data**: the machine trims travel, so thread-colour
    /// fidelity does not apply to it and it is chrome.
    ///
    /// Opacity and width are exactly what Increase Contrast undoes, so a *shape*
    /// difference is what keeps travel distinguishable from thread for low-vision
    /// users. Under Increase Contrast the dash stays and the opacity goes to 1.
    static let travelOpacity: Double = 0.6

    /// Constant in view points, never scaled by the transform — a boundary that grew
    /// with zoom could be mistaken for a very thick thread.
    static let hoopLineWidth: Double = 1.5

    /// The dash, in view points. Constant for the same reason as the width.
    static let travelDash: [CGFloat] = [3, 3]
}

extension Color {
    /// A thread colour, verbatim.
    ///
    /// No semantic colour, no appearance adaptation, no tinting: this is the one place
    /// design data crosses into SwiftUI and it must cross unchanged. `.sRGB`
    /// explicitly rather than by default, because the values are 8-bit sRGB
    /// components from a hex string the user typed (ADR-015) and interpreting them in
    /// any other space would shift the colour the machine will actually sew.
    init(_ threadColor: ThreadColor) {
        self.init(
            .sRGB,
            red: Double(threadColor.red) / 255,
            green: Double(threadColor.green) / 255,
            blue: Double(threadColor.blue) / 255
        )
    }
}
