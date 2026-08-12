@testable import catrobat_embroidery_ios
import Foundation
import Samples
import Testing

/// What VoiceOver actually speaks for a picker row.
///
/// The story asks for one element per row carrying **both** the sample's name
/// and its description — not three elements the user has to swipe through. That
/// requirement has two halves and only one of them is a unit test:
///
/// - *One element* is structural (`.accessibilityElement(children: .ignore)`)
///   and is verified in the simulator with VoiceOver, because SwiftUI's
///   accessibility tree is not readable from a test.
/// - *The label's content* is a string, and it is a string precisely so that
///   this file can assert it. That is why the row exposes a pure static
///   producing it rather than relying on `.combine`, which synthesises a
///   correct-sounding label that exists only inside SwiftUI and can never be
///   read back.
///
/// The label is composed across **two** resource bundles: the name and summary
/// come from the `Samples` package's own `en.lproj/Localizable.strings`
/// (US-301's measured decision — SwiftPM does not run `xcstringstool` over an
/// `.xcstrings`), while the separator between them is an app-catalog entry.
/// That split is deliberate — the package owns the samples, the app owns their
/// presentation — and its cost is that a translator sees the two halves in two
/// different contexts.
@MainActor
struct SampleRowAccessibilityTests {
    @Test(arguments: SampleLibrary.all)
    func aRowsLabelNamesTheSampleAndThenDescribesIt(_ sample: SampleProgram) {
        let label = SampleRowView.accessibilityLabel(for: sample)
        let name = String(localized: sample.displayName)
        let summary = String(localized: sample.summary)

        #expect(!label.isEmpty)
        #expect(label.contains(name), "the label does not name the sample: \(label)")
        #expect(label.contains(summary), "the label does not describe the sample: \(label)")

        // "Localised" in this repo's sense: a `LocalizedStringResource` whose
        // catalog entry is missing renders as its own key, which looks like text
        // to a screenshot and to a human skimming the simulator.
        #expect(!label.contains(sample.nameKey))
        #expect(!label.contains(sample.descriptionKey))

        // The failure mode `AppStringsTests.theHoopSizeStringKeepsItsLiteralPartsAroundTheArguments`
        // documents, reached here for the same reason: when a parameterised
        // catalog entry goes missing, `xcstringstool` generates
        // `defaultValue: "\(arg1)\(arg2)"` — the literal parts vanish and only
        // the substituted values remain. No key survives in the output to
        // compare against, so "≠ its key" cannot catch it. Here the literal
        // *is* the separator, and losing it runs two sentences together with no
        // pause — audible to a VoiceOver user, invisible to every other check.
        #expect(label != name + summary, "the catalog entry collapsed to its arguments")

        // **Not asserted: that the name comes first.** It does in English, and
        // the entry is written with positional arguments so it reads that way by
        // default — but a translator is entitled to reorder them, and a test
        // that forbade this would be asserting English word order in a project
        // shipping ~75 languages. The order is a design decision recorded in the
        // catalog comment, not a property of the composition.
    }
}
