// Draws the iOS app icon: the same floppy artwork as make-icon.swift, but
// full-bleed and opaque — iOS applies its own corner mask, and App Store /
// asset-catalog icons must not contain an alpha channel.
//
// Usage: swift Scripts/make-ios-icon.swift <output.png>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift make-ios-icon.swift <output.png>\n".utf8))
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Draws the icon into the current graphics context in a 1024x1024 space,
/// origin at bottom-left.
func drawIcon() {
    // Background: full-bleed slate gradient (iOS masks the corners itself).
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSGradient(starting: color(0x46628C), ending: color(0x1B2536))?
        .draw(in: canvas, angle: -90)

    // Floppy body: rounded rect with the top-right corner bevel.
    let bodyRect = NSRect(x: 242, y: 240, width: 540, height: 560)
    let bevel: CGFloat = 78
    let radius: CGFloat = 30
    let body = NSBezierPath()
    body.move(to: NSPoint(x: bodyRect.minX + radius, y: bodyRect.minY))
    body.line(to: NSPoint(x: bodyRect.maxX - radius, y: bodyRect.minY))
    body.appendArc(
        withCenter: NSPoint(x: bodyRect.maxX - radius, y: bodyRect.minY + radius),
        radius: radius, startAngle: -90, endAngle: 0
    )
    body.line(to: NSPoint(x: bodyRect.maxX, y: bodyRect.maxY - bevel))
    body.line(to: NSPoint(x: bodyRect.maxX - bevel, y: bodyRect.maxY))
    body.line(to: NSPoint(x: bodyRect.minX + radius, y: bodyRect.maxY))
    body.appendArc(
        withCenter: NSPoint(x: bodyRect.minX + radius, y: bodyRect.maxY - radius),
        radius: radius, startAngle: 90, endAngle: 180
    )
    body.line(to: NSPoint(x: bodyRect.minX, y: bodyRect.minY + radius))
    body.appendArc(
        withCenter: NSPoint(x: bodyRect.minX + radius, y: bodyRect.minY + radius),
        radius: radius, startAngle: 180, endAngle: 270
    )
    body.close()

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 30
    shadow.set()
    color(0x2A55B8).setFill()
    body.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    body.addClip()
    NSGradient(starting: color(0x3E6BD6), ending: color(0x22449B))?
        .draw(in: bodyRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Metal shutter at the top, with its dark read slot.
    let shutter = NSBezierPath(
        roundedRect: NSRect(x: 400, y: 632, width: 260, height: 168),
        xRadius: 14, yRadius: 14
    )
    NSGraphicsContext.current?.saveGraphicsState()
    shutter.addClip()
    NSGradient(starting: color(0xD9DEE7), ending: color(0xA6ADBC))?
        .draw(in: NSRect(x: 400, y: 632, width: 260, height: 168), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    color(0x25355A).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 568, y: 660, width: 62, height: 116),
        xRadius: 10, yRadius: 10
    ).fill()

    // Label: cream sticker with an orange stripe and the MAVICA wordmark.
    let labelRect = NSRect(x: 302, y: 264, width: 420, height: 280)
    color(0xF4F1E6).setFill()
    NSBezierPath(roundedRect: labelRect, xRadius: 14, yRadius: 14).fill()

    NSGraphicsContext.current?.saveGraphicsState()
    NSBezierPath(roundedRect: labelRect, xRadius: 14, yRadius: 14).addClip()
    color(0xF2A33C).setFill()
    NSRect(x: labelRect.minX, y: labelRect.maxY - 54, width: labelRect.width, height: 54).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Tiny photo on the label: sky, sun, and mountains.
    let photoRect = NSRect(x: 342, y: 396, width: 340, height: 108)
    NSGraphicsContext.current?.saveGraphicsState()
    let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: 8, yRadius: 8)
    photoPath.addClip()
    NSGradient(starting: color(0x9FCBEF), ending: color(0xDDEBf7))?
        .draw(in: photoRect, angle: -90)
    color(0xF2B03C).setFill()
    NSBezierPath(ovalIn: NSRect(x: photoRect.minX + 40, y: photoRect.maxY - 58, width: 40, height: 40)).fill()
    let mountains = NSBezierPath()
    mountains.move(to: NSPoint(x: photoRect.minX, y: photoRect.minY))
    mountains.line(to: NSPoint(x: photoRect.minX + 110, y: photoRect.minY + 78))
    mountains.line(to: NSPoint(x: photoRect.minX + 190, y: photoRect.minY))
    mountains.close()
    let mountains2 = NSBezierPath()
    mountains2.move(to: NSPoint(x: photoRect.minX + 130, y: photoRect.minY))
    mountains2.line(to: NSPoint(x: photoRect.minX + 240, y: photoRect.minY + 92))
    mountains2.line(to: NSPoint(x: photoRect.maxX, y: photoRect.minY))
    mountains2.close()
    color(0x4E8A5A).setFill()
    mountains.fill()
    color(0x39694A).setFill()
    mountains2.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Wordmark.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 64, weight: .heavy),
        .foregroundColor: color(0x3A414F),
        .kern: 10,
        .paragraphStyle: paragraph
    ]
    NSAttributedString(string: "MAVICA", attributes: attributes)
        .draw(in: NSRect(x: labelRect.minX, y: 296, width: labelRect.width, height: 80))

    // Write-protect notch detail, bottom-left of the body.
    color(0x1C3373).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: 274, y: 266, width: 44, height: 44),
        xRadius: 8, yRadius: 8
    ).fill()
}

// NSGraphicsContext cannot target a 24-bit bitmap, so draw RGBA first…
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .calibratedRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("Could not create bitmap.\n".utf8))
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context
context.cgContext.interpolationQuality = .high
drawIcon()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

// …then flatten to alpha-less RGB: asset-catalog app icons must not carry an
// alpha channel.
guard
    let drawn = rep.cgImage,
    let flatContext = CGContext(
        data: nil,
        width: 1024,
        height: 1024,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else {
    FileHandle.standardError.write(Data("Could not create flatten context.\n".utf8))
    exit(1)
}
flatContext.draw(drawn, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
guard let flattened = flatContext.makeImage() else {
    FileHandle.standardError.write(Data("Could not flatten image.\n".utf8))
    exit(1)
}
guard let data = NSBitmapImageRep(cgImage: flattened)
    .representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("Could not encode PNG.\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try data.write(to: outputURL)
print("Wrote \(outputURL.path)")
