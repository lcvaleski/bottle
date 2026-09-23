// Renders the DMG window background (1x and 2x) so the installer window
// explains itself: app on the left, Applications on the right, arrow between.
import AppKit

let width = 600.0, height = 424.0
let outDir = CommandLine.arguments[1]

func draw(scale: CGFloat, to path: String) {
    let pxW = Int(width * scale), pxH = Int(height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: scale, y: scale)

    // Ground
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Finder centres each icon roughly 45pt below the y in icon_locations
    // (it reserves label space), so the visual icon row sits ~215pt from the top.
    let iconRowFromTop = 215.0
    let iconCenterY = height - iconRowFromTop
    let leftX = 155.0, rightX = 445.0
    let iconHalf = 64.0, gap = 16.0

    // Arrow: the only thing in the icon band, so nothing overlaps the icons.
    let arrow = NSBezierPath()
    let startX = leftX + iconHalf + gap, endX = rightX - iconHalf - gap
    arrow.move(to: NSPoint(x: startX, y: iconCenterY))
    arrow.line(to: NSPoint(x: endX, y: iconCenterY))
    arrow.move(to: NSPoint(x: endX - 12, y: iconCenterY + 8))
    arrow.line(to: NSPoint(x: endX, y: iconCenterY))
    arrow.line(to: NSPoint(x: endX - 12, y: iconCenterY - 8))
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 0.6, alpha: 1).setStroke()
    arrow.stroke()

    func center(_ text: String, _ font: NSFont, _ color: NSColor, fromTop: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = text as NSString
        let size = string.size(withAttributes: attrs)
        string.draw(at: NSPoint(x: (width - size.width) / 2, y: height - fromTop - size.height),
                    withAttributes: attrs)
    }

    // Above the icons
    center("Drag Bottle to your Applications folder", .systemFont(ofSize: 18, weight: .semibold),
           NSColor(calibratedWhite: 0.12, alpha: 1), fromTop: 52)
    // Below the icon labels
    // Finder may show a ~26pt status bar at the bottom; keep everything above it.
    center("Then eject this disk image and open Bottle from Applications.",
           .systemFont(ofSize: 12.5, weight: .regular), NSColor(calibratedWhite: 0.42, alpha: 1), fromTop: 296)
    center("Bottle also needs Apple Configurator, free on the Mac App Store.",
           .systemFont(ofSize: 12.5, weight: .regular), NSColor(calibratedWhite: 0.42, alpha: 1), fromTop: 316)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

draw(scale: 1, to: "\(outDir)/dmg-background.png")
print("wrote backgrounds to \(outDir)")
