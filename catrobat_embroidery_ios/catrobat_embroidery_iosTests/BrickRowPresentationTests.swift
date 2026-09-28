@testable import catrobat_embroidery_ios
import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel
import Samples
import Testing

/// US-407 test-plan items 1–5, 7, 7b and 8: what each row of the script list says.
///
/// Asserted on the presentation value, never on a view — the view is a projection of these
/// rows, and SwiftUI's accessibility tree cannot be read from a test (see
/// `SampleRowAccessibilityTests` for why the row carries an explicit label rather than
/// `.combine`).
///
/// **Exact English strings**, with the locale pinned. The story's "non-empty, localised,
/// contains the parameter values" is the floor, and it is asserted separately for every
/// `BrickKind` below; the exact strings are what additionally catch a catalog entry whose
/// literal parts collapsed (`AppStringsTests` documents that failure: a missing parameterised
/// entry renders as its arguments run together, which still "contains the values").
struct BrickRowPresentationTests {
    private static let english = Locale(identifier: "en_US")

    private static func rows(_ bricks: [Brick]) -> [BrickRowPresentation] {
        BrickRowPresentation.rows(for: program(bricks), locale: english)
    }

    private static func program(_ bricks: [Brick]) -> Program {
        Program(name: "", scenes: [Scene(objects: [Object(name: "Needle", scripts: [Script(bricks: bricks)])])])
    }

    /// A catalog key that failed to resolve renders as itself. Every key this story adds carries
    /// one of these prefixes, so a label containing one is a missing entry.
    private static func looksLikeARawKey(_ text: String) -> Bool {
        ["brick.", "formula.", "script."].contains { text.contains($0) }
    }

    // MARK: - 1, 2 — one row per brick, indented by `indentDepths`

    /// A loop inside a loop, with bricks before, between and after — every depth transition
    /// the list has to get right.
    private static let nested: [Brick] = [
        .setVariable(name: "n", to: .number(4)),
        .repeatLoop(times: .number(10)),
        .moveNSteps(.number(5)),
        .repeatLoop(times: .number(4)),
        .turnRight(.number(90)),
        .loopEnd,
        .loopEnd,
        .stitch
    ]

    @Test("one row per brick, in script order, identified by index")
    func oneRowPerBrickInOrder() {
        let rows = Self.rows(Self.nested)

        #expect(rows.count == Self.nested.count)
        #expect(rows.map(\.id) == Array(Self.nested.indices))
        #expect(rows.map(\.kind) == Self.nested.map(BrickKind.init(of:)))
    }

    @Test("each row's depth is `Script.indentDepths`, and a loop end sits at its opener's depth")
    func depthsAreIndentDepths() {
        let rows = Self.rows(Self.nested)

        #expect(rows.map(\.depth) == Script(bricks: Self.nested).indentDepths)
        #expect(rows.map(\.depth) == [0, 0, 1, 1, 2, 1, 0, 0])
    }

    // MARK: - The rosette, exactly

    /// Every claim of items 1–6 at once, over the sample a new user is most likely to open:
    /// two `.variable` loop counts, two `.binary` turns, and a loop nested in a loop.
    @Test("the Octagon Rosette renders exactly")
    func theRosetteRendersExactly() {
        let rows = BrickRowPresentation.rows(for: SampleLibrary[.octagonRosette].program, locale: Self.english)

        #expect(rows.map(\.text) == [
            "Set Inner Loop to 8",
            "Set Outer Loop to 8",
            "Start zigzag stitch with length 2 and width 10",
            "Repeat Outer Loop times",
            "Repeat Inner Loop times",
            "Move 100 steps",
            "Turn right 360 ÷ Inner Loop degrees",
            "End of repeat Inner Loop times",
            "Turn right 360 ÷ Outer Loop degrees",
            "End of repeat Outer Loop times"
        ])
        #expect(rows.map(\.depth) == [0, 0, 0, 0, 1, 2, 2, 1, 1, 0])
        #expect(rows.map(\.accessibilityLabel) == [
            "Set Inner Loop to 8",
            "Set Outer Loop to 8",
            "Start zigzag stitch with length 2 and width 10",
            "Repeat Outer Loop times",
            "Repeat Inner Loop times, inside 1 loop",
            "Move 100 steps, inside 2 loops",
            "Turn right 360 ÷ Inner Loop degrees, inside 2 loops",
            "End of repeat Inner Loop times, inside 1 loop",
            "Turn right 360 ÷ Outer Loop degrees, inside 1 loop",
            "End of repeat Outer Loop times"
        ])
        #expect(rows.map(\.openerIndex) == [nil, nil, nil, nil, nil, nil, nil, 4, nil, 3])
    }

    // MARK: - 3 — every label names the brick and its values

    /// The property the story states, over a row for every parameter shape the model has.
    /// `parameterTexts` is a test-local exhaustive switch, so a new `Brick` case with a
    /// parameter is a compile error here rather than a parameter this test forgets.
    @Test("every label is localised and contains each of its brick's parameter values")
    func labelsContainTheirValues() throws {
        let bricks = BrickKind.allCases.flatMap { $0.template() }
        let rows = Self.rows(bricks)
        try #require(rows.count == bricks.count)

        for (row, brick) in zip(rows, bricks) {
            #expect(!row.accessibilityLabel.isEmpty, "\(row.kind) has an empty label")
            #expect(!Self.looksLikeARawKey(row.accessibilityLabel), "\(row.kind): \(row.accessibilityLabel)")
            #expect(row.accessibilityLabel.contains(row.text), "\(row.kind): the label drops the visible sentence")
            for value in Self.parameterTexts(of: brick) {
                #expect(row.accessibilityLabel.contains(value), "\(row.kind): \(row.accessibilityLabel) lacks \(value)")
            }
        }
    }

    private static func parameterTexts(of brick: Brick) -> [String] {
        func formula(_ formula: Formula) -> String {
            FormulaText.text(for: formula, locale: english)
        }
        return switch brick {
        case let .moveNSteps(value), let .turnLeft(value), let .turnRight(value),
             let .pointInDirection(value), let .setX(value), let .setY(value),
             let .changeXBy(value), let .changeYBy(value):
            [formula(value)]
        case let .placeAt(x, y): [formula(x), formula(y)]
        case let .repeatLoop(times): [formula(times)]
        case let .wait(seconds): [formula(seconds)]
        case let .setVariable(name, value), let .changeVariableBy(name, value):
            [formula(.variable(name)), formula(value)]
        case let .setThreadColor(hex): [hex]
        case let .runningStitch(length), let .tripleStitch(length): [formula(length)]
        case let .zigZagStitch(length, width): [formula(length), formula(width)]
        case let .writeEmbroideryToFile(name): [name]
        case .forever, .loopEnd, .stitch, .sewUp, .stopRunningStitch: []
        }
    }

    // MARK: - 4 — a loop's end names its loop

    @Test("a repeat's end names the loop it closes, and points back at its opener")
    func aRepeatsEndNamesItsLoop() throws {
        let rows = Self.rows([.repeatLoop(times: .number(10)), .stitch, .loopEnd])
        try #require(rows.count == 3)

        #expect(rows[0].accessibilityLabel == "Repeat 10 times")
        #expect(rows[2].accessibilityLabel == "End of repeat 10 times")
        #expect(rows[2].openerIndex == 0)
        #expect(rows[0].openerIndex == nil, "an opener has no opener")
    }

    @Test("a forever's end reads as the end of forever")
    func aForeversEnd() throws {
        let rows = Self.rows([.forever, .stitch, .loopEnd])
        try #require(rows.count == 3)

        #expect(rows[0].text == "Forever")
        #expect(rows[2].text == "End of forever")
        #expect(rows[2].openerIndex == 0)
    }

    /// Loading refuses such a file (`Script.validate()`), so this is reachable only through a
    /// bug elsewhere — which is exactly when a row that says *something* true matters.
    @Test("a loop end with no opener reads as a bare loop end rather than crashing or naming a loop")
    func aStrayLoopEnd() throws {
        let rows = Self.rows([.stitch, .loopEnd])
        try #require(rows.count == 2)

        #expect(rows[1].text == "End of loop")
        #expect(rows[1].openerIndex == nil)
        #expect(rows[1].depth == 0)
    }

    @Test("an opener that is never closed still renders, and indents what follows")
    func anUnclosedOpener() {
        let rows = Self.rows([.repeatLoop(times: .number(2)), .stitch])

        #expect(rows.map(\.text) == ["Repeat 2 times", "Stitch"])
        #expect(rows.map(\.depth) == [0, 1])
    }

    // MARK: - 5 — nesting depth is spoken

    @Test("a top-level label is its sentence alone; a nested one says how deep, in the plural it needs")
    func depthIsSpoken() throws {
        let rows = Self.rows(Self.nested)
        try #require(rows.count == Self.nested.count)

        #expect(rows[0].accessibilityLabel == rows[0].text)
        #expect(rows[2].accessibilityLabel == "Move 5 steps, inside 1 loop")
        #expect(rows[4].accessibilityLabel == "Turn right 90 degrees, inside 2 loops")
    }

    // MARK: - Plurals

    /// The Wait template's own default is one second; without a plural form the first Wait
    /// brick anyone adds reads "Wait 1 seconds".
    @Test("a whole-number literal takes the singular or plural its value needs")
    func plurals() {
        let rows = Self.rows([
            .wait(seconds: .number(1)), .wait(seconds: .number(2)),
            .moveNSteps(.number(1)), .turnLeft(.number(1)), .turnRight(.number(1)),
            .pointInDirection(.number(1)), .repeatLoop(times: .number(1)), .loopEnd
        ])

        #expect(rows.map(\.text) == [
            "Wait 1 second", "Wait 2 seconds",
            "Move 1 step", "Turn left 1 degree", "Turn right 1 degree",
            "Point in direction 1 degree", "Repeat 1 time", "End of repeat 1 time"
        ])
    }

    /// A formula has no count to agree with, so it keeps the plural form, and so does a
    /// fraction — English says "0.5 seconds".
    @Test("a fraction or a formula reads in the plural")
    func nonIntegralValuesArePlural() {
        let rows = Self.rows([
            .wait(seconds: .number(0.5)),
            .wait(seconds: .variable("t")),
            .moveNSteps(.binary(.mult, .number(2), .variable("n")))
        ])

        #expect(rows.map(\.text) == ["Wait 0.5 seconds", "Wait t seconds", "Move 2 × n steps"])
    }

    @Test("a negative whole number keeps the formula form and its minus sign")
    func negativeWholeNumber() {
        #expect(Self.rows([.moveNSteps(.number(-5))]).map(\.text) == ["Move \u{2212}5 steps"])
    }

    /// Deterministic on any simulator: the English catalog with a German decimal comma. Before
    /// this, dropping the locale on its way to `FormulaText` was caught only because the review
    /// simulator's region happened to use a comma (`swift-code-reviewer`, M13).
    @Test("the locale reaches every value in the row")
    func localeReachesValues() {
        let rows = BrickRowPresentation.rows(
            for: Self.program([.wait(seconds: .number(0.5)), .placeAt(x: .number(1.5), y: .number(2.5))]),
            locale: Locale(identifier: "de_DE")
        )
        #expect(rows.map(\.text) == ["Wait 0,5 seconds", "Place at x: 1,5 y: 2,5"])
    }

    /// Reachable through a file today and through US-410's editors later; "Write embroidery to
    /// file " reads as a sentence cut off.
    @Test("an empty name or colour reads as empty rather than as a cut-off sentence")
    func emptyStrings() {
        let rows = Self.rows([.writeEmbroideryToFile(name: ""), .setThreadColor(hex: "")])

        #expect(rows.map(\.text) == ["Write embroidery to file (empty)", "Set thread colour to (empty)"])
    }

    // MARK: - Thread colour swatch

    @Test("a thread colour row carries the colour the stage would stitch in; no other row does")
    func threadColourSwatch() throws {
        let rows = Self.rows([.setThreadColor(hex: "#ff0000"), .stitch, .setThreadColor(hex: "not a colour")])
        try #require(rows.count == 3)

        #expect(rows[0].threadColor == ThreadColor(red: 255, green: 0, blue: 0))
        #expect(rows[1].threadColor == nil)
        #expect(rows[2].threadColor == nil, "an unparseable hex shows no swatch rather than a wrong one")
        #expect(rows[2].text == "Set thread colour to not a colour", "but its text still says what the brick holds")
    }

    // MARK: - 7 — every kind, not only what the samples happen to contain

    /// The coverage guard. Neither sample contains `forever`, `wait`, `placeAt` or `setX`, so a
    /// renderer returning an empty label for `.wait` would pass a samples-only test. The
    /// expected strings are an exhaustive switch, so a new `BrickKind` fails to compile here.
    @Test("every brick kind's template renders", arguments: BrickKind.allCases)
    func everyKindRenders(_ kind: BrickKind) {
        let expected: [String] = switch kind {
        case .moveNSteps: ["Move 10 steps"]
        case .turnLeft: ["Turn left 15 degrees"]
        case .turnRight: ["Turn right 15 degrees"]
        case .pointInDirection: ["Point in direction 90 degrees"]
        case .placeAt: ["Place at x: 100 y: 200"]
        case .setX: ["Set x to 100"]
        case .setY: ["Set y to 200"]
        case .changeXBy: ["Change x by 10"]
        case .changeYBy: ["Change y by 10"]
        case .repeatLoop: ["Repeat 10 times", "End of repeat 10 times"]
        case .forever: ["Forever", "End of forever"]
        case .loopEnd: ["End of loop"]
        case .wait: ["Wait 1 second"]
        case .setVariable: ["Set (no variable) to 1"]
        case .changeVariableBy: ["Change (no variable) by 1"]
        case .stitch: ["Stitch"]
        case .setThreadColor: ["Set thread colour to #ff0000"]
        case .runningStitch: ["Start running stitch with length 10"]
        case .zigZagStitch: ["Start zigzag stitch with length 2 and width 10"]
        case .tripleStitch: ["Start triple stitch with length 10"]
        case .sewUp: ["Sew up"]
        case .stopRunningStitch: ["Stop running stitch"]
        case .writeEmbroideryToFile: ["Write embroidery to file embroidery.dst"]
        }

        #expect(Self.rows(kind.template()).map(\.text) == expected)
    }

    // MARK: - 7b — the samples, as a smoke test

    @Test("every shipped sample renders a full set of labels", arguments: SampleLibrary.all)
    func samplesRender(_ sample: SampleProgram) {
        let rows = BrickRowPresentation.rows(for: sample.program, locale: Self.english)

        #expect(!rows.isEmpty)
        for row in rows {
            #expect(!row.text.isEmpty)
            #expect(!Self.looksLikeARawKey(row.accessibilityLabel), "\(row.accessibilityLabel)")
        }
    }

    // MARK: - 8 — the empty program

    /// Passes against a stub returning `[]`, so it is proved by mutation, not by the red run.
    @Test("the blank program, and a program with no script at all, yield no rows")
    func emptyPrograms() {
        #expect(BrickRowPresentation.rows(for: .blank, locale: Self.english).isEmpty)
        #expect(BrickRowPresentation.rows(for: Program(name: "", scenes: []), locale: Self.english).isEmpty)
        #expect(BrickRowPresentation.rows(for: Program(name: "", scenes: [Scene()]), locale: Self.english).isEmpty)
    }

    /// The empty state names the action rather than a control: US-409 adds the button to
    /// `ContentUnavailableView`'s actions slot without changing this copy.
    @Test("the empty state invites the user to add a brick")
    func emptyStateCopy() {
        #expect(ScriptListView.emptyStateTitle == "No Bricks Yet")
        #expect(ScriptListView.emptyStateDescription == "Add a brick to start your design.")
    }
}
