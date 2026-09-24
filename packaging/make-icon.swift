// The app icon: a cable connector on the product's blue, drawn once so the
// asset catalog can be regenerated rather than hand-edited.
import AppKit

let size = 1024.0
let outDir = CommandLine.arguments[1]
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: the rounded square covers ~82% of the canvas.
let inset = size * 0.09
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.98, alpha: 1),
           ending: NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.62, alpha: 1))!
    .draw(in: squircle, angle: -90)

var config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
config = config.applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "cable.connector", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/icon_1024.png"))
print("wrote \(outDir)/icon_1024.png")
