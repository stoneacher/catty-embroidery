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

    var body: some View {
        List {
            Section {
                ForEach(model.samples) { sample in
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
                    // The cost is real and is paid below: the selected-row
                    // treatment is hand-rolled rather than the system's, so it
                    // approximates today's appearance and will not follow the
                    // platform's if that changes. Accepted, because an
                    // approximate highlight is a smaller defect than an
                    // acceptance criterion that cannot fire.
                    //
                    // `.onTapGesture` on a selectable row was the other way out
                    // and is worse: it competes with the list's own tap
                    // handling, wins inconsistently, and breaks keyboard
                    // selection.
                    Button {
                        model.select(sample)
                    } label: {
                        SampleRowView(sample: sample, isSelected: model.isSelected(sample))
                    }
                    // Without `.plain`, a `Button` in a list row tints its whole
                    // label with the accent colour — the sample's name would
                    // render blue.
                    .buttonStyle(.plain)
                    .listRowBackground(model.isSelected(sample) ? Color.accentColor.opacity(0.15) : nil)
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
        // `minHeight`, not `height` — a floor, not a size; `height` would clip at
        // the accessibility sizes. 44 is the HIG's physical thumb target and is
        // deliberately *not* `@ScaledMetric`: scaling a floor that exists for
        // anatomy would be scaling the wrong thing, and above roughly Large the
        // intrinsic content already exceeds it and the floor stops binding. It
        // is load-bearing at the *small* type sizes, where `.headline` plus
        // `.subheadline` come to well under 44 pt and only the default row
        // insets — a layout accident, not a promise — would otherwise carry it.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        // Makes the whole row tappable rather than just the text. Free inside a
        // `NavigationLink`; not free inside a `Button` with `.plain`.
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

        // **No disclosure chevron.** It comes free only from `NavigationLink`,
        // which cannot deliver the re-selection event this screen is built
        // around, and drawing one by hand costs an `HStack` that competes with
        // the text for width in ~75 languages at AX1 — while being wrong on
        // regular, where selecting fills the detail column rather than leaving
        // the screen. The story is explicitly thin; this is one of the places
        // that has to mean something.
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

#Preview("Nothing selected") {
    NavigationStack {
        SamplePickerView(model: AppModel())
    }
}

// The selected-row treatment is hand-rolled (see the `Button` comment above), so
// it is the one thing on this screen a preview genuinely helps with.
#Preview("One selected") {
    NavigationStack {
        SamplePickerView(model: previewModelWithASelection())
    }
}
