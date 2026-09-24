import ProgramModel

/// The single funnel through which a program can change (ADR-006 pattern 1,
/// ADR-033).
///
/// `apply` is **pure, total and non-throwing**. Purity and totality are what let
/// undo (US-403), autosave (US-406) and run-invalidation (ADR-038) each hook into
/// one place and trust what they get; non-throwing is a deliberate divergence
/// from this repo's `movingPair`/`DSTHeader.init` precedent, because *every*
/// caller here branches on rejection and `try?` would discard the reason —
/// exactly the failure ADR-025 argues against. Those are boundary conversions
/// with one caller each; this is an inner funnel called on every keystroke, where
/// a rejection is ordinary control flow.
///
/// ## Balance is preserved, not enforced
///
/// For a program whose scripts all pass `Script.validate()`, every `.applied`
/// result does too — that is milestone exit criterion 4, and `.loopEnd` being
/// unmintable (ADR-035) is what makes it provable rather than merely tested. For
/// a program that is **already** unbalanced, `apply` does not repair it and does
/// not reject solely because of an unrelated imbalance. It may still refuse for
/// its own reasons: moving an opener whose `loopEnd` is missing stays
/// `.unbalancedPair`, because `movingPair` throws it and ADR-008 owns that rule.
public enum EditorCore {
    /// Apply one action, yielding a new program or the reason it was refused.
    ///
    /// The switch is exhaustive with **no `default:`** — the pattern
    /// `BrickKind.init(of:)` established. `EditAction` cannot be `CaseIterable`
    /// (its cases carry associated values), so this is what makes a new action
    /// case a *compile error* here rather than a silent gap, which is what
    /// milestone exit criterion 2 (every mutation is undoable) rests on.
    public static func apply(_ action: EditAction, to program: Program) -> EditResult {
        switch action {
        case let .insert(kind, address):
            // The kind guard runs **before** address resolution, so
            // `insert(.loopEnd, …)` answers one thing wherever it is aimed.
            guard kind != .loopEnd else { return .rejected(.cannotInsertLoopEnd) }
            return mutatingScript(of: program, at: address) { script in
                inserting(kind, at: address.brickIndex, in: script, address: address)
            }

        case let .delete(address):
            return mutatingScript(of: program, at: address) { script in
                deleting(at: address.brickIndex, in: script, address: address)
            }

        case let .move(address, destination):
            return mutatingScript(of: program, at: address) { script in
                moving(at: address.brickIndex, to: destination, in: script, address: address)
            }

        case let .replaceBrick(address, brick):
            return mutatingScript(of: program, at: address) { script in
                replacing(at: address.brickIndex, with: brick, in: script, address: address)
            }

        case let .renameProgram(name):
            var renamed = program
            renamed.name = name
            return .applied(renamed)
        }
    }

    // MARK: Resolution

    /// What one verb did to the script it was handed.
    ///
    /// Deliberately **not** `Result<Script, EditRejection>`, and the compiler is
    /// what settled it: `Result`'s failure type must conform to `Error`, and
    /// conforming `EditRejection` to `Error` would contradict the premise of
    /// ADR-033 — a rejection here is ordinary control flow, not something thrown
    /// — while quietly making `throw rejection` legal at every future call site.
    /// A four-line private enum keeps the divergence intact at the one place it
    /// would have been easiest to give up.
    private enum ScriptEdit {
        case edited(Script)
        case refused(EditRejection)
    }

    /// Resolve `address`'s three script hops, run `transform` on the script it
    /// names, and write the result back through the **same already-validated
    /// indices**.
    ///
    /// One traversal, shared by all four addressed cases. Resolution is
    /// outside-in, so an address wrong at several hops reports the outermost —
    /// and each hop names itself, which is what makes the bounds checks
    /// individually discriminating rather than collapsible into one `guard`.
    ///
    /// Rejected alternatives, recorded because both are the obvious ones: an
    /// optional-returning resolver loses *which* hop failed, and a separate
    /// `script(at:)` + `replacingScript(at:with:)` pair resolves twice and
    /// re-introduces an "unreachable nil" to force-unwrap. A private
    /// `throws(EditRejection)` helper would work and Swift 6 would even make it
    /// exhaustive, but it re-introduces inside this very function the shape
    /// ADR-033 deliberately diverged from, and weakens its third argument —
    /// that "every path returns a value" stays checkable by *reading* the code.
    private static func mutatingScript(
        of program: Program,
        at address: BrickAddress,
        _ transform: (Script) -> ScriptEdit
    ) -> EditResult {
        let path = address.script
        guard program.scenes.indices.contains(path.sceneIndex) else {
            return .rejected(.addressOutOfBounds(.scene, at: address))
        }
        let objects = program.scenes[path.sceneIndex].objects
        guard objects.indices.contains(path.objectIndex) else {
            return .rejected(.addressOutOfBounds(.object, at: address))
        }
        let scripts = objects[path.objectIndex].scripts
        guard scripts.indices.contains(path.scriptIndex) else {
            return .rejected(.addressOutOfBounds(.script, at: address))
        }

        switch transform(scripts[path.scriptIndex]) {
        case let .edited(edited):
            var updated = program
            updated.scenes[path.sceneIndex]
                .objects[path.objectIndex]
                .scripts[path.scriptIndex] = edited
            return .applied(updated)
        case let .refused(rejection):
            return .rejected(rejection)
        }
    }

    // MARK: The four verbs

    /// `brickIndex` is an **insertion** index here — `0 ... count`, so `count`
    /// appends and an empty script accepts `0`. Milestone exit criterion 1
    /// ("build a program from nothing") rests on the second half.
    ///
    /// No pair-awareness is needed at any index: `template()` always returns a
    /// complete balanced block, so inserting it between an opener and its own
    /// `loopEnd` nests rather than splits — the same argument ADR-008's
    /// 2026-07-20 clarification makes for the move.
    private static func inserting(
        _ kind: BrickKind,
        at index: Int,
        in script: Script,
        address: BrickAddress
    ) -> ScriptEdit {
        guard index >= 0, index <= script.bricks.count else {
            return .refused(.addressOutOfBounds(.brick, at: address))
        }
        var edited = script
        edited.bricks.insert(contentsOf: kind.template(), at: index)
        return .edited(edited)
    }

    /// ADR-035: at a loop opener this removes `range(ofPairAt:)` inclusive —
    /// opener, body and end (Catroid `BrickController.delete` parity); at a
    /// `loopEnd` it redirects to that end's own opener and does the identical
    /// thing.
    ///
    /// **On a malformed script an unresolvable control brick is deleted as a
    /// leaf** *(decision, Sebastian 2026-09-23, extending ADR-035, which pins
    /// only the balanced case)*. A stray `loopEnd` resolves to no opener and an
    /// unclosed opener resolves to no pair; rejecting either would leave a
    /// hand-edited file with a row the user cannot remove, which is the exact
    /// failure ADR-035 cited when it chose the redirect over a rejection. This is
    /// not the unsolicited repair the acceptance criterion forbids — the user
    /// asked for this row to go.
    ///
    /// **`delete` and `move` therefore diverge on the same malformed input**, and
    /// that is deliberate rather than an oversight: `move` delegates to
    /// `movingPair`, a `ProgramModel` primitive ADR-008 owns and that throws
    /// `.unbalancedPair`, so it stays rejected. `delete` has no such primitive.
    private static func deleting(
        at index: Int,
        in script: Script,
        address: BrickAddress
    ) -> ScriptEdit {
        guard script.bricks.indices.contains(index) else {
            return .refused(.addressOutOfBounds(.brick, at: address))
        }

        let head = script.bricks[index].isLoopEnd
            ? (script.matchingOpener(ofLoopEndAt: index) ?? index)
            : index

        var edited = script
        if let pair = script.range(ofPairAt: head) {
            edited.bricks.removeSubrange(pair)
        } else {
            edited.bricks.remove(at: head)
        }
        return .edited(edited)
    }

    /// A loop opener delegates to `Script.movingPair(at:to:)` — already tested,
    /// already ADR-008-blessed — and its error is normalised below rather than
    /// restated. A `loopEnd` is rejected: it is the one move that can split a
    /// pair. Anything else is a plain single-element move, which cannot change
    /// balance at any destination.
    ///
    /// The plain move is written here rather than added to `ProgramModel` as a
    /// `movingSingle` primitive: that target's public API is the serialized
    /// format (ADR-033), and this is four lines with no red test of its own over
    /// there.
    private static func moving(
        at index: Int,
        to destination: Int,
        in script: Script,
        address: BrickAddress
    ) -> ScriptEdit {
        // Source-side rules precede destination-side rules, so a `loopEnd` source
        // with a nonsense destination is deterministically `.cannotMoveLoopEnd`.
        guard script.bricks.indices.contains(index) else {
            return .refused(.addressOutOfBounds(.brick, at: address))
        }
        guard !script.bricks[index].isLoopEnd else {
            return .refused(.cannotMoveLoopEnd(at: address))
        }

        if script.bricks[index].opensLoop {
            do {
                return try .edited(script.movingPair(at: index, to: destination))
            } catch let error as ScriptMoveError {
                return .refused(normalising(error, at: address))
            } catch {
                // Unreachable: `movingPair` throws only `ScriptMoveError`. Swift
                // cannot express that — the declaration is untyped `throws` — so
                // this arm exists to keep `apply` total by inspection rather than
                // by faith. It refuses, because for an unknown refusal from the
                // model the safe direction is to keep the move rejected; the
                // alternative, trapping, is what ADR-033 forbids outright.
                return .refused(.scriptMove(.unbalancedPair(index: index)))
            }
        }

        var remaining = script.bricks
        let brick = remaining.remove(at: index)
        // The same post-removal convention `movingPair` documents, so
        // `EditAction.move` means one thing regardless of the brick at `from`.
        guard destination >= 0, destination <= remaining.count else {
            return .refused(.destinationOutOfBounds(index: destination))
        }
        remaining.insert(brick, at: destination)

        var edited = script
        edited.bricks = remaining
        return .edited(edited)
    }

    /// The same-kind guard runs **after** bounds resolution, which is forced
    /// rather than chosen: `from` cannot be computed without a brick to read it
    /// from. It is what makes this a *parameter* edit and keeps the pair
    /// invariant without re-validating, since `BrickKind` decides `opensLoop` and
    /// `isLoopEnd` outright (ADR-035).
    private static func replacing(
        at index: Int,
        with brick: Brick,
        in script: Script,
        address: BrickAddress
    ) -> ScriptEdit {
        guard script.bricks.indices.contains(index) else {
            return .refused(.addressOutOfBounds(.brick, at: address))
        }
        let existing = BrickKind(of: script.bricks[index])
        let replacement = BrickKind(of: brick)
        guard existing == replacement else {
            return .refused(.cannotChangeBrickKind(from: existing, to: replacement))
        }
        var edited = script
        edited.bricks[index] = brick
        return .edited(edited)
    }

    /// Map `movingPair`'s error into this target's vocabulary, so each failure has
    /// exactly one spelling. Exhaustive with no `default:`, so a new
    /// `ScriptMoveError` case is a compile error here rather than a silent
    /// re-wrap. See `EditRejection`'s documentation for the full argument.
    private static func normalising(
        _ error: ScriptMoveError,
        at address: BrickAddress
    ) -> EditRejection {
        switch error {
        case .sourceOutOfBounds:
            // Unreachable: `moving` bounds-checks the source before it can read
            // the brick that decides which kind of move this is.
            .addressOutOfBounds(.brick, at: address)
        case .sourceIsNotLoopOpener:
            // Unreachable: delegated to only once `opensLoop` is already true.
            .scriptMove(error)
        case let .destinationOutOfBounds(index):
            // Normalised, so the pair path and the leaf path answer alike.
            .destinationOutOfBounds(index: index)
        case .unbalancedPair:
            // The wrap ADR-033 asks for, and the only reachable arm.
            .scriptMove(error)
        }
    }
}
