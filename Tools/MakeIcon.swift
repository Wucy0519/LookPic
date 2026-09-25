import AppKit

let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 224, yRadius: 224)
    NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.20, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.38, green: 0.44, blue: 0.50, alpha: 1)
    ])?.draw(in: shape, angle: 90)

    let card = NSBezierPath(roundedRect: NSRect(x: 214, y: 250, width: 596, height: 470), xRadius: 48, yRadius: 48)
    NSColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1).setFill()
    card.fill()

    NSColor(srgbRed: 0.96, green: 0.72, blue: 0.28, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 292, y: 520, width: 118, height: 118)).fill()

    let mountain = NSBezierPath()
    mountain.move(to: NSPoint(x: 250, y: 300))
    mountain.line(to: NSPoint(x: 430, y: 500))
    mountain.line(to: NSPoint(x: 530, y: 390))
    mountain.line(to: NSPoint(x: 680, y: 560))
    mountain.line(to: NSPoint(x: 774, y: 300))
    mountain.close()
    NSColor(srgbRed: 0.45, green: 0.62, blue: 0.74, alpha: 1).setFill()
    mountain.fill()
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("无法生成图标\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
