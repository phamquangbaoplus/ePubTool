import AppKit

// Finder icon coordinates in package-dmg.sh use this same 660 × 440 canvas.
let size = NSSize(width: 660, height: 440)
let image = NSImage(size: size)
image.lockFocus()
let background = NSGradient(colors: [
    NSColor(red: 1, green: 0.97, blue: 0.94, alpha: 1),
    NSColor(red: 1, green: 0.89, blue: 0.82, alpha: 1)
])!
background.draw(in: NSRect(origin: .zero, size: size), angle: -35)
func text(_ string: String, y: CGFloat, fontSize: CGFloat, bold: Bool = false) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (string as NSString).draw(in: NSRect(x: 20, y: y, width: 620, height: 40), withAttributes: [
        .font: bold ? NSFont.boldSystemFont(ofSize: fontSize) : NSFont.systemFont(ofSize: fontSize),
        .foregroundColor: NSColor(red: 0.28, green: 0.16, blue: 0.13, alpha: 1),
        .paragraphStyle: style
    ])
}
text("ePubTool", y: 355, fontSize: 32, bold: true)
text("Drag ePubTool to Applications", y: 315, fontSize: 17)
// An arrow between the two real Finder icons; do not paint fake icons.
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 292, y: 230))
arrow.line(to: NSPoint(x: 368, y: 230))
arrow.move(to: NSPoint(x: 350, y: 247))
arrow.line(to: NSPoint(x: 368, y: 230))
arrow.line(to: NSPoint(x: 350, y: 213))
arrow.lineWidth = 6
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
NSColor(red: 0.96, green: 0.32, blue: 0.20, alpha: 1).setStroke()
arrow.stroke()
text("After copying, follow the setup steps on the release page.", y: 65, fontSize: 14)
text("Terminal command • Full Disk Access", y: 38, fontSize: 13)
image.unlockFocus()
guard CommandLine.arguments.count == 2,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Usage: swift dmg-background.swift output.png")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
