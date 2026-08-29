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
    /// Whether the counter sits beside the field or beneath it.
    ///
    /// **`ViewThatFits` cannot express this**, which is worth pinning before someone
    /// "simplifies" the `AnyLayout` away: a `TextField` is horizontally greedy with no
    /// meaningful ideal width, so a horizontal candidate either always fits or never does.
    /// The switch has to be driven by a value, and this is it.
    ///
    /// The threshold is the accessibility-sizes boundary, and the arithmetic behind it:
    /// on a 393 pt compact width, minus 32 pt of padding and 8 pt of spacing, 353 pt is
    /// shared between field and counter. At AX1 the counter ("14/15" at scaled caption) is
    /// about 55 pt, leaving roughly 298 pt — about twelve characters of 28 pt text, so a
    /// 15-character name truncates. That is the truncation the criterion forbids.
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
    /// Only the *first* scalar is named, matching `DesignName`'s "first offender" rule; a
    /// grapheme cluster whose first scalar is ASCII (`e` + a combining accent) is reported
    /// by the accent, which is the part that cannot be stored.
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
