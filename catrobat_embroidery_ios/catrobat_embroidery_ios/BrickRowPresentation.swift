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
    /// `Script.indentDepths[id]`: a `loopEnd` sits at its opener's depth.
    let depth: Int
    /// The visible sentence.
    let text: String
    /// `text`, plus how many loops the brick sits inside — the indentation, spoken.
    let accessibilityLabel: String
    /// For a `loopEnd`, the index of the loop it closes; `nil` for every other row, and for an
    /// end whose opener is missing.
    let openerIndex: Int?
    /// For a thread-colour brick whose hex the stage would accept, the colour it stitches in.
    /// Parsed by `ThreadColor(hexString:)` — the parser the engine uses (ADR-015) — so the
    /// swatch never shows a colour the stitches will not have.
    let threadColor: ThreadColor?

    // MARK: What the row can do (US-408)

    /// Whether the row refuses a drag before it starts — `.moveDisabled`. `.onMove` has no
    /// reject hook, so a refusal after the drop springs the row back with no explanation.
    /// True for the two drags `apply` always rejects: a `loopEnd` (the loop moves from its
    /// opener) and an opener that never closes (`.unbalancedPair`).
    let isMoveDisabled: Bool
    /// The accessibility actions, as the edits they make; `nil` where the action is not
    /// offered, so no row advertises an action that always fails. Computed by the package
    /// (`Script+ListEditing.swift`), never re-derived here. A `loopEnd` offers only `delete`
    /// (decided 2026-09-29), which redirects to its opener.
    let moveUp: EditAction?
    let moveDown: EditAction?
    let moveAboveLoop: EditAction?
    let moveBelowLoop: EditAction?
    let moveIntoLoopAbove: EditAction?
    let moveIntoLoopBelow: EditAction?
    let delete: EditAction?

    /// The rows for the program's first script, which is the only one M4 edits.
    ///
    /// Total: a program with no scene, object or script yields no rows rather than trapping.
    static func rows(for program: Program, locale: Locale = .current) -> [BrickRowPresentation] {
        guard let script = program.scenes.first?.objects.first?.scripts.first else {
            return []
        }
        let depths = script.indentDepths
        let text = Sentence(locale: locale)
        // The first script's address, matching the `guard` above.
        let address = ScriptAddress()

        return script.bricks.enumerated().map { index, brick in
            let opener = script.matchingOpener(ofLoopEndAt: index)
            let sentence = text.of(brick, closing: opener.map { script.bricks[$0] })
            return BrickRowPresentation(
                id: index,
                kind: BrickKind(of: brick),
                depth: depths[index],
                text: sentence,
                accessibilityLabel: text.label(sentence, depth: depths[index]),
                openerIndex: opener,
                threadColor: threadColor(of: brick),
                isMoveDisabled: brick.isLoopEnd || (brick.opensLoop && script.range(ofPairAt: index) == nil),
                moveUp: script.moveUpAction(ofBrickAt: index, in: address),
                moveDown: script.moveDownAction(ofBrickAt: index, in: address),
                moveAboveLoop: script.moveAboveLoopAction(ofBrickAt: index, in: address),
                moveBelowLoop: script.moveBelowLoopAction(ofBrickAt: index, in: address),
                moveIntoLoopAbove: script.moveIntoLoopAboveAction(ofBrickAt: index, in: address),
                moveIntoLoopBelow: script.moveIntoLoopBelowAction(ofBrickAt: index, in: address),
                delete: script.deleteAction(atOffsets: [index], in: address)
            )
        }
    }

    private static func threadColor(of brick: Brick) -> ThreadColor? {
        guard case let .setThreadColor(hex) = brick else { return nil }
        return ThreadColor(hexString: hex)
    }
}

/// The catalog lookups, with the locale applied to every one so a test is deterministic.
nonisolated private struct Sentence {
    let locale: Locale

    func label(_ sentence: String, depth: Int) -> String {
        depth == 0 ? sentence : resolve(.scriptRowAccessibilityNested(sentence, loops: depth))
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
        case let .repeatLoop(times):
            unit(times, counted: LocalizedStringResource.brickRepeatCount, formula: LocalizedStringResource.brickRepeat)
        case .forever: resolve(.brickForever)
        case .loopEnd: loopEnd(closing: opener)
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
             .changeXBy, .changeYBy, .loopEnd, .wait, .setVariable, .changeVariableBy, .stitch,
             .setThreadColor, .runningStitch, .zigZagStitch, .tripleStitch, .sewUp,
             .stopRunningStitch, .writeEmbroideryToFile:
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
