import Samples
import SwiftUI

/// One example row: the design's name, and one line about what it looks like.
///
/// Internal rather than `private` so the tests can reach
/// `accessibilityLabel(for:)` — `@testable import` does not see `private`.
///
/// Moved out of `SamplePickerView` when `ProjectListView` replaced it (project management
/// slice 7). `isSelected` stays although the new list always passes `false` — a picked sample
/// is a draft, not a row (brief, UI plan of 2026-10-27) — because the checkmark and trait are
/// the precedent `ProjectRowView` follows, and keeping them here keeps the two rows readable
/// side by side.
struct SampleRowView: View {
    let sample: SampleProgram
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.displayName)
                    .font(.headline)
                    // Prevents the failure mode that actually bites in a list row:
                    // the row proposes a *height* smaller than the text's ideal, and
                    // `Text` obeys by dropping lines and ellipsising rather than
                    // growing. Wrapping is already the default; this is what stops a
                    // height-constrained proposal from overriding it, and it is the
                    // AX1 no-truncation requirement's real guarantee.
                    .fixedSize(horizontal: false, vertical: true)

                Text(sample.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Explicit, because alignment is inherited: a future ancestor setting
            // `.center` would silently centre the wrapped lines. `.leading` is also
            // the only RTL-correct spelling.
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            // **Selection is not encoded in colour alone.** The tint behind the
            // row was the only sighted indicator until the in-loop review
            // measured it: system blue at 15 % over the dark grouped-list
            // background is roughly a 3 % luminance difference, the row
            // background does not respond to Increase Contrast, and a
            // blue-yellow deficiency removes it entirely — in a classroom, on
            // an iPad, at arm's length. A checkmark is the platform's own
            // selection affordance and, unlike a disclosure chevron, is correct
            // in the split layout, which is the only place this is shown at all.
            //
            // Hidden from VoiceOver because the `.isSelected` trait already
            // carries it; announcing both would say "selected" twice.
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .pickerRowLayout()
        // One VoiceOver element per row, carrying both lines — the story's
        // requirement, and by construction rather than by SwiftUI's merging
        // heuristics. `.ignore` plus an explicit label rather than `.combine`
        // for a reason that outlives taste: `.combine` synthesises a label that
        // exists only inside SwiftUI's accessibility tree and can never be read
        // back, so no test could assert what is spoken.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.accessibilityLabel(for: sample)))
        // Voice Control: without this, "tap Octagon Rosette" fails and the user
        // must speak the name *and* the whole description, because the combined
        // label is the only name the row has. One line, invisible to everyone
        // else, and a direct consequence of the single-element requirement.
        .accessibilityInputLabels([Text(sample.displayName)])
        // Selection is conveyed as a trait, never folded into the label text:
        // "Octagon Rosette, selected" would be untranslatable in word order and
        // would duplicate once VoiceOver speaks the trait itself.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        // **No disclosure chevron**, and the honest reason is structural rather
        // than aesthetic. On compact, selecting *does* leave the screen, so a
        // chevron would be the right affordance — the first version of this
        // comment argued only from the split layout and ignored that (in-loop
        // review). What actually rules it out is that a chevron would have to
        // appear on compact and not in the sidebar, and the list deliberately
        // does not know which it is in. The container tells it whether to show
        // *selection*, which is a fact about the container; "am I a stack"
        // is not, and threading it in would reintroduce the size-class
        // dependency whose absence is what makes the container swap lossless.
    }

    /// The exact string VoiceOver speaks for this row: the design's name, then
    /// what it looks like.
    ///
    /// A pure static — the same shape as
    /// `StageView.hoopSizeDescription`, and for the same two reasons. (It lived on
    /// `StagePlaceholderView` until US-305 replaced that view with the real renderer.)
    /// It is computed rather than stored because both lookups depend on the
    /// current locale, which can change while the app is running; and it is a
    /// *value* rather than a modifier so that a test can assert what is spoken.
    ///
    /// Name first because VoiceOver reads label → traits → hint in order, and
    /// the name is the token a user scanning the list is listening for: they can
    /// move on after two words instead of sitting through the description of the
    /// wrong row.
    ///
    /// The separator is a catalog entry, not a hand-written `", "`. Punctuation
    /// and word order differ per language, and the separator is what controls
    /// VoiceOver's pause. Note that the label is therefore composed across two
    /// bundles — name and summary from the `Samples` package, the joiner from
    /// the app's catalog — which is correct ownership (the package owns the
    /// samples, the app owns their presentation) at the cost of splitting the
    /// translator's context across two catalogs.
    static func accessibilityLabel(for sample: SampleProgram) -> String {
        String(localized: .rootSampleAccessibilityLabel(
            String(localized: sample.displayName),
            String(localized: sample.summary)
        ))
    }
}

extension View {
    /// The row frame the list's rows share (`SampleRowView`, `ProjectRowView`): one spelling,
    /// so an example row and a project row cannot drift to different heights or hit areas.
    func pickerRowLayout() -> some View {
        modifier(PickerRowLayout())
    }
}

/// The spacing, floor and hit shape of a list row whose label is a `Button`'s.
private struct PickerRowLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            // The row's own spacing, applied *inside* the label because the label is
            // the button's hit area — see `listRowInsets(EdgeInsets())` at the call
            // site. `.horizontal` is leading+trailing, so it mirrors in RTL.
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            // `minHeight`, not `height` — a floor, not a size; `height` would clip at
            // the accessibility sizes. 44 is the HIG's physical thumb target and is
            // deliberately *not* `@ScaledMetric`: scaling a floor that exists for
            // anatomy would be scaling the wrong thing, and above roughly Large the
            // intrinsic content already exceeds it and the floor stops binding. It
            // is load-bearing at the *small* type sizes, where `.headline` plus
            // `.subheadline` come to well under 44 pt.
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            // With the insets zeroed at the call site and re-applied above, this
            // genuinely is the whole row — which an earlier version of this comment
            // claimed while the list's own insets were still dead zones.
            .contentShape(Rectangle())
    }
}

/// A list row that looks like a list row and *feels* like one under the finger.
///
/// `.plain` renders the label untinted — without it a `Button` in a list row
/// paints the design's name accent-blue — but it also drops the pressed-state
/// highlight that `NavigationLink` and `List(selection:)` provide. That
/// omission is not cosmetic here: in the split layout, re-tapping the
/// already-selected row is the interaction this whole screen is shaped around,
/// and with no press feedback, no navigation and a tint that is already on, it
/// produces no perceptible change at all. The row would be indistinguishable
/// from a dead one while doing exactly what it is supposed to.
///
/// `.primary.opacity(0.06)` rather than a named grey so it holds up in both
/// appearances, and it sits *behind* the label so the text keeps full contrast
/// while pressed.
struct PickerRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? AnyShapeStyle(.primary.opacity(0.06)) : AnyShapeStyle(.clear))
    }
}
