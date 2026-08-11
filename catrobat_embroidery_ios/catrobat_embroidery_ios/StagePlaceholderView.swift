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
        VStack(spacing: 24) {
            hoopOutline
            ContentUnavailableView(
                String(localized: .stageEmptyTitle),
                systemImage: "circle.dashed",
                description: Text(.stageEmptyDescription)
            )
        }
        .padding()
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
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
            .aspectRatio(StageGeometry.box.width / StageGeometry.box.height, contentMode: .fit)
            .overlay(alignment: .bottom) {
                Text(Self.hoopSizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(Self.hoopSizeDescription))
    }

    /// "Hoop 100 mm × 100 mm", with both lengths formatted for the reader's
    /// locale — so a US reader sees inches without this view knowing that.
    static var hoopSizeDescription: String {
        let side = Measurement(value: StageGeometry.sideInMillimetres, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated))
        return String(localized: LocalizedStringResource.stageHoopSize(side, side))
    }
}

#Preview {
    NavigationStack {
        StagePlaceholderView()
    }
}
