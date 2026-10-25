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
    /// What a refused entry — a rejected number, a blank file name — returns its slot to
    /// (`beginNumberEntry(for:)`, `beginFileNameEntry()`).
    var entryAnchor: EntryAnchor?
}

/// A slot's value — or one side of a comparison's — as it stood when a text field started a
/// typing run. Live-apply commits every prefix that is valid, so a run that ends refused would
/// otherwise leave the last one behind. A side's anchor restores that side alone, so an operator
/// chosen during the run survives (Variables slice 7).
struct EntryAnchor: Equatable {
    let target: ParameterTarget
    let value: ParameterValue
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
        setParameter(.slot(slot), to: value)
    }

    /// Replaces one target: a slot, or one side of the comparison a condition holds
    /// (`Brick.replacing(_:with:)` for targets refuses anything that would reshape the tree).
    @discardableResult
    func setParameter(_ target: ParameterTarget, to value: ParameterValue) -> EditResult? {
        guard let session = parameterSession,
              let replacement = brick(at: session.address)?.replacing(target, with: value)
        else { return nil }
        return apply(.replaceBrick(at: session.address, with: replacement), coalescing: session.key)
    }

    /// The comparison editor's operator picker: both sides kept. `nil`, changing nothing, unless
    /// `slot` of the edited brick holds an editable comparison (Variables slice 7).
    @discardableResult
    func setComparisonOperator(_ relation: ComparisonOperator, in slot: ParameterSlot = .condition) -> EditResult? {
        guard let session = parameterSession,
              let replacement = brick(at: session.address)?.replacingComparisonOperator(in: slot, with: relation)
        else { return nil }
        return apply(.replaceBrick(at: session.address, with: replacement), coalescing: session.key)
    }

    /// The number field's text: parsed for the locale and committed, or the reason it was not.
    /// `nil` means committed — or, with no session, that there was nothing to commit to.
    ///
    /// A rejection returns the slot to the anchor `beginNumberEntry(for:)` recorded, so the
    /// brick never keeps a value the user typed past.
    func enterNumber(_ text: String, for slot: ParameterSlot) -> FormulaLiteralError? {
        enterNumber(text, for: .slot(slot))
    }

    func enterNumber(_ text: String, for target: ParameterTarget) -> FormulaLiteralError? {
        switch NumberEntry.parse(text, decimalSeparator: decimalSeparator) {
        case let .success(formula):
            // A target that cannot take it (a locked tree) leaves nothing to report.
            setParameter(target, to: .formula(formula))
            return nil
        case let .failure(error):
            guard let session = parameterSession else { return nil }
            // Live-apply committed every prefix that parsed on the way here — typing `1e400`
            // commits `1e40` — so a rejection puts the slot back where the typing run began.
            // Within the session that nets the run to nothing (found on the simulator).
            if let anchor = session.entryAnchor, anchor.target == target {
                setParameter(target, to: anchor.value)
            }
            return error
        }
    }

    /// The stepper. Only a literal steps, and only to a finite value — a value the document can
    /// save (ADR-037).
    func stepNumber(_ slot: ParameterSlot, by delta: Double) {
        stepNumber(.slot(slot), by: delta)
    }

    func stepNumber(_ target: ParameterTarget, by delta: Double) {
        guard case let .formula(.number(value)) = editedBrick?.value(at: target) else { return }
        let stepped = value + delta
        guard stepped.isFinite else { return }
        setParameter(target, to: .formula(.number(stepped)))
        // A tap is a committed value, so a later rejected entry returns here rather than
        // silently discarding the taps. Only an anchor this target already holds moves.
        if parameterSession?.entryAnchor?.target == target {
            beginNumberEntry(for: target)
        }
    }

    /// Switches a variable slot back to a number: the number it held when the editor opened, or
    /// the kind's template default if it opened as something else (test-first item 7c).
    func switchToNumber(_ slot: ParameterSlot) {
        switchToNumber(.slot(slot))
    }

    /// A comparison's side seeds the same way: its opening number, else the template's `1 < 2`.
    func switchToNumber(_ target: ParameterTarget) {
        guard let session = parameterSession else { return }
        let seed = Self.number(in: session.opening, at: target)
            ?? Self.number(in: BrickKind(of: session.opening).template()[0], at: target)
        guard let seed else { return }
        setParameter(target, to: .formula(.number(seed)))
    }

    /// The variable menu: points a slot at a variable the object already declares, exactly as
    /// the menu lists it — a formula slot as `.variable(name)`, a `setVariable`/`changeVariableBy`
    /// target as its name. `nil`, changing nothing, for a name nothing declares: the menu offers
    /// only declared names, so a choice is never a declaration.
    ///
    /// No trim and no character rules: those govern names this editor *creates*. A loaded
    /// `" Side "` is referenced as `" Side "` (Codex round 1), and a loaded name containing a
    /// quotation mark is still usable.
    @discardableResult
    func chooseVariable(named name: String, for slot: ParameterSlot) -> EditResult? {
        chooseVariable(named: name, for: .slot(slot))
    }

    @discardableResult
    func chooseVariable(named name: String, for target: ParameterTarget) -> EditResult? {
        guard variableMenu.scope(of: name) != nil else { return nil }
        return reference(name, for: target)
    }

    /// The Create field: the typed name, **always** trimmed and validated, then referenced —
    /// declared first if nothing in scope declares it (declare on use, ADR-035 amendment).
    ///
    /// A separate operation from `chooseVariable` because the text alone cannot say where it came
    /// from: typed `" Side "` must mean `"Side"` even while a loaded `" Side "` exists (Codex
    /// round 2). Creating a name that is already declared references it rather than refusing it
    /// as a duplicate — the user asked for that variable, and it exists.
    ///
    /// Everything is checked **before** anything is applied, so a refused name declares nothing.
    /// The declaration and the replacement share the session's key: one undo entry, so undo can
    /// never leave a brick naming a variable it just un-declared.
    @discardableResult
    func createVariable(named name: String, for slot: ParameterSlot) -> EditResult? {
        createVariable(named: name, for: .slot(slot))
    }

    @discardableResult
    func createVariable(named name: String, for target: ParameterTarget) -> EditResult? {
        guard let session = parameterSession else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if case let .failure(problem) = VariableName.validate(trimmed) {
            return .rejected(.invalidVariableName(problem))
        }
        guard brick(at: session.address)?.replacing(target, with: Self.value(naming: trimmed, for: target)) != nil
        else { return nil }
        if variableMenu.scope(of: trimmed) == nil {
            let declaration = EditAction.declareVariable(name: trimmed, script: session.address.script)
            let declared = apply(declaration, coalescing: session.key)
            if case .rejected = declared { return declared }
        }
        return reference(trimmed, for: target)
    }

    /// `writeEmbroideryToFile`'s name, **exactly as typed** — file names are not restricted
    /// (ADR-040), and trimming would silently rewrite a loaded `" report "` at the first keystroke
    /// (Codex round 2). Only an empty or blank name is never written: the brick keeps the one it
    /// had, so the row never shows the `(empty)` placeholder because of this editor — and it is
    /// put back where the typing run began, because backspacing `"old"` to nothing live-commits
    /// `"ol"` and `"o"` on the way (Codex round 3).
    func setFileName(_ text: String) {
        guard text.contains(where: { !$0.isWhitespace }) else {
            if let anchor = parameterSession?.entryAnchor, anchor.target == .slot(.fileName) {
                setParameter(.fileName, to: anchor.value)
            }
            return
        }
        setParameter(.fileName, to: .fileName(text))
    }

    // MARK: Reading

    private func reference(_ name: String, for target: ParameterTarget) -> EditResult? {
        setParameter(target, to: Self.value(naming: name, for: target))
    }

    private static func value(naming name: String, for target: ParameterTarget) -> ParameterValue {
        target == .slot(.variableName) ? .variableName(name) : .formula(.variable(name))
    }

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

    private static func number(in brick: Brick, at target: ParameterTarget) -> Double? {
        guard case let .formula(.number(value)) = brick.value(at: target) else { return nil }
        return value
    }
}
