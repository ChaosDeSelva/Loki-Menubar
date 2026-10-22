import AppKit

@main
 enum IconRenderer {
    static func main() throws {
        let folder = CommandLine.arguments[1]
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let context = NSGraphicsContext.current!.cgContext
                context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
                let paths = LokiGlyph.paths(in: CGRect(x: 110, y: 70, width: 804, height: 884), flipped: true)
                for (index, path) in paths.enumerated() {
                    let color = index == 0
                        ? NSColor(srgbRed: 23 / 255, green: 53 / 255, blue: 40 / 255, alpha: 1)
                        : NSColor(srgbRed: 194 / 255, green: 230 / 255, blue: 133 / 255, alpha: 1)
                    context.setFillColor(color.cgColor)
                    context.addPath(path)
                    context.fillPath()
                }
                NSGraphicsContext.restoreGraphicsState()
                let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: folder).appendingPathComponent(filename))
            }
        }
    }
}
