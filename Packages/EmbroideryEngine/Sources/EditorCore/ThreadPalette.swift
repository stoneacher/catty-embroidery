/// The curated thread palette (US-410, ADR-040): a fixed set of spool-like
/// colours, written into `setThreadColor(hex:)` as these exact strings.
///
/// A palette rather than the system `ColorPicker`, for three reasons ADR-040
/// records: a swatch is a **discrete** edit, so there is nothing to coalesce;
/// `ColorPicker` yields a `Color`, and its round-trip to a hex string is lossy
/// and would feed ADR-015's parser values it has never seen; and DST carries no
/// colour at all (US-312), so a fixed palette is the honest control for a
/// display-only attribute.
///
/// The hex values are design data: spelled `#rrggbb` in lowercase, the way the
/// template and both samples spell theirs, so a stored brick finds its swatch
/// by string equality. They include the template default and every colour a
/// shipped sample uses (`ThreadPaletteTests`). The names are the app's catalog
/// keys — `EditorCore` ships no resources.
public enum ThreadSwatch: Sendable, Hashable, CaseIterable {
    case black
    case white
    case red
    case orange
    case amber
    case yellow
    case green
    case teal
    case royalBlue
    case navy
    case purple
    case pink
    case brown
    case grey

    public var hex: String {
        switch self {
        case .black: "#000000"
        case .white: "#ffffff"
        case .red: "#ff0000" // BrickDefaults.threadColorHex (Catroid THREAD_COLOR)
        case .orange: "#f97316"
        case .amber: "#f59e0b" // Square Coil's second thread
        case .yellow: "#facc15"
        case .green: "#16a34a"
        case .teal: "#0d9488"
        case .royalBlue: "#1d4ed8" // Square Coil's first thread
        case .navy: "#1e3a8a"
        case .purple: "#7c3aed"
        case .pink: "#db2777"
        case .brown: "#92400e"
        case .grey: "#6b7280"
        }
    }

    /// The swatch spelled exactly `hex`, or `nil`. Exact spelling only:
    /// `#FF0000` is a valid colour but not this palette's string, and treating
    /// it as `red` would let a tap on the selected swatch rewrite the brick.
    public init?(hex: String) {
        guard let match = Self.allCases.first(where: { $0.hex == hex }) else { return nil }
        self = match
    }
}
