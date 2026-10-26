import ProgramModel

public extension Program {
    /// Whether `self` is `other` renamed and nothing else (brief D8): a rename keeps the run
    /// and only re-prepares the export, so the window judges the actual before and after.
    ///
    /// Compares what would be **persisted**, not `==`: `Program.==` treats `-0.0` and `0.0` as
    /// one value, but a sign can change a run (`arctan2(-0, -1)` is -180, Codex slice 2
    /// review). A program that cannot be encoded is never rename-only, which voids the run —
    /// the safe direction. The two encodes run only when the names differ.
    func differsOnlyInName(from other: Program) -> Bool {
        guard name != other.name else {
            return false
        }
        var renamedBack = self
        renamedBack.name = other.name
        guard let before = try? ProgramDocument.encode(other),
              let after = try? ProgramDocument.encode(renamedBack)
        else {
            return false
        }
        return before == after
    }
}
