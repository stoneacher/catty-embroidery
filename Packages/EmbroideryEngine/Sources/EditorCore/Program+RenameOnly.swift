import ProgramModel

public extension Program {
    /// Whether `self` is `other` renamed and nothing else (brief D8): a rename keeps the run
    /// and only re-prepares the export, so the window judges the actual before and after.
    func differsOnlyInName(from other: Program) -> Bool {
        var renamedBack = self
        renamedBack.name = other.name
        return name != other.name && renamedBack == other
    }
}
