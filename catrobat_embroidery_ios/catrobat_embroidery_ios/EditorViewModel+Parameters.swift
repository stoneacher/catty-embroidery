import EditorCore
import Foundation
import ProgramModel

/// One open parameter editor (US-410): the brick it edits, the undo session it coalesces into,
/// and the brick as it was when the editor opened.
///
/// `opening` is what "switch back to a number" restores, so a user who flips a slot to a
/// variable and back gets the number they started with rather than a default.
struct ParameterSession: Equatable {
    let address: BrickAddress
    let key: CoalescingKey
    let opening: Brick
    /// What a rejected number entry returns its slot to (`beginNumberEntry(for:)`).
    var numberAnchor: NumberAnchor?
}

/// A slot's literal as it stood when the number field started a typing run.
struct NumberAnchor: Equatable {
    let slot: ParameterSlot
    let value: Double
}

/// The parameter editor's edits (US-410). Every one goes through `apply(_:coalescing:)` with the
/// session's key, so the whole session is one undo entry (ADR-036) and every change still voids
/// the run and saves (ADR-038). **Live-apply** (decided 2026-10-03): nothing is buffered until
/// Done, so a sheet torn down by ADR-023's container swap loses nothing.
///
/// With no session open every method changes nothing, which is what makes a late write from a
/// torn-down sheet harmless (test-first item 6).
extension EditorViewModel {
    /// Whether the toolbar's Edit button is enabled: a brick is selected and it has something to
    /// edit.
    var canEditSelectedBrick: Bool {
        selectedBrickIndex.map(hasParameters(at:)) ?? false
    }

    /// Whether the brick at `index` in the first script has anything to edit — the row's
    /// "Edit Parameters" action is offered only then.
    func hasParameters(at index: Int) -> Bool {
        guard let bricks = program.scenes.first?.objects.first?.scripts.first?.bricks,
              bricks.indices.contains(index)
        else { return false }
        return !bricks[index].parameters.isEmpty
    }

    /// The brick the session edits, as it now stands.
    var editedBrick: Brick? {
        guard let address = parameterSession?.address else { return nil }
        return brick(at: address)
    }

    /// The variables the edited brick's object can reference, object scope first.
    var variableMenu: VariableMenu {
        VariableMenu(program: program, script: parameterSession?.address.script ?? ScriptAddress())
    }

    /// Replaces one slot of the edited brick. `nil`, changing nothing, with no session, or for a
    /// value the slot cannot hold — so the replacement that reaches the funnel is always the
    /// same kind (`Brick.replacing`), and ADR-035's guard stays a backstop (test-first item 10).
    @discardableResult
    func setParameter(_ slot: ParameterSlot, to value: ParameterValue) -> EditResult? {
        guard let session = parameterSession,
              let replacement = brick(at: session.address)?.replacing(slot, with: value)
        else { return nil }
        return apply(.replaceBrick(at: session.address, with: replacement), coalescing: session.key)
    }

    /// The number field's text: parsed for the locale and committed, or the reason it was not.
    /// `nil` means committed — or, with no session, that there was nothing to commit to.
    ///
    /// A rejection returns the slot to the anchor `beginNumberEntry(for:)` recorded, so the
    /// brick never keeps a value the user typed past.
    func enterNumber(_ text: String, for slot: ParameterSlot) -> FormulaLiteralError? {
        switch NumberEntry.parse(text, decimalSeparator: decimalSeparator) {
        case let .success(formula):
            setParameter(slot, to: .formula(formula))
            return nil
        case let .failure(error):
            guard let session = parameterSession else { return nil }
            // Live-apply committed every prefix that parsed on the way here — typing `1e400`
            // commits `1e40` — so a rejection puts the slot back where the typing run began.
            // Within the session that nets the run to nothing (found on the simulator).
            if let anchor = session.numberAnchor, anchor.slot == slot {
                setParameter(slot, to: .formula(.number(anchor.value)))
            }
            return error
        }
    }

    /// The stepper. Only a literal steps, and only to a finite value — a value the document can
    /// save (ADR-037).
    func stepNumber(_ slot: ParameterSlot, by delta: Double) {
        guard case let .formula(.number(value)) = value(of: slot) else { return }
        let stepped = value + delta
        guard stepped.isFinite else { return }
        setParameter(slot, to: .formula(.number(stepped)))
        // A tap is a committed value, so a later rejected entry returns here rather than
        // silently discarding the taps. Only an anchor this slot already holds moves.
        if parameterSession?.numberAnchor?.slot == slot {
            beginNumberEntry(for: slot)
        }
    }

    /// Switches a variable slot back to a number: the number it held when the editor opened, or
    /// the kind's template default if it opened as something else (test-first item 7c).
    func switchToNumber(_ slot: ParameterSlot) {
        guard let session = parameterSession else { return }
        let seed = Self.number(in: session.opening, at: slot)
            ?? Self.number(in: BrickKind(of: session.opening).template()[0], at: slot)
        guard let seed else { return }
        setParameter(slot, to: .formula(.number(seed)))
    }

    /// Points a slot at the variable `name` — a formula slot as `.variable(name)`, a
    /// `setVariable`/`changeVariableBy` target as its name — declaring it first if nothing in
    /// scope does (declare on use, ADR-035 amendment).
    ///
    /// The name is trimmed, then validated **before** anything is applied, so a refused name
    /// declares nothing. The declaration and the replacement share the session's key: one undo
    /// entry, so undo can never leave a brick naming a variable it just un-declared.
    @discardableResult
    func useVariable(named name: String, for slot: ParameterSlot) -> EditResult? {
        guard let session = parameterSession else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // The character rules govern names this editor *creates*. A name the object can
        // already resolve — from a loaded file, say — is chosen, not created, so it is usable
        // whatever it contains; refusing it would offer a menu item that silently does nothing.
        let isDeclared = variableMenu.scope(of: trimmed) != nil
        if !isDeclared, case let .failure(problem) = VariableName.validate(trimmed) {
            return .rejected(.invalidVariableName(problem))
        }
        let value: ParameterValue = slot == .variableName ? .variableName(trimmed) : .formula(.variable(trimmed))
        guard brick(at: session.address)?.replacing(slot, with: value) != nil else { return nil }
        if !isDeclared {
            let declared = apply(
                .declareVariable(name: trimmed, script: session.address.script),
                coalescing: session.key
            )
            if case .rejected = declared {
                return declared
            }
        }
        return setParameter(slot, to: value)
    }

    /// `writeEmbroideryToFile`'s name, trimmed. An empty name is never written: the brick keeps
    /// the one it had, so the row never shows the `(empty)` placeholder because of this editor.
    func setFileName(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setParameter(.fileName, to: .fileName(trimmed))
    }

    // MARK: Reading

    private func brick(at address: BrickAddress) -> Brick? {
        let path = address.script
        guard program.scenes.indices.contains(path.sceneIndex) else { return nil }
        let objects = program.scenes[path.sceneIndex].objects
        guard objects.indices.contains(path.objectIndex) else { return nil }
        let scripts = objects[path.objectIndex].scripts
        guard scripts.indices.contains(path.scriptIndex) else { return nil }
        let bricks = scripts[path.scriptIndex].bricks
        return bricks.indices.contains(address.brickIndex) ? bricks[address.brickIndex] : nil
    }

    private func value(of slot: ParameterSlot) -> ParameterValue? {
        editedBrick?.parameters.first { $0.slot == slot }?.value
    }

    private static func number(in brick: Brick, at slot: ParameterSlot) -> Double? {
        guard case let .formula(.number(value)) = brick.parameters.first(where: { $0.slot == slot })?.value
        else { return nil }
        return value
    }
}
