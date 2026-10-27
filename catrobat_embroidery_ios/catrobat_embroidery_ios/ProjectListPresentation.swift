import EditorCore
import Foundation
import ProgramModel
import Projects

/// Why a listed project cannot be opened (brief D11): two badges, by what the user can do
/// about it. Only a file from a later app version is "newer"; everything else, the launch
/// alert's blocks-don't-fit group included, is damage (decided 2026-10-27).
enum ProjectBadge: Equatable {
    case needsNewerApp
    case damaged

    /// No `default`: a new `ProgramDocumentError` case must fail to compile here rather than
    /// fall silently into a badge.
    init(_ reason: ProgramDocumentError) {
        switch reason {
        case let .unsupportedVersion(version) where version > Program.currentFormatVersion:
            self = .needsNewerApp
        case .unsupportedVersion, .corrupt, .encodingFailed, .unbalancedScript, .formulaTooDeep:
            self = .damaged
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .needsNewerApp: .projectRowBadgeNewer
        case .damaged: .projectRowBadgeDamaged
        }
    }
}

/// What a row offers. A refused row offers only `.delete` (D11).
enum ProjectRowAction: Equatable {
    case open
    case rename
    case duplicate
    case delete
}

/// One of the user's projects, as the list shows it.
struct ProjectRow: Equatable, Identifiable {
    let id: ProjectID
    /// The program's name, a refused file's readable name, or "Unnamed design".
    let name: String
    let modified: Date
    /// Set exactly when the file was refused.
    let badge: ProjectBadge?
    let isSelected: Bool

    var actions: [ProjectRowAction] {
        badge == nil ? [.open, .rename, .duplicate, .delete] : [.delete]
    }
}

/// The "My Designs" section: the rows, or the empty state.
enum ProjectListContent: Equatable {
    case empty
    case rows([ProjectRow])
}

/// What the project list shows (project management slice 7; brief D11, D12). Pure, so the
/// list's behaviour is testable without a view (`ProjectListPresentationTests`).
///
/// Emptiness is decided from the project files alone — refused ones count, the window's
/// unwritten draft does not — so the samples section, which is always shown, can never stand
/// in for the user's own designs.
enum ProjectListPresentation {
    /// Newest first; files modified at the same moment by ID, so the order never depends on
    /// the directory scan. `showsSelection` is the container's: only the split view's sidebar
    /// shows one (`ProjectListView.showsSelection`).
    static func content(files: [ProjectFile], openID: ProjectID, showsSelection: Bool) -> ProjectListContent {
        guard !files.isEmpty else { return .empty }
        let sorted = files.sorted {
            $0.modified != $1.modified ? $0.modified > $1.modified : $0.id.uuidString < $1.id.uuidString
        }
        return .rows(sorted.map { file in
            let name: String?
            let badge: ProjectBadge?
            switch file.inspection {
            case let .openable(program):
                name = program.name
                badge = nil
            case let .refused(reason, readable):
                name = readable
                badge = ProjectBadge(reason)
            }
            return ProjectRow(
                id: file.id,
                name: name ?? String(localized: .projectRowUnnamed),
                modified: file.modified,
                badge: badge,
                isSelected: showsSelection && file.id == openID
            )
        })
    }

    /// "1 hour ago", "yesterday": relative to an injected `now`, computed once per render
    /// rather than ticking (`Text(_:style: .relative)` re-announces itself to VoiceOver).
    static func dateText(_ modified: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: modified, relativeTo: now)
    }

    /// One sentence per row, one whole catalog entry per kind, so a translator can make the
    /// parts agree.
    static func accessibilityLabel(for row: ProjectRow, now: Date, locale: Locale = .current) -> String {
        let date = dateText(row.modified, now: now, locale: locale)
        return switch row.badge {
        case nil: String(localized: .projectRowAccessibilityLabel(row.name, date))
        case .needsNewerApp: String(localized: .projectRowAccessibilityLabelNewer(row.name, date))
        case .damaged: String(localized: .projectRowAccessibilityLabelDamaged(row.name, date))
        }
    }
}
