import ProgramModel

/// The script list's row identity, derived by the editor rather than stored in the model
/// (ADR-034's 2026-10-15 amendment, Editor UI slice 4).
///
/// `Brick` carries no identity (ADR-034), and index identity made a drop stutter: UIKit animates
/// the dragged row into place, then the new data arrives as "row 4 changed its contents", and for
/// about a third of a second the list showed the wrong brick and an empty gap before snapping
/// (recorded on the simulator, 2026-10-15). So after every change the IDs **follow the bricks**,
/// by the same diff `HistoryAnnouncement` names edits with:
///
/// - rows equal at the front and back keep their IDs;
/// - a window that is one block moved rotates its IDs with the block;
/// - a window changed in place (a parameter edit) keeps its IDs, so the row is not re-created
///   under the user's finger;
/// - anything else gets **fresh** IDs. An ID is never reused: SwiftUI would take it for the old
///   row coming back.
///
/// Equal bricks are interchangeable here — two `stitch` rows may trade IDs — which is harmless:
/// rows that look the same and say the same to VoiceOver.
nonisolated struct RowIdentities: Equatable {
    private(set) var ids: [Int]
    private var next: Int

    init(count: Int) {
        ids = Array(0 ..< count)
        next = count
    }

    mutating func follow(from old: [Brick], to new: [Brick]) {
        let diff = BrickListDiff(from: old, to: new)
        let window = Array(ids[diff.prefix ..< ids.count - diff.suffix])
        let middle: [Int] = if let split = diff.moveSplit {
            BrickListDiff.rotated(window, at: split)
        } else if diff.removed.count == diff.inserted.count {
            window
        } else {
            fresh(diff.inserted.count)
        }
        ids = Array(ids[..<diff.prefix]) + middle + Array(ids[(ids.count - diff.suffix)...])
    }

    private mutating func fresh(_ count: Int) -> [Int] {
        defer { next += count }
        return Array(next ..< next + count)
    }
}
