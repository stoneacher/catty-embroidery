// Crops the stage region out of full-resolution iPhone 17 frames and tiles them, three per row.
//
//     swiftc -O tile.swift -o tile && ./tile <out.png> <frame.png>...
//
// The crop (y 300…1400 of a 2622-pixel-high frame) is the stage, its caption and the name field:
// enough to see whether the design has left the hoop, and whether it has left the mat.
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
let destination = URL(fileURLWithPath: arguments[0])
let crop = NSRect(x: 0, y: 0, width: 1206, height: 1100)
let tiles = arguments.dropFirst().compactMap { path -> NSImage? in
    guard let frame = NSImage(contentsOfFile: path) else { return nil }
    let tile = NSImage(size: crop.size)
    tile.lockFocus()
    frame.draw(
        in: crop,
        from: NSRect(x: 0, y: frame.size.height - 1400, width: crop.width, height: crop.height),
        operation: .copy,
        fraction: 1
    )
    tile.unlockFocus()
    return tile
}

let width = crop.width * 0.4
let height = crop.height * 0.4
let rows = (tiles.count + 2) / 3
let sheet = NSImage(size: NSSize(width: width * 3, height: height * CGFloat(rows)))
sheet.lockFocus()
for (index, tile) in tiles.enumerated() {
    let column = CGFloat(index % 3)
    let row = CGFloat(rows - 1 - index / 3)
    tile.draw(in: NSRect(x: column * width, y: row * height, width: width, height: height))
}

sheet.unlockFocus()

guard let tiff = sheet.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
else { fatalError("could not encode the sheet") }
try png.write(to: destination)
