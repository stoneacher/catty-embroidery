import EmbroideryEngine

/// One observable effect of advancing the interpreter, emitted in execution
/// order (ADR-018). The full case set lands here (US-205), but only
/// `needleMoved` and `waited` are *produced* by US-205's stepper; the three
/// embroidery cases are produced from US-206 on, once the bricks are wired to
/// the engine. `colorArmed` and `finalizeRequested` still carry provisional
/// payloads — chosen to carry what US-206's producers will need so the enum
/// need not be reshaped then. `stitch` no longer does: ADR-021 pinned its
/// payload against M3's preview, the first real consumer.
public enum InterpreterEvent: Equatable, Sendable {
    /// A motion brick moved the needle (US-205). Carries the acting object and
    /// the single `NeedleUpdate` the motion produced (one per executed motion
    /// brick, including catch-and-skip, per US-204's bridge).
    case needleMoved(actor: ActorID, update: NeedleUpdate)

    /// A `wait` brick completed its logical duration on this tick (US-205).
    case waited(actor: ActorID)

    /// A stitch was placed (produced from US-206), carrying the thread color the
    /// engine resolved for the acting object (ADR-021). No longer provisional:
    /// M3's preview is a real consumer and this payload is pinned against it.
    ///
    /// The color comes from `EmbroideryPatternManager.threadColor(for:)`, so a
    /// renderer inherits every ADR-015 rule — the silent start, the invalid-hex
    /// no-op, the `== 121` tie-off — without implementing any of them. `.black`
    /// is a legitimate value here (it is `ColorState`'s default), not a marker.
    case stitch(actor: ActorID, position: StagePoint, layer: Int, color: ThreadColor)

    /// A thread color was armed for the next stitch (produced from US-206).
    /// Provisional payload.
    case colorArmed(actor: ActorID, hex: String)

    /// A `writeEmbroideryToFile` brick requested finalization (produced from
    /// US-206). Provisional payload.
    case finalizeRequested(name: String)
}
