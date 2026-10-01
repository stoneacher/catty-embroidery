@testable import catrobat_embroidery_ios
import CoreGraphics
import Testing

/// US-409: how much of the script list a presented palette covers, so the list's bottom margin
/// can keep a freshly inserted brick out from behind the sheet.
///
/// The geometry is in one coordinate space (`.global`). The list here spans y 100…800 on a
/// 400-pt-wide window. A sheet rises from the window's bottom edge, so it always reaches the
/// list's bottom. A popover hangs from the toolbar and stops short of it. The function tells
/// the two apart by that.
///
/// Written after the view layer, at review, rather than first: `swift-ui-design` proposed the
/// measurement and the view agent wrote the function. These tests are proved by mutation
/// instead of by a red run (ADR-032 invariant 2).
struct PaletteInsetTests {
    private static let list = CGRect(x: 0, y: 100, width: 400, height: 700)

    private static func inset(_ palette: CGRect?) -> CGFloat {
        ScriptListView.bottomInset(listFrame: list, paletteFrame: palette)
    }

    @Test("no palette, no inset")
    func noPalette() {
        #expect(Self.inset(nil) == 0)
    }

    @Test("a sheet at a partial detent insets the list by what it covers")
    func partialSheet() {
        // The sheet's top at y 500, its bottom past the window's bottom edge.
        #expect(Self.inset(CGRect(x: 0, y: 500, width: 400, height: 380)) == 300)
    }

    @Test("a sheet reaching exactly the list's bottom still counts")
    func sheetFlushWithTheList() {
        #expect(Self.inset(CGRect(x: 0, y: 600, width: 400, height: 200)) == 200)
    }

    @Test("a sheet covering the whole list insets by the list's height and no more")
    func largeSheet() {
        #expect(Self.inset(CGRect(x: 0, y: 40, width: 400, height: 900)) == 700)
    }

    @Test("a sheet entirely below the list covers nothing")
    func sheetBelowTheList() {
        #expect(Self.inset(CGRect(x: 0, y: 820, width: 400, height: 100)) == 0)
    }

    /// A popover hangs from the toolbar's Add button and ends above the list's bottom. It
    /// overlaps the list, but nothing scrolls under it from below, so it gets no inset.
    @Test("a popover that stops short of the list's bottom gets no inset")
    func popover() {
        #expect(Self.inset(CGRect(x: 40, y: 120, width: 380, height: 600)) == 0)
    }

    /// On iPad the palette sits over the stage column, beside the list rather than over it.
    @Test("a palette beside the list, not over it, gets no inset", arguments: [
        CGRect(x: 400, y: 500, width: 300, height: 400),
        CGRect(x: -300, y: 500, width: 300, height: 400)
    ])
    func besideTheList(palette: CGRect) {
        #expect(Self.inset(palette) == 0)
    }
}
