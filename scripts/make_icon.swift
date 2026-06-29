import AppKit

// Generates the Burnrate app icon (white flame on an orange→red squircle)
// at every size the macOS AppIcon set needs.

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(px: Int) -> Data? {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    // Rounded-rect (squircle-ish) background with a small margin.
    let margin = size * 0.10
    let rect = NSRect(x: margin, y: margin, width: size - 2 * margin, height: size - 2 * margin)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.20, alpha: 1), // warm orange
        NSColor(calibratedRed: 0.95, green: 0.28, blue: 0.13, alpha: 1)  // red
    ])
    gradient?.draw(in: path, angle: -90)

    // White flame, centered, preserving aspect.
    let config = NSImage.SymbolConfiguration(paletteColors: [.white])
        .applying(NSImage.SymbolConfiguration(pointSize: size * 0.6, weight: .bold))
    if let symbol = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let targetH = rect.height * 0.62
        let scale = targetH / s.height
        let targetW = s.width * scale
        let drawRect = NSRect(
            x: rect.midX - targetW / 2,
            y: rect.midY - targetH / 2,
            width: targetW, height: targetH
        )
        symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for px in sizes {
    guard let data = drawIcon(px: px) else {
        FileHandle.standardError.write("failed at \(px)\n".data(using: .utf8)!)
        continue
    }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("icon_\(px).png")
    try? data.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
