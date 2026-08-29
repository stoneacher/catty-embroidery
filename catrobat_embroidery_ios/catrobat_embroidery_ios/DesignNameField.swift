import EmbroideryEngine
import SwiftUI

/// The design-name field: a label, the field itself, a live counter, and the one sentence
/// saying what is wrong with what has been typed so far (US-308).
///
/// **Dumb by construction.** It owns no name, no validator and no commit: `ExportViewModel`
/// holds the string and recomputes the verdict, and the *commit* — the point at which a new
/// `.dst` is written — is the caller's, because it is a side effect. A caller attaches
/// `.onSubmit { … }` to this view and watches its own `@FocusState`; both propagate down and
/// up respectively, so no callback needs to be threaded through here.
///
/// The counter is *live* rather than a post-hoc error on purpose. Catroid silently
/// `take(15)`s the project name and mangles non-ASCII to `?` bytes under `US_ASCII`; the
/// user learns nothing until the machine displays a truncated label.
struct DesignNameField: View {
    /// Raw and unvalidated, because a `TextField` must accept anything the user can type.
    /// The verdict below is a *view* of this, never a second copy of it.
    @Binding var name: String

    /// Recomputed by the owner on every keystroke. Passed in rather than derived here so
    /// this view and the share control's gate cannot disagree about the same string.
    let validation: Result<DesignName, DesignNameProblem>

    /// Owned by the caller: focus loss is one of the two commit triggers, and only the view
    /// that declares the `@FocusState` can observe it.
    @FocusState.Binding var isFocused: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Counter beside the field, or beneath it at accessibility sizes.
    ///
    /// **`AnyLayout`, never `if`/`else`.** An `if`/`else` builds two different view trees, so
    /// a Dynamic Type change while the field is focused would destroy the `TextField` and
    /// dismiss the keyboard mid-edit. `AnyLayout` re-arranges the *same* subviews, so
    /// identity — and therefore focus and the insertion point — survives the switch.
    ///
    /// The policy itself lives in `DesignNameFieldLayout`, where it is assertable; nothing
    /// can read a hosted view's arrangement back out.
    private var arrangement: AnyLayout {
        DesignNameFieldLayout.axis(for: dynamicTypeSize) == .horizontal
            ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            arrangement {
                field
                counter
            }
            if case let .failure(problem) = validation {
                problemLine(problem)
            }
        }
    }

    /// The visible label. Hidden from VoiceOver because the field carries the **same**
    /// catalog entry as its own accessibility label — one entry cannot disagree with itself,
    /// where a duplicate element would simply read "Design name" twice before the field.
    private var title: some View {
        Text(.stageNameLabel)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    private var field: some View {
        TextField(text: $name, prompt: Text(.stageNamePrompt)) {
            Text(.stageNameLabel)
        }
        .textFieldStyle(.roundedBorder)
        .focused($isFocused)
        // **Mandatory, not polish.** iOS smart punctuation rewrites `'` as `’` (U+2019),
        // which `DesignName` then refuses as non-ASCII — the app would be blaming the user
        // for a character its own keyboard substituted.
        .autocorrectionDisabled()
        // A design name is not a sentence; auto-capitalising the first letter would silently
        // change what the machine displays.
        .textInputAutocapitalization(.never)
        // Offers the characters the format can actually store. A hint to the keyboard, never
        // a guarantee — paste and hardware keyboards go straight past it, which is why
        // `DesignName` validates rather than trusts.
        .keyboardType(.asciiCapable)
        // The field is not part of a multi-field flow: submitting means "done naming".
        .submitLabel(.done)
        // The HIG's 44 pt floor, from the constant `StageTransportRow` builds its row from
        // rather than a second literal. `minHeight` and never `height`: Dynamic Type may
        // only make it taller.
        .frame(minHeight: RunControl.minimumTouchTarget)
        .accessibilityLabel(Text(.stageNameLabel))
        // Spoken once, when focus lands. It states the rules — the limit and the character
        // class — precisely because the *count* must not be announced per keystroke.
        .accessibilityHint(Text(.stageNameAccessibilityHint(DesignName.maximumLength)))
    }

    /// "13/15", counted the way the validator counts (`DesignNameFieldLayout`), so the
    /// counter cannot read 15/15 while validation reports `.tooLong`.
    ///
    /// **Hidden from VoiceOver, deliberately.** VoiceOver already echoes each typed
    /// character; a counter in the value would make every keystroke read "a … 13 of 15".
    /// The limit is stated once by the field's hint, and a violation is stated by the
    /// message below — neither needs a per-keystroke number.
    private var counter: some View {
        Text(.stageNameCounter(DesignNameFieldLayout.characterCount(of: name), DesignName.maximumLength))
            .font(.caption)
            // So the row does not twitch as the digit widths change while typing.
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }

    /// What is wrong, in one sentence.
    ///
    /// `.red` is the *system* red — appearance-adaptive, unlike `StageChrome`'s fixed
    /// literals, and that is the rule rather than an exception to it: `StageChrome` fixes
    /// colours **inside** the canvas because they are design data, and everything outside it
    /// is semantic. This field is outside it.
    ///
    /// The icon is load-bearing, not decoration: colour alone must never carry meaning, and
    /// `exclamationmark.circle` rather than the `exclamationmark.triangle` the out-of-hoop
    /// notice uses, for the reason `StageView.limitNotice` records — two identical glyphs
    /// carrying different meanings on one screen is worse than no glyph at all.
    private func problemLine(_ problem: DesignNameProblem) -> some View {
        Label {
            Text(problem.message)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .multilineTextAlignment(.leading)
        // Wraps rather than ellipsising under a height-constrained proposal — the guard
        // `SamplePickerView`'s rows and the stage's notice block both needed.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hosts the field the way a caller does: a `@State` name and a `@FocusState` the field
/// cannot declare for itself.
private struct DesignNameFieldPreview: View {
    @State var name: String
    @FocusState private var isFocused: Bool

    var body: some View {
        DesignNameField(
            name: $name,
            validation: DesignName.validating(name),
            isFocused: $isFocused
        )
        .padding()
    }
}

#Preview("Valid name") {
    DesignNameFieldPreview(name: "Square coil")
}

#Preview("Rejected character") {
    DesignNameFieldPreview(name: "Gr\u{FC}\u{DF}e")
}
