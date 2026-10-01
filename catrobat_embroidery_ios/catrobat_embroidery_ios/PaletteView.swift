import EditorCore
import SwiftUI

/// The brick palette (US-409): every brick the editor offers, grouped, and a tap adds one.
///
/// **It presents nothing itself.** `ScriptListView`'s toolbar owns the one presentation —
/// a popover on regular, a detented sheet on compact (ADR-039) — and this view is only its
/// content, so it never knows which of the two it is in. The tap goes to
/// `AppModel.addFromPalette(_:)`, which inserts through the editor's one door, closes the
/// palette and asks the list to scroll; nothing here mutates (ADR-006 pattern 1).
///
/// It takes the model rather than a closure for `ScriptListView`'s reason: the flag it clears
/// lives on `AppModel` (ADR-023's container swap), and the body then depends on nothing that
/// changes while it is showing.
struct PaletteView: View {
    let model: AppModel

    @Environment(\.locale) private var locale

    var body: some View {
        let sections = PaletteSection.sections(locale: locale)

        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            // A `Button`, not `List(selection:)`: a palette row is an action,
                            // and tapping the same row twice must add twice.
                            Button {
                                model.addFromPalette(row.id)
                            } label: {
                                PaletteRowView(row: row)
                            }
                            // `.plain` keeps the sentence untinted, and the style restores the
                            // pressed state `.plain` drops — `SamplePickerView`'s reasons.
                            .buttonStyle(PickerRowButtonStyle())
                            // Zeroed so the label is the whole row's hit area; the row
                            // re-applies the spacing inside (`SamplePickerView`).
                            .listRowInsets(EdgeInsets())
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text(.paletteTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        model.isPalettePresented = false
                    } label: {
                        Label {
                            Text(.paletteClose)
                        } icon: {
                            Image(systemName: "xmark")
                        }
                    }
                }
            }
        }
        // Ideal sizes only, and no `minHeight`. A popover sizes itself from its content's ideal
        // size, which a `List` does not have; a sheet proposes its detent's height, which a
        // frame with no minimum passes straight through. A minimum height taller than the
        // 0.4 detent would lay the content out taller than the sheet and push the title bar
        // off its top. The width floor is below every iPhone's, so it binds only a popover.
        .frame(minWidth: 320, idealWidth: 380, idealHeight: 600)
    }
}

/// One palette row: the brick as it will appear in the script, and what it does.
///
/// Internal rather than `private` only for previews.
struct PaletteRowView: View {
    let row: PaletteRowPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // The script row's own leading mark, so the palette shows the brick as the script
            // will (`BrickLeadingView`).
            BrickLeadingView(kind: row.id, threadColor: row.threadColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.text)
                    .font(.body)
                    // The AX1 no-truncation guarantee inside a list row — see `SampleRowView`.
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Explicit for `SampleRowView`'s reason: alignment is inherited, and `.leading` is
            // the only RTL-correct spelling.
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Inside the label, because the label is the button's hit area — see the zeroed
        // `listRowInsets` at the call site.
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        // A floor for the thumb, not a size — see `SampleRowView`.
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        // One element per row, naming the brick and what it does, with a label a test can read
        // (`PaletteRowPresentation.accessibilityLabel`). The description is in the label rather
        // than a hint, because hints can be turned off. The enclosing `Button` contributes the
        // button trait, as it does for `SampleRowView`.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.accessibilityLabel))
        // Voice Control: "tap Stitch", not the whole label (`SampleRowView`).
        .accessibilityInputLabels([Text(row.text)])
    }
}

#Preview {
    PaletteView(model: AppModel(autosave: .preview))
}
