@testable import catrobat_embroidery_ios
import EditorCore
import ProgramModel
import Testing

/// US-408 test-plan items 9 and 9b: what each row lets the user do — whether it can be
/// dragged, and which accessibility actions it carries.
///
/// On the presentation value rather than the view, for `BrickRowPresentationTests`' reason:
/// `.moveDisabled` and `.accessibilityActions` exist only inside SwiftUI, where no test can
/// read them. The view projects these fields one to one.
struct BrickRowActionsTests {
    private static func rows(_ bricks: [Brick]) -> [BrickRowPresentation] {
        BrickRowPresentation.rows(for: Program(
            name: "",
            scenes: [Scene(objects: [Object(name: "Needle", scripts: [Script(bricks: bricks)])])]
        ))
    }

    /// A loop inside a loop, with a brick on each side — `BrickRowPresentationTests.nested`.
    ///
    /// ```
    /// 0  setVariable
    /// 1  repeat(10)   ─┐
    /// 2    move         │
    /// 3    repeat(4)  ─┐│
    /// 4      turn      ││
    /// 5    end        ─┘│
    /// 6  end          ──┘
    /// 7  stitch
    /// ```
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

    /// Item 9. `.onMove` has no reject hook — it is called after the drop — so a refusal there
    /// springs the row back unexplained. The honest version is refusing the drag up front.
    @Test("loop end rows cannot be dragged; every other row of a balanced script can")
    func loopEndsAreMoveDisabled() {
        #expect(Self.rows(Self.nested).map(\.isMoveDisabled) == [false, false, false, false, false, true, true, false])
    }

    /// The same refusal for the other drag `apply` always rejects: an opener with no end
    /// (`.unbalancedPair`). No row offers a gesture that can never succeed.
    @Test("an opener that is never closed cannot be dragged")
    func unclosedOpenerIsMoveDisabled() {
        #expect(Self.rows([.repeatLoop(times: .number(2)), .moveNSteps(.number(10))]).map(\.isMoveDisabled) == [
            true,
            false
        ])
    }

    /// Item 9b — **decided 2026-09-29: omitted.** Offering Move Up on an end row would be an
    /// action that returns `.cannotMoveLoopEnd` every time. Delete stays, and redirects.
    @Test("a loop end row offers Delete and no move", arguments: [5, 6])
    func loopEndRowsOfferOnlyDelete(index: Int) {
        let row = Self.rows(Self.nested)[index]

        #expect(row.moveUp == nil)
        #expect(row.moveDown == nil)
        #expect(row.moveAboveLoop == nil)
        #expect(row.moveBelowLoop == nil)
        #expect(row.moveIntoLoopAbove == nil)
        #expect(row.moveIntoLoopBelow == nil)
        #expect(row.delete == .delete(at: BrickAddress(brickIndex: index)))
    }

    /// The row carries exactly what the package computes for its index — no second copy of the
    /// arithmetic in the app to drift from the one the package tests pin.
    @Test("every row's actions are the script's own, for that row's index")
    func rowActionsAreThePackages() {
        let script = Script(bricks: Self.nested)
        let address = ScriptAddress()

        for row in Self.rows(Self.nested) {
            #expect(row.moveUp == script.moveUpAction(ofBrickAt: row.id, in: address), "row \(row.id)")
            #expect(row.moveDown == script.moveDownAction(ofBrickAt: row.id, in: address), "row \(row.id)")
            #expect(row.moveAboveLoop == script.moveAboveLoopAction(ofBrickAt: row.id, in: address), "row \(row.id)")
            #expect(row.moveBelowLoop == script.moveBelowLoopAction(ofBrickAt: row.id, in: address), "row \(row.id)")
            #expect(
                row.moveIntoLoopAbove == script.moveIntoLoopAboveAction(ofBrickAt: row.id, in: address),
                "row \(row.id)"
            )
            #expect(
                row.moveIntoLoopBelow == script.moveIntoLoopBelowAction(ofBrickAt: row.id, in: address),
                "row \(row.id)"
            )
            #expect(row.delete == script.deleteAction(atOffsets: [row.id], in: address), "row \(row.id)")
        }
    }

    /// Non-vacuity for the test above: on this fixture every action is offered somewhere, so
    /// "every row equals the package" cannot pass by both sides being `nil`.
    @Test("each kind of action is offered by some row")
    func everyActionIsOfferedSomewhere() {
        let rows = Self.rows(Self.nested)

        #expect(rows[3].moveUp == .move(from: BrickAddress(brickIndex: 3), to: 2))
        // Over the whole inner loop (3…5): with the brick removed, below its end is 5.
        #expect(rows[2].moveDown == .move(from: BrickAddress(brickIndex: 2), to: 5))
        #expect(rows[2].moveAboveLoop == .move(from: BrickAddress(brickIndex: 2), to: 1))
        // The inner loop is three bricks; with it removed, below the outer end (6) is 6 + 1 − 3.
        #expect(rows[3].moveBelowLoop == .move(from: BrickAddress(brickIndex: 3), to: 4))
        // Into the outer loop from above it, as its first brick; into it from below, as its last.
        #expect(rows[0].moveIntoLoopBelow == .move(from: BrickAddress(brickIndex: 0), to: 1))
        #expect(rows[7].moveIntoLoopAbove == .move(from: BrickAddress(brickIndex: 7), to: 6))
    }

    /// The review's fixture at the row level: the end of an **empty** loop sits right after its
    /// opener, a shape the nested fixture never has, and must still offer Delete alone.
    @Test("the end row of an empty loop offers Delete and no move")
    func emptyLoopEndOffersOnlyDelete() {
        let row = Self.rows([.stitch, .repeatLoop(times: .number(2)), .loopEnd])[2]

        #expect(row.isMoveDisabled)
        #expect([row.moveUp, row.moveDown, row.moveAboveLoop, row.moveBelowLoop,
                 row.moveIntoLoopAbove, row.moveIntoLoopBelow].allSatisfy { $0 == nil })
        #expect(row.delete == .delete(at: BrickAddress(brickIndex: 2)))
    }
}
