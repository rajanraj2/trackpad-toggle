import Cocoa
import CoreGraphics

func renderLogo(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    
    // Background: Apple squircle / smooth rounded rect
    let cornerRadius = size * 0.225
    let bgRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    
    // Deep gradient: modern macOS dark cybernetic slate to midnight indigo
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1.0).cgColor
    ] as CFArray
    let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(bgGradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Subtle outer border / glass rim
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setLineWidth(size * 0.015)
    ctx.setStrokeColor(NSColor(red: 0.35, green: 0.45, blue: 0.65, alpha: 0.35).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Inner Trackpad Surface (Hardware representation)
    let padRect = CGRect(
        x: size * 0.18,
        y: size * 0.18,
        width: size * 0.64,
        height: size * 0.50
    )
    let padRadius = size * 0.08
    let padPath = CGPath(roundedRect: padRect, cornerWidth: padRadius, cornerHeight: padRadius, transform: nil)
    
    let padColors = [
        NSColor(red: 0.15, green: 0.18, blue: 0.28, alpha: 0.85).cgColor,
        NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 0.95).cgColor
    ] as CFArray
    let padGradient = CGGradient(colorsSpace: colorSpace, colors: padColors, locations: [0.0, 1.0])!

    ctx.saveGState()
    // Soft drop shadow under trackpad
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    ctx.addPath(padPath)
    ctx.clip()
    ctx.drawLinearGradient(padGradient, start: CGPoint(x: 0, y: padRect.maxY), end: CGPoint(x: 0, y: padRect.minY), options: [])
    ctx.restoreGState()

    // Trackpad glass edge glow
    ctx.saveGState()
    ctx.addPath(padPath)
    ctx.setLineWidth(size * 0.012)
    ctx.setStrokeColor(NSColor(red: 0.25, green: 0.60, blue: 1.0, alpha: 0.5).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Trackpad Divider line (click zone separator at bottom)
    let dividerY = padRect.minY + padRect.height * 0.28
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.30, green: 0.45, blue: 0.70, alpha: 0.3).cgColor)
    ctx.setLineWidth(size * 0.008)
    ctx.move(to: CGPoint(x: padRect.midX, y: padRect.minY))
    ctx.addLine(to: CGPoint(x: padRect.midX, y: dividerY))
    ctx.strokePath()
    ctx.restoreGState()

    // Electric Cyan Toggle Ring / Power Switch in center
    let center = CGPoint(x: rect.midX, y: rect.midY + size * 0.03)
    let ringRadius = size * 0.16

    // Glowing cyan/electric blue halo
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.08, color: NSColor(red: 0.0, green: 0.75, blue: 1.0, alpha: 0.8).cgColor)
    
    // Draw Toggle Shield / Power slash
    let ringPath = CGMutablePath()
    ringPath.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.addPath(ringPath)
    ctx.setLineWidth(size * 0.03)
    ctx.setStrokeColor(NSColor(red: 0.1, green: 0.8, blue: 1.0, alpha: 0.95).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Inner toggle switch slash (signifying Toggle ON/OFF state)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.04, color: NSColor(red: 0.0, green: 0.9, blue: 1.0, alpha: 0.9).cgColor)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineCap(.round)
    ctx.setLineWidth(size * 0.035)

    // Diagonal toggle bar
    let slashLen = ringRadius * 1.3
    let p1 = CGPoint(x: center.x - slashLen * 0.7, y: center.y + slashLen * 0.7)
    let p2 = CGPoint(x: center.x + slashLen * 0.7, y: center.y - slashLen * 0.7)
    ctx.move(to: p1)
    ctx.addLine(to: p2)
    ctx.strokePath()
    ctx.restoreGState()

    // Hand Touchpoint indicator dot (vibrant emerald/cyan pulse)
    let pulseCenter = CGPoint(x: padRect.minX + padRect.width * 0.22, y: padRect.maxY - padRect.height * 0.22)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: size * 0.05, color: NSColor(red: 0.2, green: 1.0, blue: 0.6, alpha: 0.85).cgColor)
    ctx.setFillColor(NSColor(red: 0.3, green: 1.0, blue: 0.7, alpha: 0.95).cgColor)
    ctx.fillEllipse(in: CGRect(x: pulseCenter.x - size * 0.035, y: pulseCenter.y - size * 0.035, width: size * 0.07, height: size * 0.07))
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

let sizes: [CGFloat] = [16, 32, 64, 128, 256, 512, 1024]
let iconsetDir = "/tmp/TrackpadToggle.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for s in sizes {
    let img = renderLogo(size: s)
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    
    let filename: String
    if s == 16 { filename = "icon_16x16.png" }
    else if s == 32 { filename = "icon_16x16@2x.png" }
    else if s == 64 { filename = "icon_32x32@2x.png" }
    else if s == 128 { filename = "icon_128x128.png" }
    else if s == 256 { filename = "icon_128x128@2x.png" }
    else if s == 512 { filename = "icon_512x512.png" }
    else { filename = "icon_512x512@2x.png" }
    
    let path = "\(iconsetDir)/\(filename)"
    try? png.write(to: URL(fileURLWithPath: path))
}

// Also save 32x32 for icon_32x32.png and 256x256 for icon_256x256.png
let img32 = renderLogo(size: 32)
if let tiff = img32.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "\(iconsetDir)/icon_32x32.png"))
}
let img256 = renderLogo(size: 256)
if let tiff = img256.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "\(iconsetDir)/icon_256x256.png"))
}

// Also export master high-res 1024x1024 AppIcon.png
let master = renderLogo(size: 1024)
if let tiff = master.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
    let target = "/Users/zorax/op/repos/powertools/TrackpadToggle/Resources/AppIcon.png"
    try? png.write(to: URL(fileURLWithPath: target))
    print("Master AppIcon.png written to \(target)")
}

print("Iconset created at \(iconsetDir)")
