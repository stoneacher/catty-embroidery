import EditorCore
import ProgramModel

/// One open parameter editor (US-410).
struct ParameterSession: Equatable {
    let address: BrickAddress
    let key: CoalescingKey
    let opening: Brick
}

extension EditorViewModel {
    var canEditSelectedBrick: Bool {
        false
    }

    var editedBrick: Brick? {
        nil
    }

    var variableMenu: VariableMenu {
        VariableMenu(program: .blank, script: ScriptAddress())
    }

    @discardableResult
    func beginParameterEdit(at index: Int) -> Bool {
        false
    }

    func endParameterEdit() {}

    @discardableResult
    func setParameter(_ slot: ParameterSlot, to value: ParameterValue) -> EditResult? {
        nil
    }

    func enterNumber(_ text: String, for slot: ParameterSlot) -> FormulaLiteralError? {
        nil
    }

    func stepNumber(_ slot: ParameterSlot, by delta: Double) {}

    func switchToNumber(_ slot: ParameterSlot) {}

    @discardableResult
    func useVariable(named name: String, for slot: ParameterSlot) -> EditResult? {
        nil
    }

    func setFileName(_ text: String) {}
}
