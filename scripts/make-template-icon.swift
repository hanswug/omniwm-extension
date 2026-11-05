// Renders a monochrome template PNG (black + alpha) from an app icon (PDR §7.4).
//
// Mask source:
//   - the icon's alpha silhouette, when the icon has real transparency;
//   - otherwise (opaque icon, e.g. a glyph on a solid tile) a luminance mask:
//     pixels darker than the tile background become opaque.
//
// Usage: swift scripts/make-template-icon.swift <input.icns> <output.png> <pixels>
import AppKit

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count == 4, let pixels = Int(args[3]), pixels > 0 else {
    fail("usage: make-template-icon.swift <input.icns> <output.png> <pixels>", code: 2)
}
guard let icon = NSImage(contentsOfFile: args[1]) else { fail("cannot read \(args[1])") }

let bytesPerRow = pixels * 4
var buffer = [UInt8](repeating: 0, count: bytesPerRow * pixels)
let colorSpace = CGColorSpaceCreateDeviceRGB()
var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
guard let cgIcon = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { fail("no bitmap") }

buffer.withUnsafeMutableBytes { raw in
    guard let ctx = CGContext(
        data: raw.baseAddress, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("no context") }
    ctx.interpolationQuality = .high
    ctx.draw(cgIcon, in: rect)
}

let count = pixels * pixels
func alpha(_ i: Int) -> Double { Double(buffer[i * 4 + 3]) / 255 }
func luminance(_ i: Int) -> Double {
    let a = max(alpha(i), 1e-6) // un-premultiply
    let r = Double(buffer[i * 4]) / 255 / a
    let g = Double(buffer[i * 4 + 1]) / 255 / a
    let b = Double(buffer[i * 4 + 2]) / 255 / a
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

let opaqueShare = Double((0..<count).filter { alpha($0) > 0.98 }.count) / Double(count)
var mask = [Double](repeating: 0, count: count)

if opaqueShare < 0.9 {
    print("\(args[2]): alpha silhouette")
    for i in 0..<count { mask[i] = alpha(i) }
} else {
    // Background = median luminance of opaque pixels (the tile dominates); foreground = darkest.
    let lums = (0..<count).filter { alpha($0) > 0.98 }.map(luminance).sorted()
    let background = lums[lums.count / 2]
    let foreground = lums.first ?? 0
    let span = max(background - foreground, 0.05)
    print("\(args[2]): luminance mask (bg \(String(format: "%.2f", background)), fg \(String(format: "%.2f", foreground)))")
    for i in 0..<count {
        let t = (background - luminance(i)) / span
        mask[i] = min(max(t, 0), 1) * alpha(i)
    }
}

// Write black with the mask as alpha (premultiplied → RGB stays 0).
for i in 0..<count {
    buffer[i * 4] = 0
    buffer[i * 4 + 1] = 0
    buffer[i * 4 + 2] = 0
    buffer[i * 4 + 3] = UInt8((mask[i] * 255).rounded())
}

let out: CGImage? = buffer.withUnsafeMutableBytes { raw in
    CGContext(
        data: raw.baseAddress, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
}
guard let out, let png = NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:]) else {
    fail("cannot encode PNG")
}
do {
    try png.write(to: URL(filePath: args[2]))
} catch {
    fail("cannot write \(args[2]): \(error)")
}
