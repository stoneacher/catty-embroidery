import Foundation

/// Lifecycle wrapper around a `StitchPattern` (Catroid `RunningStitch`):
/// one per stitching actor. Holds the active pattern as an existential
/// because the concrete type changes at runtime (running → zigzag → triple
/// per brick). `resume()` deliberately does not re-anchor — callers
/// re-anchor explicitly via `setStartPosition`, the seam US-109's
/// pause-around-sew-up composes on.
public struct RunningStitch: Sendable {
    public private(set) var isRunning = false

    private var pattern: (any StitchPattern)?

    public init() {}

    /// Catroid `activateStitching`: installs a pattern and starts. A
    /// non-optional parameter makes the reference's null-type case
    /// unrepresentable.
    public mutating func activate(_ pattern: any StitchPattern) {
        self.pattern = pattern
        isRunning = true
    }

    /// Catroid `update()`: delegates to the pattern while running,
    /// otherwise emits nothing.
    public mutating func update(_ needle: NeedleUpdate) -> [StagePoint] {
        guard isRunning else { return [] }
        return pattern?.update(needle) ?? []
    }

    /// Feeds one action's updates (Arc, GoThrough: up to 100 in a tick,
    /// ADR-047), returning each update's stitches in order.
    ///
    /// ADR-014's million-length bound, extended from one update to the
    /// action: when the chords from `start` through every update hold more
    /// than `maxStitchesPerUpdate` whole lengths, nothing is fed and every
    /// result is empty, leaving the pattern's anchor where it was, as for one
    /// rejected update. Each chord can pass the per-update bound, so without
    /// this a huge arc materialises ~100 million stitches in one tick, before
    /// any run budget can look (Codex, PR 2 handover round 1). Within the
    /// bound this is exactly `updates.map { update($0) }`.
    public mutating func update(path updates: [NeedleUpdate], from start: StagePoint) -> [[StagePoint]] {
        if isRunning, let length = pattern?.length, length > 0 {
            var previous = start
            var chords = 0.0
            for update in updates {
                chords += hypot(update.position.x - previous.x, update.position.y - previous.y)
                previous = update.position
            }
            // `!(… <= …)` rather than `>`: an infinite or NaN total is refused too.
            if !(chords / length <= maxStitchesPerUpdate) {
                return updates.map { _ in [] }
            }
        }
        return updates.map { update($0) }
    }

    /// Catroid `setStartCoordinates`: delegates when a pattern is set.
    public mutating func setStartPosition(_ position: StagePoint) {
        pattern?.setStartPosition(position)
    }

    public mutating func pause() {
        isRunning = false
    }

    /// Resumes only while a pattern is installed (Catroid `resume`).
    public mutating func resume() {
        guard pattern != nil else { return }
        isRunning = true
    }

    /// Catroid `deactivate`: stops and discards the pattern.
    public mutating func stop() {
        isRunning = false
        pattern = nil
    }
}
