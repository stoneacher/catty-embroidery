/// A trigger plus a flat, ordered list of bricks (Catroid `Script`). Control
/// bricks live inline as begin/end pairs (ADR-008); the paired-control model
/// logic — pair resolution, validation, move-as-a-unit — is in
/// `Script+PairedControl.swift`.
public struct Script: Sendable, Equatable, Codable {
    public var header: ScriptHeader
    public var bricks: [Brick]

    public init(header: ScriptHeader = .whenStarted, bricks: [Brick] = []) {
        self.header = header
        self.bricks = bricks
    }
}
