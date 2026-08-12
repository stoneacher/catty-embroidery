import Samples
import SwiftUI

/// The list of bundled designs, and the only thing in the app that starts a
/// selection.
///
/// **It owns no navigation container and never reads the size class.** That is
/// not tidiness: it is the mechanism by which `RootView`'s container swap loses
/// nothing. The same view is what the compact `NavigationStack`'s root and the
/// regular `NavigationSplitView`'s sidebar both render, so nothing has to
/// survive the swap by luck. US-303's compact-only "Stage" link — the last
/// size-class dependency inside this list — is deleted by this story, because a
/// row that navigates *is* the selection it was standing in for.
///
/// Deliberately thin, per the story: M5 owns the real project list
/// (create/rename/duplicate/delete), so picker surface built now is surface M5
/// must delete.
struct SamplePickerView: View {
    let model: AppModel

    /// Whether a selected row should *read* as selected.
    ///
    /// True only where the selection is visible next to the list — the split
    /// view's sidebar, where the detail column is showing that design, so the
    /// tint means "this is what you are looking at". In the compact stack it is
    /// false, because selecting pushes the stage and coming back leaves nothing
    /// on screen for a highlight to refer to. iOS clears a pushed row's
    /// highlight on return for exactly that reason (UIKit spells it
    /// `clearsSelectionOnViewWillAppear`), and a row that stays lit after Back
    /// claims a state the screen is not in. Reported from the simulator by
    /// Sebastian, 2026-08-12.
    ///
    /// **This is a flag, not a size-class read, and that is the point.** The
    /// container knows whether it displays the selection beside the list;
    /// `SamplePickerView` does not, and must not start branching on the
    /// environment — that would put back the size-class dependency whose
    /// absence is what makes the container swap lossless.
    ///
    /// Note what this does *not* change: `AppModel.selection` outlives the pop
    /// either way, which is deliberate and pinned by
    /// `AppModelTests.poppingTheStageKeepsTheSelection`. Only its *presentation*
    /// is conditional.
    let showsSelection: Bool

    var body: some View {
        List {
            Section {
                ForEach(model.samples) { sample in
                    let isSelected = showsSelection && model.isSelected(sample)

                    // A `Button`, **not** `List(selection:)`, and this is the
                    // story's load-bearing UI decision.
                    //
                    // `List(selection:)` would give the standard sidebar
                    // highlight for free. What it does not give is a guarantee
                    // that tapping the **already-selected** row writes the
                    // binding again — that is undocumented, collection-view
                    // backed behaviour, not an API contract. So with it, the
                    // acceptance criterion "re-selecting the same sample
                    // re-publishes it rather than being a no-op" would be
                    // unreachable through the UI while every unit test still
                    // passed: green, and wrong.
                    //
                    // **Three costs, all of them paid below rather than
                    // listed and shrugged at** — the first version of this
                    // comment named only the first, and the in-loop review
                    // found the two that matter more:
                    //
                    // 1. the selected-row tint is hand-rolled, so it
                    //    approximates the system's rather than following it;
                    // 2. `.plain` strips the pressed-state highlight a
                    //    `NavigationLink` gives free — restored by
                    //    `PickerRowButtonStyle` below, and *load-bearing here*,
                    //    because re-tapping the already-selected row in the
                    //    split layout otherwise produces no perceptible change
                    //    anywhere on screen, making the one interaction this
                    //    story exists to enable indistinguishable from a dead
                    //    row;
                    // 3. a `Button`'s hit area is its label, not the row, so
                    //    the list's own insets become dead zones — fixed by
                    //    zeroing `listRowInsets` and re-applying the padding
                    //    inside the label, where it is part of the target.
                    //
                    // `.onTapGesture` on a selectable row was the other way out
                    // and is worse: it competes with the list's own tap
                    // handling, wins inconsistently, and breaks keyboard
                    // selection.
                    Button {
                        model.select(sample)
                    } label: {
                        SampleRowView(sample: sample, isSelected: isSelected)
                    }
                    .buttonStyle(PickerRowButtonStyle())
                    // Zeroed so the label owns the row's full width and height;
                    // `SampleRowView` re-applies the spacing internally. Without
                    // this, a tap in the row's ~20 pt leading margin — where a
                    // thumb naturally lands — does nothing, while every stock
                    // iOS row responds edge to edge.
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
                }
            } header: {
                Text(.rootSamplesHeader)
            }
        }
        // Both containers set the same title on this view, so it belongs here
        // rather than being spelled twice in `RootView`'s branches, where the
        // two copies could drift.
        .navigationTitle(Text(.rootTitle))
        .navigationBarTitleDisplayMode(.inline)

        // **No empty state, and the omission is argued rather than skipped.**
        // The ROADMAP's M3+ definition of done says loading/empty/error states
        // ship with the feature. Here the empty state is unreachable by
        // construction: `SampleLibrary.all` is a `static let` array literal in
        // the same module as its builders, linked directly (ADR-022 — the app
        // never decodes anything, so there is no failure path that could yield
        // zero rows). `AppModelTests.thePickerOffersEverySampleInLibraryOrderAndNoneTwice`
        // is what turns "unreachable" into "asserted".
        //
        // The stronger reason not to build one: an empty picker would not mean
        // "you have no designs", it would mean the app shipped broken. Rendering
        // that honestly needs a sentence describing a build defect — and that
        // sentence would go to Crowdin for ~75 translations. If it were ever
        // reached, the honest render is a `ContentUnavailableView` saying the
        // bundled designs are missing and that reinstalling should fix it;
        // explicitly not a spinner, since nothing here loads.
        //
        // M5 is where an empty list becomes a real user state, and where
        // `ContentUnavailableView` earns its strings.
    }
}

/// One row: the design's name, and one line about what it looks like.
///
/// Internal rather than `private` so the tests can reach
/// `accessibilityLabel(for:)` — `@testable import` does not see `private`.
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
        // genuinely is the whole row — which the earlier version of this comment
        // claimed while the list's own insets were still dead zones.
        .contentShape(Rectangle())
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
        // appear on compact and not in the sidebar, and this view deliberately
        // does not know which it is in. The container tells it whether to show
        // *selection*, which is a fact about the container; "am I a stack"
        // is not, and threading it in would reintroduce the size-class
        // dependency whose absence is what makes the container swap lossless.
        // The checkmark above is unaffected: it comes from `showsSelection`,
        // which the container already states.
    }

    /// The exact string VoiceOver speaks for this row: the design's name, then
    /// what it looks like.
    ///
    /// A pure static — the same shape as
    /// `StagePlaceholderView.hoopSizeDescription`, and for the same two reasons.
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

/// Preview support: a model with the first sample already picked.
///
/// A function rather than statements inside `#Preview`, because that closure is
/// a `@ViewBuilder` and cannot hold a `let` and a mutation.
private func previewModelWithASelection() -> AppModel {
    let model = AppModel()
    if let first = SampleLibrary.all.first {
        model.select(first)
    }
    return model
}

// As the compact stack presents it: no selection shown, because coming back
// from the stage must not leave a row lit.
#Preview("In the stack") {
    NavigationStack {
        SamplePickerView(model: previewModelWithASelection(), showsSelection: false)
    }
}

// As the sidebar presents it. The selected-row treatment is hand-rolled, so this
// is the one thing on this screen a preview genuinely helps with.
#Preview("As a sidebar") {
    NavigationStack {
        SamplePickerView(model: previewModelWithASelection(), showsSelection: true)
    }
}
