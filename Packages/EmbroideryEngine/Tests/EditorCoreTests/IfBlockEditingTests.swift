import EditorCore
import ProgramModel
import Testing

/// Variables slice 2 (brief D13, ADR-045 amendment): the editor verbs over If blocks. Insert
/// brings the whole template; an `elseBranch` or `ifEnd` is never inserted or moved on its
/// own; delete at either redirects to the opener when it resolves and is a leaf delete when it
/// does not (ADR-045's malformed-script rule).
///
/// ```
/// 0  moveNSteps(1)
/// 1  ifElse(1 < 2)   ─┐
/// 2    stitch          │ then-branch
/// 3  elseBranch        │
/// 4    sewUp           │ else-branch
/// 5  ifEnd           ─┘
/// 6  stopRunningStitch
/// ```
@Suite("If blocks in the editor")
struct IfBlockEditingTests {
    static let condition = Formula.binary(.smallerThan, .number(1), .number(2))
    static let bricks: [Brick] = [
        .moveNSteps(.number(1)), .ifElse(condition: condition), .stitch, .elseBranch, .sewUp, .ifEnd,
        .stopRunningStitch
    ]

    static func program(_ bricks: [Brick]) -> Program {
        Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: bricks)])])])
    }

    static func apply(_ action: EditAction, to bricks: [Brick] = bricks) -> EditResult {
        EditorCore.apply(action, to: program(bricks))
    }

    static func at(_ index: Int) -> BrickAddress {
        BrickAddress(brickIndex: index)
    }

    // MARK: - Templates and insertion

    /// Catroid's palette seeds `1 < 2` (`CategoryBricksFactory.kt:361-380`).
    @Test("an If template is the whole block, seeded with 1 < 2")
    func templates() {
        #expect(BrickKind.ifThen.template() == [.ifThen(condition: Self.condition), .ifEnd])
        #expect(BrickKind.ifElse.template() == [.ifElse(condition: Self.condition), .elseBranch, .ifEnd])
    }

    @Test("inserting an If/Else inserts the whole block")
    func insertIfElse() {
        #expect(Self.apply(.insert(.ifElse, at: Self.at(1)), to: [.stitch, .sewUp])
            == .applied(Self.program([.stitch, .ifElse(condition: Self.condition), .elseBranch, .ifEnd, .sewUp])))
    }

    @Test("an else or an If end is never inserted on its own", arguments: [BrickKind.elseBranch, .ifEnd])
    func markersAreNotInsertable(_ kind: BrickKind) {
        #expect(Self.apply(.insert(kind, at: Self.at(0))) == .rejected(.cannotInsertIfMarker(kind)))
        // Checked before the address, like `loopEnd`: the rule is the kind, not the place.
        #expect(Self.apply(.insert(kind, at: Self.at(99))) == .rejected(.cannotInsertIfMarker(kind)))
    }

    /// The insertion rule is positional (ADR-045): after the else means first in the else-branch.
    @Test("a palette tap after the else lands first in the else-branch")
    func insertAfterElse() {
        let script = Script(bricks: Self.bricks)
        let action = script.insertAction(of: .stitch, after: 3, in: ScriptAddress())
        #expect(action == .insert(.stitch, at: Self.at(4)))
        guard case let .applied(program) = Self.apply(action) else {
            Issue.record("not applied")
            return
        }
        #expect(program.scenes[0].objects[0].scripts[0].indentDepths[4] == 1)
    }

    // MARK: - Delete

    @Test("deleting at the opener, the else or the end removes the whole block", arguments: [1, 3, 5])
    func deleteRemovesTheBlock(_ index: Int) {
        #expect(Self.apply(.delete(at: Self.at(index)))
            == .applied(Self.program([.moveNSteps(.number(1)), .stopRunningStitch])))
    }

    /// ADR-045's malformed-script rule (Codex brief review, finding 4): no opener to redirect
    /// to, so the selected row goes as a leaf, and nothing else does.
    struct StrayDelete: Sendable {
        let bricks: [Brick], index: Int, expected: [Brick]
        init(_ bricks: [Brick], _ index: Int, _ expected: [Brick]) {
            (self.bricks, self.index, self.expected) = (bricks, index, expected)
        }
    }

    @Test("an else or end with no opener is deleted as a leaf", arguments: [
        StrayDelete([.stitch, .elseBranch, .sewUp], 1, [.stitch, .sewUp]),
        StrayDelete([.stitch, .ifEnd, .sewUp], 1, [.stitch, .sewUp]),
        StrayDelete([.forever, .elseBranch, .loopEnd], 1, [.forever, .loopEnd]),
        StrayDelete([.ifThen(condition: condition), .elseBranch, .ifEnd], 1, [.ifThen(condition: condition), .ifEnd]),
        StrayDelete([.forever, .stitch, .ifEnd], 2, [.forever, .stitch]),
        // Codex slice review of slice 2: an If/Else that closes but is malformed inside is no
        // block either, so its opener, end or else goes alone.
        StrayDelete([.ifElse(condition: condition), .stitch, .ifEnd, .sewUp], 2,
                    [.ifElse(condition: condition), .stitch, .sewUp]),
        StrayDelete([.ifElse(condition: condition), .stitch, .ifEnd, .sewUp], 0, [.stitch, .ifEnd, .sewUp]),
        StrayDelete([.ifElse(condition: condition), .elseBranch, .elseBranch, .ifEnd], 1,
                    [.ifElse(condition: condition), .elseBranch, .ifEnd]),
        StrayDelete([.ifElse(condition: condition), .elseBranch, .elseBranch, .ifEnd], 2,
                    [.ifElse(condition: condition), .elseBranch, .ifEnd]),
        // Codex handover review, round 2: the outer If does not resolve through a nested end of
        // the wrong family, so its end goes alone.
        StrayDelete([.ifThen(condition: condition), .forever, .ifEnd, .ifEnd, .stitch], 3,
                    [.ifThen(condition: condition), .forever, .ifEnd, .stitch]),
        // Round 3: a nested If/Else without its else does not let the outer If resolve either.
        StrayDelete([.ifThen(condition: condition), .ifElse(condition: condition), .ifEnd, .ifEnd], 3,
                    [.ifThen(condition: condition), .ifElse(condition: condition), .ifEnd])
    ])
    func strayMarkerIsALeaf(_ row: StrayDelete) {
        #expect(Self.apply(.delete(at: Self.at(row.index)), to: row.bricks) == .applied(Self.program(row.expected)))
    }

    /// The else of an If/Else that never closes resolves to an opener with no block, so the
    /// else itself goes — never the opener the user did not select.
    @Test("the else of an unclosed If/Else is deleted alone")
    func elseOfAnUnclosedIf() {
        let bricks: [Brick] = [.ifElse(condition: Self.condition), .stitch, .elseBranch, .sewUp]
        #expect(Self.apply(.delete(at: Self.at(2)), to: bricks)
            == .applied(Self.program([.ifElse(condition: Self.condition), .stitch, .sewUp])))
    }

    // MARK: - Move and replace

    @Test("an else or an If end is never moved", arguments: [3, 5])
    func markersDoNotMove(_ index: Int) {
        #expect(Self.apply(.move(from: Self.at(index), to: 0)) == .rejected(.cannotMoveIfMarker(at: Self.at(index))))
    }

    @Test("an If opener moves its whole block")
    func moveOpener() {
        #expect(Self.apply(.move(from: Self.at(1), to: 0))
            == .applied(Self.program([
                .ifElse(condition: Self.condition), .stitch, .elseBranch, .sewUp, .ifEnd, .moveNSteps(.number(1)),
                .stopRunningStitch
            ])))
    }

    @Test("an If/Else's condition is replaced in place; it never becomes an If")
    func replaceCondition() {
        let other = Formula.binary(.greaterThan, .variable("i"), .number(3))
        #expect(Self.apply(.replaceBrick(at: Self.at(1), with: .ifElse(condition: other)))
            == .applied(Self.program([
                .moveNSteps(.number(1)), .ifElse(condition: other), .stitch, .elseBranch, .sewUp, .ifEnd,
                .stopRunningStitch
            ])))
        #expect(Self.apply(.replaceBrick(at: Self.at(1), with: .ifThen(condition: other)))
            == .rejected(.cannotChangeBrickKind(from: .ifElse, to: .ifThen)))
    }

    // MARK: - Parameters and the document

    @Test("an If's one parameter is its condition")
    func conditionSlot() {
        let brick = Brick.ifThen(condition: Self.condition)
        #expect(brick.parameters == [BrickParameter(slot: .condition, value: .formula(Self.condition))])
        #expect(brick.replacing(.condition, with: .formula(.constant(.true))) == .ifThen(condition: .constant(.true)))
        #expect(Brick.elseBranch.parameters.isEmpty && Brick.ifEnd.parameters.isEmpty)
    }

    /// A condition is a formula like any other, so it counts toward ADR-037's depth cap.
    @Test("a too-deep condition is refused like any formula")
    func conditionDepth() {
        let deep = (1 ..< 129).reduce(Formula.number(0)) { tree, _ in .logicalNot(tree) }
        let program = Self.program([.ifThen(condition: deep), .ifEnd])
        #expect(throws: ProgramDocumentError.formulaTooDeep(limit: 128)) { _ = try ProgramDocument.encode(program) }
    }

    @Test("a malformed If is refused when the document is read")
    func malformedIsRefused() throws {
        let program = Self.program([.ifElse(condition: Self.condition), .stitch, .ifEnd])
        // Encoding refuses first; the decode half is the same `validate()` (ADR-037).
        #expect(throws: ProgramDocumentError.unbalancedScript(.missingElse(index: 0))) {
            _ = try ProgramDocument.encode(program)
        }
    }

    // MARK: - Indentation and siblings

    /// The else row sits at its opener's depth (D13), like the end.
    @Test("the else and the end sit at the opener's depth")
    func indentDepths() {
        #expect(Script(bricks: Self.bricks).indentDepths == [0, 0, 1, 0, 1, 0, 0])
        let nested = Script(bricks: [
            .forever, .ifElse(condition: Self.condition), .stitch, .elseBranch, .ifEnd, .loopEnd
        ])
        #expect(nested.indentDepths == [0, 1, 2, 1, 1, 0])
    }

    /// An else is a boundary, not a sibling: the then-branch's last block has no next sibling and
    /// the else-branch's first has no previous one.
    @Test("siblings stop at the else")
    func siblingsStopAtTheElse() {
        let script = Script(bricks: Self.bricks)
        #expect(script.nextSiblingIndex(ofBrickAt: 2) == nil)
        #expect(script.previousSiblingIndex(ofBrickAt: 4) == nil)
        #expect(script.nextSiblingIndex(ofBrickAt: 3) == nil, "the else is no block")
        #expect(script.previousSiblingIndex(ofBrickAt: 3) == nil)
        // The whole block is one sibling of its neighbours.
        #expect(script.nextSiblingIndex(ofBrickAt: 0) == 1)
        #expect(script.previousSiblingIndex(ofBrickAt: 6) == 1)
    }

    /// What the app labels a move-out by: the innermost block a row sits inside.
    @Test("a row's enclosing opener is the innermost block around it")
    func enclosingOpener() {
        let script = Script(bricks: Self.bricks)
        #expect(script.enclosingOpener(ofBrickAt: 2) == 1)
        #expect(script.enclosingOpener(ofBrickAt: 4) == 1, "past the else")
        #expect(script.enclosingOpener(ofBrickAt: 0) == nil)
        #expect(script.enclosingOpener(ofBrickAt: 1) == nil, "an opener is not inside itself")
        let nested = Script(bricks: [.forever, .ifThen(condition: Self.condition), .ifEnd, .stitch, .loopEnd])
        #expect(nested.enclosingOpener(ofBrickAt: 3) == 0, "past a closed sibling block")
        #expect(nested.enclosingOpener(ofBrickAt: 99) == nil)
    }

    @Test("an If end's opener is found past nested blocks")
    func matchingOpener() {
        let script = Script(bricks: [.ifThen(condition: Self.condition), .forever, .loopEnd, .ifEnd])
        #expect(script.matchingOpener(ofEndAt: 3) == 0)
        #expect(script.matchingOpener(ofEndAt: 2) == 1)
        #expect(Script(bricks: Self.bricks).matchingOpener(ofElseAt: 3) == 1)
        #expect(Script(bricks: [.forever, .elseBranch, .loopEnd]).matchingOpener(ofElseAt: 1) == nil)
        // An end of the other family resolves to nothing, not to the loop around it (found by
        // mutation: the leaf-delete fallback hid the difference).
        #expect(Script(bricks: [.forever, .stitch, .ifEnd]).matchingOpener(ofEndAt: 2) == nil)
        #expect(Script(bricks: [.ifThen(condition: Self.condition), .loopEnd]).matchingOpener(ofEndAt: 1) == nil)
        // …and an end whose opener does not resolve back to it, as `matchingEnd` sees it.
        #expect(Script(bricks: [.ifElse(condition: Self.condition), .ifEnd]).matchingOpener(ofEndAt: 1) == nil)
    }
}
