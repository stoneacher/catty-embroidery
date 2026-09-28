import SwiftUI

/// The window's standing notice that the working program is not being saved (US-406).
///
/// **Not dismissible, and not an alert.** It clears itself on the next successful write, and
/// hiding it by hand would hide a condition that is still true; an alert per failed save would
/// be the "dialog on every hiccup" the story rules out. Being non-interactive, it has no touch
/// target to size.
///
/// A sentence row, so leading-aligned (mirrored in right-to-left) where the stage's captions
/// are centred; `.bar` makes it read as an extension of the top chrome, and a system material
/// honours Reduce Transparency and Increase Contrast on its own.
struct AutosaveBanner: View {
    let failure: ProgramSaveFailure

    var body: some View {
        VStack(spacing: 0) {
            // The title/icon closure form, as in `StageNotices`: `Label(_:systemImage:)` would
            // resolve the resource to a `String` and lose `Text`-level localisation.
            Label {
                Text(AutosaveNotice.banner(for: failure))
            } icon: {
                Image(systemName: AutosaveNotice.bannerSymbol(for: failure))
            }
            .font(.footnote)
            .foregroundStyle(.primary)
            // Capped at AX1 for `StageExportRow`'s reason: pinned secondary text may stop
            // scaling, and every extra line comes out of every screen in the window.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Divider()
        }
        .background(.bar)
    }
}

#Preview("Save failed") {
    AutosaveBanner(failure: .saveFailed)
}

#Preview("Saving paused") {
    AutosaveBanner(failure: .unpreservedDocument)
}
