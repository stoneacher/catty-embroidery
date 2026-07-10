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
    public mutating func activate(_: any StitchPattern) {}

    /// Catroid `update()`: delegates to the pattern while running,
    /// otherwise emits nothing.
    public mutating func update(_: NeedleUpdate) -> [StagePoint] {
        []
    }

    /// Catroid `setStartCoordinates`: delegates when a pattern is set.
    public mutating func setStartPosition(_: StagePoint) {}

    public mutating func pause() {}

    /// Resumes only while a pattern is installed (Catroid `resume`).
    public mutating func resume() {}

    /// Catroid `deactivate`: stops and discards the pattern.
    public mutating func stop() {}
}
