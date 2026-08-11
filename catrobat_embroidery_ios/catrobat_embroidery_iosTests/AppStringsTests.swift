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
            (.stageEmptyDescription, "stage.empty.description")
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
    /// substituted values remain. So asserting "≠ key" would not catch it here;
    /// asserting the rendered string still contains its literal separator does.
    @Test func theHoopSizeStringKeepsItsLiteralPartsAroundTheArguments() {
        let rendered = String(localized: .stageHoopSize("100 mm", "100 mm"))
        #expect(rendered.contains("100 mm"))
        #expect(rendered != "100 mm100 mm", "the catalog entry's literal parts were dropped")
    }
}
