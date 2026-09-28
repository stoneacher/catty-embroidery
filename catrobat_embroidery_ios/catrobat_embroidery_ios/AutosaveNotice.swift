import Foundation

/// What the window says about the saved program (US-406): the launch refusal's alert and the
/// save-failure banner.
///
/// Pure, so the choice of words is testable without a view.
enum AutosaveNotice {
    /// Why a saved design was refused, in the three groups the copy distinguishes.
    enum Cause: Equatable, Sendable {
        case newerApp, damaged, blocksDontFit
    }

    static func cause(of _: ProgramLoadError) -> Cause {
        .damaged
    }

    static var refusalTitle: LocalizedStringResource {
        .autosaveRefusalTitle
    }

    static func message(for _: ProgramRefusal) -> LocalizedStringResource {
        .autosaveRefusalTitle
    }

    static func banner(for _: ProgramSaveFailure) -> LocalizedStringResource {
        .autosaveRefusalTitle
    }

    static func bannerSymbol(for _: ProgramSaveFailure) -> String {
        ""
    }
}
