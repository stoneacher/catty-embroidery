import EmbroideryEngine
import SwiftUI

/// How the design-name field arranges itself, as a value rather than as layout.
///
/// **The story's definition of done — the counter moves below the field at AX1 rather than
/// truncating — cannot be checked by a test**, because nothing can read a hosted view's
/// arrangement back out. So the *policy* lives here and is asserted, and only its
/// application is left to the screenshot. That is the mitigation ADR-028 used for Reduce
/// Motion: hoist the decision out of `body` so it is both testable and impossible for two
/// views to disagree about.
enum DesignNameFieldLayout {
    /// Whether the counter sits beside the **label** or beneath it.
    ///
    /// **It used to govern the field's row, and moving it is the better fix** (Sebastian, on
    /// the running app): with the counter beside the field, the field was narrower than
    /// every other element in the column and the row read as off-centre. The counter now
    /// trails the label, so the field always spans the column — which means **a name can no
    /// longer be truncated by the counter at any size**, and this rule guards a wrapped
    /// label instead of a clipped name. US-308's definition of done said "the counter moves
    /// below the field at AX1"; it now moves below the *label*, and the truncation that
    /// criterion existed to prevent is unreachable by construction rather than avoided at
    /// one threshold.
    ///
    /// **`ViewThatFits` still cannot express it**, which is worth pinning before someone
    /// "simplifies" the `AnyLayout` away: the label is given `maxWidth: .infinity` so it
    /// pushes the counter to the trailing edge, and a greedy candidate always "fits". The
    /// switch has to be driven by a value, and this is it.
    ///
    /// The threshold is the accessibility-sizes boundary. At AX1 on a 393 pt compact width,
    /// "Design name" and "14/15" at scaled caption need roughly 300 pt together against the
    /// 361 pt available — close enough that a longer translation of the label overruns it,
    /// which is what stacking avoids.
    static func axis(for size: DynamicTypeSize) -> Axis {
        size.isAccessibilitySize ? .vertical : .horizontal
    }

    /// What the counter displays, counted the way the validator counts.
    ///
    /// Routed through `DesignName.normalised` rather than `name.count` so the field cannot
    /// read "15/15" while validation reports `.tooLong` — and so a trailing space, which is
    /// never going into the file, does not consume the user's budget.
    static func characterCount(of name: String) -> Int {
        DesignName.normalised(name).count
    }
}

extension DesignNameProblem {
    /// What the field says under itself.
    ///
    /// ADR-011 keeps user-facing wording in the app's String Catalog, so the engine's
    /// problem type carries data and this carries the sentence.
    var message: LocalizedStringResource {
        switch self {
        case .empty:
            .stageNameErrorEmpty
        // The typed count is deliberately *not* passed: the counter beside the field
        // already shows it, and a message repeating it is noise.
        case let .tooLong(_, limit):
            .stageNameErrorTooLong(limit)
        case let .unsupportedCharacter(character):
            .stageNameErrorCharacter(Self.describing(character))
        }
    }

    /// Renders the offending character for display, falling back to its code point when it
    /// has nothing to show.
    ///
    /// **The fallback is the case that actually happens.** A control character from a paste,
    /// a non-breaking space, or a zero-width space, quoted directly would produce
    /// `“ ” cannot be stored` —
    /// a message that appears to quote nothing, about a character the user cannot see in the
    /// field either. The code point at least identifies it.
    ///
    /// **The whole grapheme is shown, not the offending scalar** — an earlier version of
    /// this comment claimed the opposite, and cross-vendor round 4 falsified it: for
    /// `"e\u{0301}"`, `DesignName` reports the entire cluster `é`, and the visible `e` makes
    /// the invisibility test above false, so this returns `é`. That is the better answer
    /// anyway — it is what the user sees in the field — but the comment was describing code
    /// that does not exist. The code-point fallback applies only when the *whole* cluster has
    /// nothing to show.
    private static func describing(_ character: Character) -> String {
        // **Broadened after an in-loop review.** The rule is now printable ASCII, so the
        // offender can be an ASCII *control* character — `0x0A` and `0x1A` are the header's
        // own field terminators — and those are invisible without being whitespace or
        // default-ignorable, which is all the first version checked.
        let isInvisible = character.unicodeScalars.allSatisfy { scalar in
            scalar.properties.isWhitespace
                || scalar.properties.isDefaultIgnorableCodePoint
                || scalar.properties.generalCategory == .control
                || scalar.properties.generalCategory == .format
        }
        guard isInvisible, let scalar = character.unicodeScalars.first else {
            return String(character)
        }
        return String(format: "U+%04X", scalar.value)
    }
}
