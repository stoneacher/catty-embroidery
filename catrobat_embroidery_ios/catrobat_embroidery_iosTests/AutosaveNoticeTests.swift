@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Testing

/// The words the window uses about the saved program (US-406).
///
/// Resources are built inside each test body, never stored: `LocalizedStringResource` is not
/// `Sendable` before iOS 18 (see `AppStringsTests`).
@Suite("Autosave notice")
struct AutosaveNoticeTests {
    // MARK: Grouping

    @Test("every refusal reason falls into its copy group")
    func everyReasonHasItsGroup() {
        let groups: [(ProgramLoadError, AutosaveNotice.Cause)] = [
            (.document(.unsupportedVersion(2)), .newerApp),
            (.document(.corrupt), .damaged),
            (.document(.encodingFailed), .damaged),
            (.unreadable, .damaged),
            (.document(.unbalancedScript(.unmatchedLoopEnd(index: 0))), .blocksDontFit),
            (.document(.formulaTooDeep(limit: 128)), .blocksDontFit),
        ]
        for (reason, expected) in groups {
            #expect(AutosaveNotice.cause(of: reason) == expected, "\(reason)")
        }
    }

    // MARK: The alert

    /// The key pins which sentence each combination gets, without asserting English.
    @Test("each reason group and outcome has its own message")
    func eachCombinationHasItsOwnMessage() {
        let cases: [(ProgramLoadError, Bool, String)] = [
            (.document(.unsupportedVersion(2)), true, "autosave.refusal.message.newer.kept"),
            (.document(.unsupportedVersion(2)), false, "autosave.refusal.message.newer.paused"),
            (.document(.corrupt), true, "autosave.refusal.message.damaged.kept"),
            (.unreadable, false, "autosave.refusal.message.damaged.paused"),
            (.document(.formulaTooDeep(limit: 128)), true, "autosave.refusal.message.blocks.kept"),
            (.document(.formulaTooDeep(limit: 128)), false, "autosave.refusal.message.blocks.paused")
        ]
        for (reason, preserved, key) in cases {
            let refusal = ProgramRefusal(reason: reason, preserved: preserved)
            #expect(AutosaveNotice.message(for: refusal).key == key, "\(reason), preserved: \(preserved)")
        }
    }

    @Test("every alert and banner string resolves, and no two say the same thing")
    func everyStringResolvesAndIsDistinct() {
        let entries: [(resource: LocalizedStringResource, key: String)] = [
            (AutosaveNotice.refusalTitle, "autosave.refusal.title"),
            (.autosaveRefusalMessageNewerKept, "autosave.refusal.message.newer.kept"),
            (.autosaveRefusalMessageNewerPaused, "autosave.refusal.message.newer.paused"),
            (.autosaveRefusalMessageDamagedKept, "autosave.refusal.message.damaged.kept"),
            (.autosaveRefusalMessageDamagedPaused, "autosave.refusal.message.damaged.paused"),
            (.autosaveRefusalMessageBlocksKept, "autosave.refusal.message.blocks.kept"),
            (.autosaveRefusalMessageBlocksPaused, "autosave.refusal.message.blocks.paused"),
            (AutosaveNotice.banner(for: .saveFailed), "autosave.failure.save"),
            (AutosaveNotice.banner(for: .unpreservedDocument), "autosave.failure.paused"),
            (.programTitleUntitled, "program.title.untitled")
        ]
        let resolved = entries.map { String(localized: $0.resource) }
        for (entry, text) in zip(entries, resolved) {
            #expect(entry.resource.key == entry.key)
            #expect(!text.isEmpty && text != entry.key, "\(entry.key) fell back to its key")
        }
        #expect(Set(resolved).count == resolved.count)
    }

    /// The name passes through untouched — including a name that happens to spell a key.
    @Test("a restored program's name is its title verbatim")
    func theNamedTitleIsVerbatim() {
        #expect(String(localized: .programTitleNamed("Square Coil")) == "Square Coil")
        #expect(String(localized: .programTitleNamed("stage.title")) == "stage.title")
    }

    // MARK: The banner

    @Test("the two banners have different symbols")
    func theBannerSymbolsDiffer() {
        let save = AutosaveNotice.bannerSymbol(for: .saveFailed)
        let paused = AutosaveNotice.bannerSymbol(for: .unpreservedDocument)
        #expect(!save.isEmpty)
        #expect(!paused.isEmpty)
        #expect(save != paused)
    }
}
