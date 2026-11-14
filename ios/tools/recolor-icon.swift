// Swaps the dark background of the app icon for a linear gradient with fine diagonal lines.
// swiftc -O ios/tools/recolor-icon.swift -o /tmp/recolor && /tmp/recolor original.png AppIcon.png a   (a = indigo to teal, b = calmer)
import AppKit
// usage: recolor in.png out.png variant
let args = CommandLine.arguments
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: args[1])))!
let variant = args[3]
let W = src.pixelsWide, H = src.pixelsHigh
func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    let c = src.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
}
// Which pixels are background: connected to the border, dark and neutral (never the mascot's bright body).
var isBG = [Bool](repeating: false, count: W * H)
var stack: [(Int, Int)] = []
func bgLike(_ x: Int, _ y: Int) -> Bool { let (r, g, b) = rgb(x, y); return g * 255 >= 14 && max(r, g, b) * 255 < 75 }
for i in 0..<W { for (x, y) in [(i, 0), (i, H - 1), (0, i), (W - 1, i)] where bgLike(x, y) && !isBG[y * W + x] { isBG[y * W + x] = true; stack.append((x, y)) } }
while let (x, y) = stack.popLast() {
    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx, ny = y + dy
        if nx >= 0, ny >= 0, nx < W, ny < H, !isBG[ny * W + nx], bgLike(nx, ny) { isBG[ny * W + nx] = true; stack.append((nx, ny)) }
    }
}
func hex(_ h: UInt32) -> (Double, Double, Double) { (Double((h >> 16) & 255) / 255, Double((h >> 8) & 255) / 255, Double(h & 255) / 255) }
let stops: [(Double, (Double, Double, Double))] = variant == "a"
    ? [(0, hex(0x2A2A8C)), (0.55, hex(0x1B6DB3)), (1, hex(0x13B3A4))]
    : [(0, hex(0x0F2A4A)), (0.5, hex(0x1A5C8A)), (1, hex(0x35C6C0))]
func grad(_ t: Double) -> (Double, Double, Double) {
    for i in 1..<stops.count where t <= stops[i].0 {
        let (t0, c0) = stops[i - 1], (t1, c1) = stops[i]; let u = (t - t0) / (t1 - t0)
        return (c0.0 + (c1.0 - c0.0) * u, c0.1 + (c1.1 - c0.1) * u, c0.2 + (c1.2 - c0.2) * u)
    }
    return stops.last!.1
}
var buf = [UInt8](repeating: 255, count: W * H * 4)
for y in 0..<H { for x in 0..<W {
    let (r, g, b) = rgb(x, y)
    var o = (r, g, b)
    if isBG[y * W + x] {
        let t = (Double(x) + Double(y)) / Double(W + H)
        var n = grad(t)
        let d = (x + y) % 36
        if d < 2 { let k = 0.10 * (1 - t * 0.5); n = (n.0 + (1 - n.0) * k, n.1 + (1 - n.1) * k, n.2 + (1 - n.2) * k) }
        let u = min(1, max(0, (g * 255 - 13.5) / 3.5))
        o = (r + (n.0 - r) * u, g + (n.1 - g) * u, b + (n.2 - b) * u)
    }
    let i = (y * W + x) * 4
    buf[i] = UInt8(max(0, min(255, o.0 * 255))); buf[i + 1] = UInt8(max(0, min(255, o.1 * 255))); buf[i + 2] = UInt8(max(0, min(255, o.2 * 255)))
} }
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: &buf, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote", args[2])
