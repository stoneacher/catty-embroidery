@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Testing

/// US-409's test-first item 1, the app half: what each palette row says and what VoiceOver
/// reads.
///
/// "Each row showing the brick as it will appear" is asserted literally: a row's text is the
/// text the *script list* gives the kind's template, so the palette and the script cannot read
/// differently. The locale is pinned, for `BrickRowPresentationTests`' reason.
struct PalettePresentationTests {
    private static let locale = Locale(identifier: "en_US")

    private static var sections: [PaletteSection] {
        PaletteSection.sections(locale: locale)
    }

    private static var rows: [PaletteRowPresentation] {
        sections.flatMap(\.rows)
    }

    /// What the script list shows for `kind`'s template as its first row.
    private static func scriptText(of kind: BrickKind) -> String? {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: kind.template())])])])
        return BrickRowPresentation.rows(for: program, locale: locale).first?.text
    }

    @Test("the sections are the package's groups, each with exactly its kinds, in order")
    func sectionsMirrorTheGroups() {
        #expect(Self.sections.map(\.id) == PaletteGroup.allCases)
        #expect(Self.sections.map { $0.rows.map(\.id) } == PaletteGroup.allCases.map(\.kinds))
    }

    @Test("every row reads as the script list will show the inserted brick")
    func rowTextIsTheScriptText() {
        #expect(!Self.rows.isEmpty)
        for row in Self.rows {
            #expect(row.text == Self.scriptText(of: row.id), "\(row.id)")
        }
    }

    /// Spot checks in English, so a row that resolved to a key — or to the wrong kind's
    /// sentence on both sides — still fails.
    @Test("rows read as the templates' English sentences")
    func englishSpotChecks() {
        let text = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0.id, $0.text) })
        #expect(text[.wait] == "Wait 1 second")
        #expect(text[.stitch] == "Stitch")
        #expect(text[.repeatLoop] == Self.scriptText(of: .repeatLoop))
        #expect(text[.repeatLoop]?.hasPrefix("Repeat") == true)
    }

    @Test("every row has its own non-empty description, resolved from the catalog")
    func descriptions() {
        let descriptions = Self.rows.map(\.description)
        #expect(descriptions.count == PaletteGroup.allCases.flatMap(\.kinds).count)
        for row in Self.rows {
            #expect(!row.description.isEmpty, "\(row.id)")
            #expect(!row.description.hasPrefix("palette."), "\(row.id) fell back to its key")
        }
        // A copy-pasted mapping gives two kinds one description.
        #expect(Set(descriptions).count == descriptions.count)
        let description = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0.id, $0.description) })
        #expect(description[.wait] == "Pauses before the next brick.")
        #expect(description[.repeatLoop] == "Repeats the bricks inside it a number of times.")
    }

    /// One element, naming the brick **and** what it does — in the label, not a hint, because
    /// hints can be turned off and the criterion asks the element itself to say it.
    @Test("each row's VoiceOver label is its text, then its description")
    func accessibilityLabel() {
        for row in Self.rows {
            #expect(row.accessibilityLabel == "\(row.text). \(row.description)", "\(row.id)")
        }
    }

    @Test("section titles are English, distinct and not keys")
    func sectionTitles() {
        #expect(Self.sections.map(\.title) == ["Embroidery", "Motion", "Control and Data"])
    }

    @Test("the thread colour row shows the template's colour, and no other row has a swatch")
    func threadColourSwatch() throws {
        let rows = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0.id, $0) })
        guard case let .setThreadColor(hex) = try #require(BrickKind.setThreadColor.template().first) else {
            Issue.record("the template is not a thread colour brick")
            return
        }
        #expect(try #require(rows[.setThreadColor]).threadColor == ThreadColor(hexString: hex))
        #expect(Self.rows.filter { $0.threadColor != nil }.map(\.id) == [.setThreadColor])
    }
}
