@testable import catrobat_embroidery_ios
import Foundation
import Testing

/// Every user-facing string this story ships resolves to real English text.
///
/// The check that matters is `≠ key`: a `LocalizedStringResource` whose entry is
/// missing from the catalog renders as its own key, which looks like text to a
/// screenshot and to a human skimming the simulator. Only an assertion catches it.
///
/// These read the *generated symbols* (`.rootTitle`, …), which
/// `STRING_CATALOG_GENERATE_SYMBOLS` emits from `Localizable.xcstrings`. That is
/// deliberate and buys the property a grep cannot: a typo'd key is a **compile**
/// error here, not a silent fallback at runtime.
struct AppStringsTests {
    /// Deliberately **not** `@Test(arguments:)` over a stored array.
    ///
    /// `LocalizedStringResource` only conforms to `Sendable` from iOS 18, and this
    /// app targets iOS 17 (ADR-004), so a `static let` of them is a Swift 6
    /// concurrency warning today and an error the moment the language tightens.
    /// Building the pairs inside the test body keeps them off the global actor
    /// while preserving the property that matters — a typo'd symbol is a compile
    /// error — at the cost of one test case instead of five. The message on each
    /// expectation names the key, so a failure is still self-identifying.
    @Test func everyStringResolvesRatherThanFallingBackToItsKey() {
        let entries: [(resource: LocalizedStringResource, key: String)] = [
            (.rootTitle, "root.title"),
            (.rootSamplesHeader, "root.samples.header"),
            (.stageTitle, "stage.title"),
            (.stageEmptyTitle, "stage.empty.title"),
            (.stageEmptyDescription, "stage.empty.description"),
            // US-305. `stage.empty.*` survives alongside these: there are **two**
            // empty states, and they are not interchangeable — nothing selected
            // (reachable only in the regular-width detail column) against a design
            // selected but not yet run.
            (.stageReadyTitle, "stage.ready.title"),
            (.stageReadyDescription, "stage.ready.description"),
            (.stageOutsideHoop, "stage.outside.hoop"),
            (.stageCanvasAccessibilityLabel, "stage.canvas.accessibility.label"),
            // US-306. Three titles for one button, which is why they are listed
            // separately rather than folded together: `RunControlTests` additionally
            // pins that they are pairwise *distinct*, and that property is what a
            // VoiceOver user relies on to tell a finished run from one not yet started.
            (.stageRunPlay, "stage.run.play"),
            (.stageRunStop, "stage.run.stop"),
            (.stageRunPlayAgain, "stage.run.play.again"),
            // US-307. The three hints are listed individually rather than folded
            // together because `StageAccessibilityTests` additionally pins that they are
            // pairwise distinct, which is what criterion 5's "the hint describes the run
            // state" actually asks for.
            (.stageCanvasAccessibilityValueStitching, "stage.canvas.accessibility.value.stitching"),
            (.stageCanvasAccessibilityHintIdle, "stage.canvas.accessibility.hint.idle"),
            (.stageCanvasAccessibilityHintRunning, "stage.canvas.accessibility.hint.running"),
            (.stageCanvasAccessibilityHintFinished, "stage.canvas.accessibility.hint.finished"),
            (.stageCanvasAccessibilityActionFit, "stage.canvas.accessibility.action.fit")
        ]

        for entry in entries {
            let rendered = String(localized: entry.resource)
            #expect(!rendered.isEmpty, "\(entry.key) rendered empty")
            #expect(rendered != entry.key, "\(entry.key) fell back to its own key")
        }
    }

    /// The hoop-size string is parameterised, and its fallback is the failure mode
    /// worth pinning: when a catalog entry goes missing, `xcstringstool` generates
    /// `defaultValue: "\(arg1)\(arg2)"` — the *literal parts vanish* and only the
    /// substituted values remain. Asserting "≠ key" cannot catch that, because
    /// there is no key left in the output to compare against.
    ///
    /// The third expectation catches one more collapse than the second: an
    /// earlier version asserted only that the arguments survived and that the
    /// result was not the two of them concatenated, which **still passed** if the
    /// entry were reduced to `"%1$@ × %2$@"` — dropping the word "Hoop" and
    /// leaving the label meaningless.
    ///
    /// **What this still does not prove**, stated because two successive versions
    /// of this comment overclaimed and the review caught both: it does not prove
    /// a *descriptive* literal survives. A catalog value of `"%1$@ %2$@"` — the
    /// arguments separated by a plain space — passes all three expectations. The
    /// three assertions pin the two collapses `xcstringstool` can actually
    /// produce (total loss of literals, and separator-only), not the presence of
    /// the word "Hoop", which would mean asserting English wording in a file
    /// whose whole point is that the wording is translatable.
    @Test func theHoopSizeStringKeepsItsLiteralPartsAroundTheArguments() {
        let side = "100 mm"
        let rendered = String(localized: .stageHoopSize(side, side))

        #expect(rendered.contains(side))
        #expect(rendered != side + side, "the catalog entry collapsed to its arguments")
        #expect(
            rendered != "\(side) × \(side)",
            "the catalog entry kept its separator but lost its literal text"
        )
    }

    /// The stitch-limit notice is parameterised, so it needs the same treatment as the
    /// hoop-size string rather than the `≠ key` check: `xcstringstool`'s fallback for a
    /// missing entry is `defaultValue: "\(arg1)"`, which leaves the number and drops
    /// every word around it — and there is then no key left in the output to compare
    /// against.
    ///
    /// A `%lld` argument rather than `%@`: the count is an integer, and passing it as a
    /// string would push number formatting out of the catalog and into Swift, where a
    /// locale's digits and grouping separator are no longer the translator's to control.
    @Test func theStitchLimitNoticeKeepsItsLiteralPartsAroundTheCount() {
        let rendered = String(localized: .stageRunLimitNotice(200_000))

        #expect(!rendered.isEmpty)
        // The number survives, in whatever form the locale formats it — asserting the
        // exact digits would be asserting a locale, so this checks only that the
        // argument was substituted at all.
        let hasDigit = rendered.contains { $0.isNumber }
        let hasLetter = rendered.contains { $0.isLetter }

        #expect(hasDigit)
        // And the words around it survive: a collapsed entry would be the bare number.
        #expect(hasLetter, "the entry collapsed to its argument")

        // **Pluralised**, so the singular is a different string rather than "1 stitches".
        // The count is arbitrary — any value at or above the cap — and this is the catalog's
        // first numeric string, so it sets the pattern for a repo targeting ~75 languages
        // through Crowdin (`swift-code-reviewer`). Languages with dual/paucal forms cannot be
        // translated correctly from a single form, and the plural *categories* are the
        // translator's to add; what this pins is that the entry has variations at all.
        let singular = String(localized: .stageRunLimitNotice(1))
        #expect(singular != rendered, "the entry has no plural variations")
        #expect(singular.contains { $0.isLetter })
    }

    /// US-307's accessibility entries, in the collapse-detection idiom this file established
    /// for the hoop caption: when an entry goes missing, `xcstringstool` generates
    /// `defaultValue: "\(arg1)…"`, so the *literal parts vanish* and only the substituted
    /// values remain. "≠ key" cannot catch that, because no key is left in the output.
    @Test func theCanvasAccessibilityEntriesKeepTheirLiteralPartsAroundTheirArguments() {
        let named = String(localized: .stageCanvasAccessibilityLabelNamed("Octagon Rosette"))
        #expect(named.contains("Octagon Rosette"))
        #expect(named != "Octagon Rosette", "the entry collapsed to its argument")

        let size = String(localized: .stageCanvasAccessibilitySize("10 millimetres", "20 millimetres"))
        #expect(size.contains("10 millimetres"))
        #expect(size.contains("20 millimetres"))
        // A separator survives between them — the whole point of the entry, and what a
        // collapsed fallback loses.
        #expect(size != "10 millimetres20 millimetres")

        let zoom = String(localized: .stageCanvasAccessibilityZoom("300%"))
        #expect(zoom.contains("300%"))
        #expect(zoom != "300%")

        let zoomed = String(localized: .stageCanvasAccessibilityValueZoomed("Zoom 300%.", "3 stitches"))
        #expect(zoomed.contains("Zoom 300%."))
        #expect(zoomed.contains("3 stitches"))

        let value = String(localized: .stageCanvasAccessibilityValue("a", "b", "c"))
        #expect(value.contains("a"))
        #expect(value.contains("b"))
        #expect(value.contains("c"))
        #expect(value != "abc", "the entry collapsed to its arguments")
    }

    /// Both counts in the summary are pluralised **independently**.
    ///
    /// Asserted per count rather than over the composed sentence: a single assertion on the
    /// whole value passes when only one of the two entries has variations, which is exactly
    /// the half-done state a reviewer would miss. Languages with dual and paucal forms cannot
    /// be translated correctly from a single form, and the plural *categories* are the
    /// translator's to add — what this pins is that the entries have variations at all.
    @Test func bothSummaryCountsArePluralisedIndependently() {
        let oneStitch = String(localized: .stageCanvasAccessibilityStitches(1))
        let manyStitches = String(localized: .stageCanvasAccessibilityStitches(3194))
        #expect(oneStitch != manyStitches, "stage.canvas.accessibility.stitches has no plural variations")
        #expect(oneStitch.contains { $0.isLetter })

        let oneColour = String(localized: .stageCanvasAccessibilityColors(1))
        let manyColours = String(localized: .stageCanvasAccessibilityColors(4))
        #expect(oneColour != manyColours, "stage.canvas.accessibility.colors has no plural variations")
        #expect(oneColour.contains { $0.isLetter })

        // And the two entries are not the same string, which a copy-paste of one key into
        // both call sites would make them.
        #expect(oneStitch != oneColour)
    }
}
