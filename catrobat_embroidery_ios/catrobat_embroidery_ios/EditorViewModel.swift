import EditorCore
import Observation
import ProgramModel

/// The working program, its history, and the one door every edit goes through (US-405).
@MainActor
@Observable
final class EditorViewModel {
    private(set) var undoStack: UndoStack

    var program: Program {
        undoStack.current
    }

    @ObservationIgnored var onEditApplied: (() -> Void)?

    init(program: Program = .blank) {
        undoStack = UndoStack(program: program)
    }

    @discardableResult
    func apply(_ action: EditAction) -> EditResult {
        EditorCore.apply(action, to: program)
    }

    func load(_ program: Program) {
        undoStack.reset(to: program)
    }
}
