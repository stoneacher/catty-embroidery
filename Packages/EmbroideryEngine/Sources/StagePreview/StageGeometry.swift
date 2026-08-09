/// ADR-007's virtual stage, in code for the first time: centre origin, y-up,
/// 500 × 500 points, 1 pt = 2 embroidery units = 0.2 mm — about a 100 × 100 mm
/// consumer hoop.
///
/// **This does not bound engine input.** Nothing bounds a `StagePoint`, and a
/// design may legitimately leave the stage: the hoop is drawn as an *outline*
/// and is not clipped to, so an out-of-hoop design stays visible rather than
/// being silently cropped. The engine's only coordinate boundary is ADR-020's
/// convertibility and interpolability guard inside `EmbroideryStream.append`,
/// which is about what a DST record can hold, not about where the hoop is —
/// and inside this stage the maximum extent is 1000 units, comfortably within
/// every header field, so the two concerns never even meet here.
///
/// Everything below is for fitting, chrome and the accessibility summary. No
/// code path may use these values to reject or clamp a stitch.
public enum StageGeometry {
    /// The stage is square: 500 points on a side.
    public static let sideInPoints: Double = 500

    /// Half a side — the stage spans ±250 points about the origin on both axes.
    public static let halfExtentInPoints: Double = 250

    /// ADR-007's unit chain: 1 stage point = 2 embroidery units = 0.2 mm.
    public static let millimetresPerPoint: Double = 0.2

    /// 100 mm on a side, i.e. the hoop the stage is modelled on.
    public static let sideInMillimetres: Double = sideInPoints * millimetresPerPoint

    /// The hoop outline, centred on the origin.
    public static let box = StageBox(
        minX: -halfExtentInPoints,
        minY: -halfExtentInPoints,
        maxX: halfExtentInPoints,
        maxY: halfExtentInPoints
    )
}
