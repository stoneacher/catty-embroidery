import StagePreview
import SwiftUI

/// The stage's skeleton: an empty state and the hoop outline, at the size
/// ADR-007 defines.
///
/// Named `StagePlaceholderView` rather than `StageView` on purpose — US-305
/// introduces the real renderer under the latter name, and a placeholder that
/// already occupies it would make that story a rewrite disguised as an edit.
///
/// This is also the app's only honest use of `StagePreview` before US-305
/// exists: it reads `StageGeometry` for the hoop's physical size and aspect
/// ratio. There is no display list, no transform and no run state here.
struct StagePlaceholderView: View {
    var body: some View {
        // A `ScrollView`, even though nothing here is long enough to scroll at
        // ordinary type sizes. The detail pane does not scroll on its own, so at
        // AX3–AX5 the fixed `VStack` clipped and `ContentUnavailableView`'s title
        // truncated to "No Design Sele…" — measured on iPad Pro 11 at AX5 by the
        // in-loop review. The milestone's definition of done only claims AX1, and
        // AX1 was clean either way; this makes the larger sizes correct rather
        // than merely unclaimed, which is cheaper now than after US-305 fills the
        // pane with a renderer.
        ScrollView {
            VStack(spacing: 24) {
                hoopOutline
                ContentUnavailableView(
                    String(localized: .stageEmptyTitle),
                    systemImage: "circle.dashed",
                    description: Text(.stageEmptyDescription)
                )
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(Text(.stageTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The hoop, drawn from `StageGeometry.box` rather than a literal square.
    ///
    /// The aspect ratio comes from the box's own width and height even though
    /// ADR-007's stage is square: hard-coding `1` here would mean this view
    /// quietly disagrees with `StageGeometry` if the stage ever stops being
    /// square, and the disagreement would be invisible.
    private var hoopOutline: some View {
        // Bound once. `hoopSizeDescription` runs a `Measurement` format and a
        // catalog lookup, and it was previously evaluated twice per body — once
        // for the caption, once for the accessibility label.
        let description = Self.hoopSizeDescription

        return VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                .aspectRatio(StageGeometry.box.width / StageGeometry.box.height, contentMode: .fit)
                // The shape carries no information a caption does not, so it is
                // decorative to VoiceOver. `.ignore` says that; the previous
                // `.combine` merged children that do not exist and was then
                // overridden by the label anyway.
                .accessibilityHidden(true)

            // **Below** the shape, not overlaid on it. As a bottom overlay the
            // caption was width-bound by the hoop, where English already spans
            // ~95% at AX5 — German "Stickrahmen 100 mm × 100 mm" is ~40% longer
            // and would have truncated. For a project shipping ~75 languages,
            // a label that only fits in English is a defect, not a risk.
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(description))
    }

    /// "Hoop 100 mm × 100 mm".
    ///
    /// `usage: .asProvided` is deliberate. The default lets the formatter pick
    /// the locale's preferred unit, which rendered this as "10 cm × 10 cm" —
    /// arithmetically right and wrong for the domain: ADR-007 defines the stage
    /// in millimetres, DST is a millimetre-based format, and hoops are specified
    /// in millimetres by every machine vendor. The number and the unit
    /// abbreviation are still localized; only the *choice* of unit is pinned.
    ///
    /// Computed rather than `static let` on purpose: both the measurement
    /// formatting and the catalog lookup depend on the current locale, which can
    /// change while the app is running. A stored constant would freeze whichever
    /// locale happened to be active at first access.
    static var hoopSizeDescription: String {
        let side = Measurement(value: StageGeometry.sideInMillimetres, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided))
        return String(localized: LocalizedStringResource.stageHoopSize(side, side))
    }
}

#Preview {
    NavigationStack {
        StagePlaceholderView()
    }
}
