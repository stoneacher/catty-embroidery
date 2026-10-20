import EditorCore
import EmbroideryEngine
import Foundation
import ProgramModel

/// One row of the script list: what it says, how deep it sits, and what VoiceOver reads (US-407).
///
/// **A value, not a view**, for the reason `SampleRowView.accessibilityLabel(for:)` gives: the
/// label is the story's contract, and a label SwiftUI synthesises with `.combine` exists only
/// inside SwiftUI where no test can read it. The row view is a projection of this value, and
/// `.accessibilityElement(children: .ignore)` plus `accessibilityLabel` makes it exactly one
/// element — which is what the ROADMAP's "`.combine`" was asking for (ADR-039).
///
/// **Identity is the brick's index** (ADR-034). That is safe only while a row holds no
/// interactive control; a control inside a row is the named symptom that forces an identity
/// sidecar, and a reason to redesign the row rather than add the control quietly. US-408's
/// actions are not such a control: each is an `EditAction` computed from the program, held by
/// value, and rebuilt with every row.
///
/// Every sentence is a formatted String Catalog entry with the values interpolated into it —
/// never concatenated — because word order differs by language. The seven unit-bearing labels
/// have a plural twin (`brick.wait.count`, …) used when the value is a whole-number literal,
/// so the Wait template's own default reads "Wait 1 second".
nonisolated struct BrickRowPresentation: Equatable, Identifiable {
    /// The brick's index in its script.
    let id: Int
    let kind: BrickKind
    /// `Script.indentDepths[id]`: an end, and an If/Else's else, sits at its opener's depth.
    let depth: Int
    /// The visible sentence.
    let text: String
    /// `text`, plus how many loops and Ifs the brick sits inside — the indentation, spoken.
    let accessibilityLabel: String
    /// For an end row, the index of the block it closes; `nil` for every other row, and for an
    /// end whose opener is missing.
    let openerIndex: Int?
    /// For a thread-colour brick whose hex the stage would accept, the colour it stitches in.
    /// Parsed by `ThreadColor(hexString:)` — the parser the engine uses (ADR-015) — so the
    /// swatch never shows a colour the stitches will not have.
    let threadColor: ThreadColor?

    // MARK: What the row can do (US-408)

    /// Whether the row refuses a drag before it starts — `.moveDisabled`. `.onMove` has no
    /// reject hook, so a refusal after the drop springs the row back with no explanation.
    /// True for the drags `apply` always rejects: an end or an else (the block moves from its
    /// opener) and an opener that never closes (`.unbalancedPair`).
    let isMoveDisabled: Bool
    /// The accessibility actions, as the edits they make; `nil` where the action is not
    /// offered, so no row advertises an action that always fails. Computed by the package
    /// (`Script+ListEditing.swift`), never re-derived here. An end or an else offers only
    /// `delete` (decided 2026-09-29), which redirects to its opener.
    let moveUp: EditAction?
    let moveDown: EditAction?
    let moveOutAbove: EditAction?
    let moveOutBelow: EditAction?
    let moveIntoBlockAbove: EditAction?
    let moveIntoBlockBelow: EditAction?
    /// The crossing pair of an If/Else (Variables slice 2).
    let moveAboveElse: EditAction?
    let moveBelowElse: EditAction?
    let delete: EditAction?
    /// The offered moves above, each under the name VoiceOver reads for it, in rotor order:
    /// up, down, out, into, then the else pair. A move out of or into a block is named after
    /// that block's family, so "Move Above Loop" never moves a brick out of an If.
    let moveActions: [NamedMove]

    /// The rows for the program's first script, which is the only one M4 edits.
    ///
    /// Total: a program with no scene, object or script yields no rows rather than trapping.
    static func rows(for program: Program, locale: Locale = .current) -> [BrickRowPresentation] {
        guard let script = program.scenes.first?.objects.first?.scripts.first else {
            return []
        }
        let depths = script.indentDepths
        let enclosing = enclosingCounts(of: script)
        let text = Sentence(locale: locale)
        // The first script's address, matching the `guard` above.
        let address = ScriptAddress()

        return script.bricks.enumerated().map { index, brick in
            let opener = script.matchingOpener(ofEndAt: index)
            let sentence = text.of(brick, closing: opener.map { script.bricks[$0] })
            let moves = Moves(script: script, index: index, address: address)
            return BrickRowPresentation(
                id: index,
                kind: BrickKind(of: brick),
                depth: depths[index],
                text: sentence,
                accessibilityLabel: text.label(
                    sentence,
                    loops: enclosing[index].loops,
                    ifs: enclosing[index].ifs
                ),
                openerIndex: opener,
                threadColor: threadColor(of: brick),
                isMoveDisabled: brick.closesBlock || brick.isDivider
                    || (brick.opensBlock && script.range(ofPairAt: index) == nil),
                moveUp: moves.up,
                moveDown: moves.down,
                moveOutAbove: moves.outAbove,
                moveOutBelow: moves.outBelow,
                moveIntoBlockAbove: moves.intoAbove,
                moveIntoBlockBelow: moves.intoBelow,
                moveAboveElse: moves.aboveElse,
                moveBelowElse: moves.belowElse,
                delete: script.deleteAction(atOffsets: [index], in: address),
                moveActions: moves.named(locale: locale)
            )
        }
    }

    /// The sentence a brick reads as on its own row, outside any script. Used by the palette
    /// (US-409), so a palette row and the row it inserts read the same.
    ///
    /// No `loopEnd` reaches this from the palette. One that did reads "end of loop" with no
    /// opener, as an unmatched end does in a script.
    static func text(of brick: Brick, locale: Locale = .current) -> String {
        Sentence(locale: locale).of(brick, closing: nil)
    }

    /// How many loops and Ifs hold each row, one per row: the spoken indentation. An end and
    /// an else are counted outside their own block, as their depth is. Total on a malformed
    /// script: a stray end leaves the counts at zero.
    static func enclosingCounts(of script: Script) -> [(loops: Int, ifs: Int)] {
        var open: [BlockFamily] = []
        func counts(_ families: some Collection<BlockFamily>) -> (loops: Int, ifs: Int) {
            (families.count { $0 == .loop }, families.count { $0 == .conditional })
        }
        return script.bricks.map { brick in
            switch brick.blockRole {
            case let .opener(family):
                defer { open.append(family) }
                return counts(open)
            case .closer:
                if !open.isEmpty { open.removeLast() }
                return counts(open)
            case .divider:
                return counts(open.dropLast())
            case .leaf:
                return counts(open)
            }
        }
    }

    /// The swatch colour for a thread-colour brick; `nil` for every other brick.
    static func threadColor(of brick: Brick) -> ThreadColor? {
        guard case let .setThreadColor(hex) = brick else { return nil }
        return ThreadColor(hexString: hex)
    }
}

/// The catalog lookups, with the locale applied to every one so a test is deterministic.
nonisolated private struct Sentence {
    let locale: Locale

    func label(_ sentence: String, loops: Int, ifs: Int) -> String {
        switch (loops, ifs) {
        case (0, 0): sentence
        case (_, 0): resolve(.scriptRowAccessibilityNested(sentence, loops: loops))
        case (0, _): resolve(.scriptRowAccessibilityNestedIfs(sentence, ifs: ifs))
        default: resolve(.scriptRowAccessibilityNestedLoopsAndIfs(sentence, loops: loops, ifs: ifs))
        }
    }

    /// `opener` is the brick a `loopEnd` closes, if it has one.
    func of(_ brick: Brick, closing opener: Brick?) -> String {
        switch brick {
        case let .moveNSteps(steps):
            unit(steps, counted: LocalizedStringResource.brickMoveCount, formula: LocalizedStringResource.brickMove)
        case let .turnLeft(degrees):
            unit(
                degrees,
                counted: LocalizedStringResource.brickTurnLeftCount,
                formula: LocalizedStringResource.brickTurnLeft
            )
        case let .turnRight(degrees):
            unit(
                degrees,
                counted: LocalizedStringResource.brickTurnRightCount,
                formula: LocalizedStringResource.brickTurnRight
            )
        case let .pointInDirection(degrees):
            unit(
                degrees,
                counted: LocalizedStringResource.brickPointDirectionCount,
                formula: LocalizedStringResource.brickPointDirection
            )
        case let .placeAt(x, y): resolve(.brickPlaceAt(formula(x), formula(y)))
        case let .setX(value): resolve(.brickSetX(formula(value)))
        case let .setY(value): resolve(.brickSetY(formula(value)))
        case let .changeXBy(value): resolve(.brickChangeX(formula(value)))
        case let .changeYBy(value): resolve(.brickChangeY(formula(value)))
        // One whole sentence per side, so a language can inflect or reorder it.
        case let .arc(.left, radius, degrees): resolve(.brickArcLeft(formula(radius), formula(degrees)))
        case let .arc(.right, radius, degrees): resolve(.brickArcRight(formula(radius), formula(degrees)))
        case let .goThrough(throughX, throughY, x, y):
            resolve(.brickGoThrough(formula(throughX), formula(throughY), formula(x), formula(y)))
        case let .repeatLoop(times):
            unit(times, counted: LocalizedStringResource.brickRepeatCount, formula: LocalizedStringResource.brickRepeat)
        case .forever: resolve(.brickForever)
        case .loopEnd: loopEnd(closing: opener)
        // One sentence for both Ifs, as in Catroid; the palette description tells them apart.
        case let .ifThen(condition), let .ifElse(condition): resolve(.brickIf(formula(condition)))
        case .elseBranch: resolve(.brickIfElse)
        case .ifEnd: resolve(.brickIfEnd)
        case let .wait(seconds):
            unit(seconds, counted: LocalizedStringResource.brickWaitCount, formula: LocalizedStringResource.brickWait)
        case let .setVariable(name, value): resolve(.brickSetVariable(variable(name), formula(value)))
        case let .changeVariableBy(name, value): resolve(.brickChangeVariable(variable(name), formula(value)))
        case .stitch: resolve(.brickStitch)
        case let .setThreadColor(hex): resolve(.brickThreadColor(verbatim(hex)))
        case let .runningStitch(length): resolve(.brickRunningStitch(formula(length)))
        case let .zigZagStitch(length, width): resolve(.brickZigzagStitch(formula(length), formula(width)))
        case let .tripleStitch(length): resolve(.brickTripleStitch(formula(length)))
        case .sewUp: resolve(.brickSewUp)
        case .stopRunningStitch: resolve(.brickStopStitch)
        case let .writeEmbroideryToFile(name): resolve(.brickWriteFile(verbatim(name)))
        }
    }

    /// A loop's end repeats its opener's parameter, so it reads as the end of *that* loop.
    ///
    /// Exhaustive over the opener rather than `if case .repeatLoop`: `matchingOpener` returns
    /// only openers today, but a third loop brick should be a decision here, not a silent
    /// "End of loop".
    private func loopEnd(closing opener: Brick?) -> String {
        guard let opener else { return resolve(.brickLoopEndUnmatched) }
        switch opener {
        case let .repeatLoop(times):
            return unit(
                times,
                counted: LocalizedStringResource.brickLoopEndRepeatCount,
                formula: LocalizedStringResource.brickLoopEndRepeat
            )
        case .forever:
            return resolve(.brickLoopEndForever)
        case .moveNSteps, .turnLeft, .turnRight, .pointInDirection, .placeAt, .setX, .setY,
             .changeXBy, .changeYBy, .arc, .goThrough, .loopEnd, .wait, .ifThen, .ifElse, .elseBranch, .ifEnd,
             .setVariable, .changeVariableBy, .stitch, .setThreadColor, .runningStitch, .zigZagStitch,
             .tripleStitch, .sewUp, .stopRunningStitch, .writeEmbroideryToFile:
            return resolve(.brickLoopEndUnmatched)
        }
    }

    /// The plural form for a whole-number literal, the formula form for everything else.
    private func unit(
        _ value: Formula,
        counted: (Int) -> LocalizedStringResource,
        formula text: (String) -> LocalizedStringResource
    ) -> String {
        if let count = FormulaText.count(of: value) {
            return resolve(counted(count))
        }
        return resolve(text(formula(value)))
    }

    /// The variable a Set or Change Variable brick names: bare, as Catroid's spinner shows it —
    /// it is the brick's subject, not an operand, so there is no tree for it to be confused
    /// with. Only a formula quotes a variable.
    private func variable(_ name: String) -> String {
        name.isEmpty ? resolve(.scriptVariablePlaceholder) : name
    }

    /// A string parameter shown as stored — or, when empty, a placeholder, so the sentence is
    /// not left cut off ("Write embroidery to file "). Variables have their own placeholder.
    private func verbatim(_ text: String) -> String {
        text.isEmpty ? resolve(.scriptTextPlaceholder) : text
    }

    private func formula(_ formula: Formula) -> String {
        FormulaText.text(for: formula, locale: locale)
    }

    private func resolve(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }
}

/// One accessibility move under the name VoiceOver reads for it.
nonisolated struct NamedMove: Equatable {
    let title: String
    let action: EditAction
}

/// The package's moves for one row, and the family each move out of or into a block concerns.
nonisolated private struct Moves {
    let up, down, outAbove, outBelow, intoAbove, intoBelow, aboveElse, belowElse: EditAction?
    /// The block a move out leaves, and the blocks a move into enters.
    let enclosing, above, below: BlockFamily?

    init(script: Script, index: Int, address: ScriptAddress) {
        up = script.moveUpAction(ofBrickAt: index, in: address)
        down = script.moveDownAction(ofBrickAt: index, in: address)
        outAbove = script.moveOutAboveAction(ofBrickAt: index, in: address)
        outBelow = script.moveOutBelowAction(ofBrickAt: index, in: address)
        intoAbove = script.moveIntoBlockAboveAction(ofBrickAt: index, in: address)
        intoBelow = script.moveIntoBlockBelowAction(ofBrickAt: index, in: address)
        aboveElse = script.moveAboveElseAction(ofBrickAt: index, in: address)
        belowElse = script.moveBelowElseAction(ofBrickAt: index, in: address)
        let family = { (opener: Int?) in opener.flatMap { script.bricks[$0].blockFamily } }
        enclosing = family(script.enclosingOpener(ofBrickAt: index))
        above = family(script.previousSiblingIndex(ofBrickAt: index))
        below = family(script.nextSiblingIndex(ofBrickAt: index))
    }

    func named(locale: Locale) -> [NamedMove] {
        let entries: [(EditAction?, LocalizedStringResource)] = [
            (up, .scriptActionMoveUp),
            (down, .scriptActionMoveDown),
            (outAbove, enclosing == .conditional ? .scriptActionMoveAboveIf : .scriptActionMoveAboveLoop),
            (outBelow, enclosing == .conditional ? .scriptActionMoveBelowIf : .scriptActionMoveBelowLoop),
            (intoAbove, above == .conditional ? .scriptActionMoveIntoIfAbove : .scriptActionMoveIntoLoopAbove),
            (intoBelow, below == .conditional ? .scriptActionMoveIntoIfBelow : .scriptActionMoveIntoLoopBelow),
            (aboveElse, .scriptActionMoveAboveElse),
            (belowElse, .scriptActionMoveBelowElse)
        ]
        return entries.compactMap { action, title in
            action.map {
                var resource = title
                resource.locale = locale
                return NamedMove(title: String(localized: resource), action: $0)
            }
        }
    }
}
