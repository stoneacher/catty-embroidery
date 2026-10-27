@testable import catrobat_embroidery_ios
import EditorCore
import Foundation
import ProgramModel
import Projects
import Samples
import Testing

/// What the project list shows (project management slice 7; brief D11, D12): the user's
/// projects newest first, an empty state only when there are no project files, the selection
/// following the window's project, and a refused file badged with only Delete to offer.
///
/// The view draws this value and decides nothing, so these tests are the list's behaviour. The
/// samples section is the view's and always present; emptiness is decided from the files
/// alone, so samples can never stand in for projects (or hide the empty state).
@MainActor
@Suite("Project list presentation")
struct ProjectListPresentationTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let english = Locale(identifier: "en_US")

    static func named(_ name: String) -> Program {
        var program = Program.blank
        program.name = name
        return program
    }

    static func file(
        _ number: Int,
        _ name: String,
        hoursAgo: Double = 1
    ) -> ProjectFile {
        ProjectFile(id: .fixed(number), inspection: .openable(named(name)), modified: now - hoursAgo * 3600)
    }

    static func refused(
        _ number: Int,
        _ reason: ProgramDocumentError,
        name: String?,
        hoursAgo: Double = 1
    ) -> ProjectFile {
        ProjectFile(id: .fixed(number), inspection: .refused(reason, name: name), modified: now - hoursAgo * 3600)
    }

    static func rows(_ content: ProjectListContent) -> [ProjectRow] {
        guard case let .rows(rows) = content else { return [] }
        return rows
    }

    // MARK: Order and emptiness

    @Test("projects are listed newest first")
    func newestFirst() {
        let content = ProjectListPresentation.content(
            files: [
                Self.file(1, "Old", hoursAgo: 30),
                Self.file(2, "New", hoursAgo: 1),
                Self.file(3, "Mid", hoursAgo: 5)
            ],
            openID: .fixed(9),
            showsSelection: true
        )

        #expect(Self.rows(content).map(\.name) == ["New", "Mid", "Old"])
    }

    @Test("projects edited at the same moment keep one order, whatever order the scan found them in")
    func tiesAreDeterministic() {
        let files = [Self.file(2, "B", hoursAgo: 1), Self.file(1, "A", hoursAgo: 1), Self.file(3, "C", hoursAgo: 1)]

        let forwards = ProjectListPresentation.content(files: files, openID: .fixed(9), showsSelection: true)
        let backwards = ProjectListPresentation.content(
            files: files.reversed(),
            openID: .fixed(9),
            showsSelection: true
        )

        #expect(Self.rows(forwards).map(\.id) == [.fixed(1), .fixed(2), .fixed(3)])
        #expect(forwards == backwards)
    }

    @Test("with no project files the list is empty")
    func emptyWithNoFiles() {
        let content = ProjectListPresentation.content(files: [], openID: .fixed(1), showsSelection: true)

        #expect(content == .empty)
    }

    @Test("a list holding only refused files is not empty")
    func refusedFilesCount() {
        let content = ProjectListPresentation.content(
            files: [Self.refused(1, .corrupt, name: nil)],
            openID: .fixed(9),
            showsSelection: true
        )

        #expect(Self.rows(content).map(\.id) == [.fixed(1)])
    }

    // MARK: Selection

    @Test("the window's project is selected, and no other", arguments: [1, 2])
    func selectionFollowsTheProject(open: Int) {
        let content = ProjectListPresentation.content(
            files: [Self.file(1, "A", hoursAgo: 1), Self.file(2, "B", hoursAgo: 2)],
            openID: .fixed(open),
            showsSelection: true
        )

        #expect(Self.rows(content).filter(\.isSelected).map(\.id) == [.fixed(open)])
    }

    @Test("a window holding a draft selects nothing")
    func aDraftSelectsNothing() {
        let content = ProjectListPresentation.content(
            files: [Self.file(1, "A")],
            openID: .fixed(9),
            showsSelection: true
        )

        #expect(Self.rows(content).allSatisfy { !$0.isSelected })
    }

    @Test("the compact stack shows no selection")
    func compactShowsNoSelection() {
        let content = ProjectListPresentation.content(
            files: [Self.file(1, "A")],
            openID: .fixed(1),
            showsSelection: false
        )

        #expect(Self.rows(content).allSatisfy { !$0.isSelected })
    }

    // MARK: Refused rows (D11)

    @Test("an openable row has no badge and offers open, rename, duplicate and delete")
    func anOpenableRow() throws {
        let row = try #require(Self.rows(ProjectListPresentation.content(
            files: [Self.file(1, "Flower")], openID: .fixed(9), showsSelection: true
        )).first)

        #expect(row.badge == nil)
        #expect(row.actions == [.open, .rename, .duplicate, .delete])
    }

    @Test(
        "a refused row is badged by its reason and offers only delete",
        arguments: [
            (ProgramDocumentError.unsupportedVersion(2), ProjectBadge.needsNewerApp),
            (.unsupportedVersion(0), .damaged),
            (.corrupt, .damaged),
            (.encodingFailed, .damaged),
            (.unbalancedScript(.unmatchedLoopEnd(index: 0)), .damaged),
            (.formulaTooDeep(limit: 128), .damaged)
        ]
    )
    func aRefusedRow(reason: ProgramDocumentError, badge: ProjectBadge) throws {
        let row = try #require(Self.rows(ProjectListPresentation.content(
            files: [Self.refused(1, reason, name: "Flower")], openID: .fixed(9), showsSelection: true
        )).first)

        #expect(row.badge == badge)
        #expect(row.actions == [.delete])
        #expect(row.name == "Flower")
    }

    @Test("a refused file with no readable name is listed as unnamed")
    func anUnnamedRefusedRow() throws {
        let row = try #require(Self.rows(ProjectListPresentation.content(
            files: [Self.refused(1, .corrupt, name: nil)], openID: .fixed(9), showsSelection: true
        )).first)

        #expect(row.name == String(localized: .projectRowUnnamed))
        #expect(!row.name.isEmpty)
        #expect(row.name != "project.row.unnamed")
    }

    @Test("the two badges say different things, and neither is its key")
    func badgeTexts() {
        let newer = String(localized: ProjectBadge.needsNewerApp.label)
        let damaged = String(localized: ProjectBadge.damaged.label)

        #expect(newer != damaged)
        #expect(!newer.hasPrefix("project."))
        #expect(!damaged.hasPrefix("project."))
    }

    // MARK: Text (D12)

    @Test("the date is relative to now")
    func relativeDate() {
        let text = ProjectListPresentation.dateText(Self.now - 3600, now: Self.now, locale: Self.english)

        #expect(text == "1 hour ago")
    }

    /// The list reads `now` once a minute (`TimelineView(.everyMinute)`), so a file saved since
    /// the last tick is newer than `now`; it was edited just now, not "in 21 seconds".
    @Test("a file saved after the clock last ticked reads as edited now, not in the future")
    func aNewerFileIsNotInTheFuture() {
        let text = ProjectListPresentation.dateText(Self.now + 21, now: Self.now, locale: Self.english)

        #expect(text == ProjectListPresentation.dateText(Self.now, now: Self.now, locale: Self.english))
        #expect(!text.contains("in "))
    }

    @Test("the accessibility label is one sentence: the name, then when it was edited")
    func openableAccessibilityLabel() throws {
        let row = try #require(Self.rows(ProjectListPresentation.content(
            files: [Self.file(1, "Flower")], openID: .fixed(9), showsSelection: true
        )).first)

        let label = ProjectListPresentation.accessibilityLabel(for: row, now: Self.now, locale: Self.english)

        #expect(label == "Flower, edited 1 hour ago")
    }

    @Test("a refused row's label names the problem and says it can only be deleted")
    func refusedAccessibilityLabel() throws {
        let row = try #require(Self.rows(ProjectListPresentation.content(
            files: [Self.refused(1, .unsupportedVersion(2), name: "Flower")], openID: .fixed(9), showsSelection: true
        )).first)

        let label = ProjectListPresentation.accessibilityLabel(for: row, now: Self.now, locale: Self.english)

        #expect(label == "Flower, needs a newer app, edited 1 hour ago. It can only be deleted.")
    }
}
