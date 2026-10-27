@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects
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
            // Only a version above the app's own is "newer"; 0 or below is damage (slice 2 note).
            (.document(.unsupportedVersion(0)), .damaged),
            (.document(.unsupportedVersion(-1)), .damaged),
            (.document(.corrupt), .damaged),
            (.document(.encodingFailed), .damaged),
            (.unreadable, .damaged),
            (.document(.unbalancedScript(.unmatchedLoopEnd(index: 0))), .blocksDontFit),
            (.document(.formulaTooDeep(limit: 128)), .blocksDontFit)
        ]
        for (reason, expected) in groups {
            #expect(AutosaveNotice.cause(of: reason) == expected, "\(reason)")
        }
    }

    // MARK: The alert

    /// The key pins which sentence each group gets, without asserting English. A refused
    /// project file always stays where it is (brief D11), so every message is a "kept" one.
    @Test("each reason group has its own message")
    func eachGroupHasItsOwnMessage() {
        let cases: [(refusal: ProgramRefusal, key: String)] = [
            (.init(reason: .document(.unsupportedVersion(2))), "autosave.refusal.message.newer.kept"),
            (.init(reason: .document(.corrupt)), "autosave.refusal.message.damaged.kept"),
            (.init(reason: .unreadable), "autosave.refusal.message.damaged.kept"),
            (.init(reason: .document(.formulaTooDeep(limit: 128))), "autosave.refusal.message.blocks.kept")
        ]
        for (refusal, key) in cases {
            #expect(AutosaveNotice.message(for: refusal).key == key, "\(refusal)")
        }
    }

    @Test("every alert and banner string resolves, and no two say the same thing")
    func everyStringResolvesAndIsDistinct() {
        let entries: [(resource: LocalizedStringResource, key: String)] = [
            (AutosaveNotice.refusalTitle, "autosave.refusal.title"),
            (.autosaveRefusalMessageNewerKept, "autosave.refusal.message.newer.kept"),
            (.autosaveRefusalMessageDamagedKept, "autosave.refusal.message.damaged.kept"),
            (.autosaveRefusalMessageBlocksKept, "autosave.refusal.message.blocks.kept"),
            (AutosaveNotice.banner(for: .saveFailed), "autosave.failure.save"),
            (AutosaveNotice.banner(for: .refusedDocument), "autosave.failure.paused"),
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
        let paused = AutosaveNotice.bannerSymbol(for: .refusedDocument)
        #expect(!save.isEmpty)
        #expect(!paused.isEmpty)
        #expect(save != paused)
    }
}
