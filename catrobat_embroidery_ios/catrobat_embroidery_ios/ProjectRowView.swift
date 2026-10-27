import SwiftUI

/// One of the user's projects in the list (project management slice 7): its name, a badge if
/// the file was refused, and when it was last edited.
///
/// It renders a `ProjectRow` and decides nothing: newest-first order, the name fallback, the
/// badge and the highlight all come from `ProjectListPresentation`, where they are tested.
/// Whether the row opens is read from `row.actions` rather than re-derived from the badge, so
/// the one rule "a refused row offers only Delete" (D11) has one spelling.
struct ProjectRowView: View {
    let row: ProjectRow
    /// Read once per render by the list, so every row's "Edited …" agrees and nothing ticks
    /// under VoiceOver (`ProjectListPresentation.dateText`).
    let now: Date
    /// Another window holds this design (brief D7), shown as a line of its own so the row says
    /// why its Rename and Delete are disabled before the menu is opened.
    let heldElsewhere: Bool
    let onOpen: () -> Void

    var body: some View {
        rowBody
            // Zeroed so the label owns the row's full width and height; `pickerRowLayout()`
            // re-applies the spacing inside it (`SampleRowView`'s reasons).
            .listRowInsets(EdgeInsets())
            .listRowBackground(row.isSelected ? Color.accentColor.opacity(0.15) : nil)
    }

    @ViewBuilder
    private var rowBody: some View {
        if row.actions.contains(.open) {
            // A `Button`, not `List(selection:)`: tapping the open project must still reach
            // `openProject(_:)`, which shows its script (`ProjectListView`'s comment).
            Button(action: onOpen) {
                content
            }
            .buttonStyle(PickerRowButtonStyle())
        } else {
            // **Not a button, not dimmed** (D11): a refused file cannot be opened, and a
            // greyed-out button would read as "not yet" rather than "never". The badge says
            // why; slice 8 gives it its only action, Delete.
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.headline)
                    // The AX1 no-truncation guard, as on `SampleRowView`.
                    .fixedSize(horizontal: false, vertical: true)
                    // Pinned to the name: otherwise the list aligns the separator to the
                    // badge's text on a refused row, and that one separator starts indented
                    // (seen on the simulator).
                    .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }

                if let badge = row.badge {
                    ProjectBadgeView(badge: badge)
                }

                Text(.projectRowEdited(ProjectListPresentation.dateText(row.modified, now: now)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if heldElsewhere {
                    ProjectHeldLine()
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Not colour alone, and hidden from VoiceOver because the trait carries it —
            // `SampleRowView`'s checkmark, for the same reasons.
            if row.isSelected {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .pickerRowLayout()
        // One element per row, its label the tested sentence (name, badge, date), so a test
        // can assert what is spoken; `.combine` would synthesise one nobody can read back.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(ProjectListPresentation.accessibilityLabel(for: row, now: now)))
        // Voice Control: "tap Rosette" rather than the whole sentence.
        .accessibilityInputLabels([Text(row.name)])
        .accessibilityAddTraits(row.isSelected ? [.isSelected] : [])
    }
}

/// "Open in another window" under the date (slice 8, D7): the same words the menu shows as
/// the disabled reason, so the row and the menu name one state once.
///
/// **Known gap**: VoiceOver does not hear it, because the row speaks only its tested sentence
/// (`ProjectListPresentation.accessibilityLabel(for:now:)`) and the catalog has no variant
/// with the held clause yet. The menu's disabled items still carry the reason.
private struct ProjectHeldLine: View {
    var body: some View {
        // An `HStack`, not a `Label`, for `ProjectBadgeView`'s reason (the row's icon spacing).
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "macwindow.on.rectangle")
            Text(.projectActionHeld)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// Why a refused file cannot be opened, as a capsule under its name. An icon and words,
/// never colour alone, and secondary rather than red: the file is not an error the user just
/// caused, only one they may want to delete.
private struct ProjectBadgeView: View {
    let badge: ProjectBadge

    var body: some View {
        // An `HStack` rather than a `Label`: inside a list row a `Label` takes the row's icon
        // spacing, which pushed the words a thumb's width away from their icon.
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: badge.systemImage)
            Text(badge.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.fill.tertiary, in: Capsule())
    }
}

private extension ProjectBadge {
    /// No `default`, for `ProjectBadge.init`'s reason: a new badge must not borrow an icon.
    var systemImage: String {
        switch self {
        case .needsNewerApp: "arrow.up.circle"
        case .damaged: "exclamationmark.triangle"
        }
    }
}
