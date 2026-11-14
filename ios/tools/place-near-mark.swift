import AppKit
// usage: nearmark in.png out.png
let a = CommandLine.arguments
let base = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[1])))!
let W = base.pixelsWide, H = base.pixelsHigh
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(base.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
// The cap's top face (image coordinates, y down): bottom, right, left corners.
let Bc = CGPoint(x: 513, y: 430), Rc = CGPoint(x: 668, y: 373), Lc = CGPoint(x: 357, y: 372)
func pt(_ gx: Double, _ gy: Double) -> CGPoint {   // glyph coords, +-0.5, y up
    let s = gx + 0.5, t = gy + 0.5
    let x = Bc.x + s * (Rc.x - Bc.x) + t * (Lc.x - Bc.x)
    let y = Bc.y + s * (Rc.y - Bc.y) + t * (Lc.y - Bc.y)
    return CGPoint(x: x, y: CGFloat(H) - y)           // flip to CG's y-up
}
let k = 0.68
// The official mark: black on green. Opacity comes from how far each pixel is from the green.
let logo = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: a[3])))!
let LW = logo.pixelsWide, LH = logo.pixelsHigh
var px = [UInt8](repeating: 0, count: LW * LH * 4)
var minX = LW, maxX = 0, minY = LH, maxY = 0
for y in 0..<LH { for x in 0..<LW {
    let c = logo.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
    let al = max(0, min(1, 1 - c.greenComponent / 0.925))
    let i = (y * LW + x) * 4
    px[i] = 10; px[i + 1] = 10; px[i + 2] = 11; px[i + 3] = UInt8(al * 255)
    if al > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
} }
let lctx = CGContext(data: &px, width: LW, height: LH, bitsPerComponent: 8, bytesPerRow: LW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// premultiply fix: colors are near black so the effect is negligible
let mark = lctx.makeImage()!.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
let aspect = Double(mark.width) / Double(mark.height)
// Glyph units (+-0.5, y up) -> screen: affine from the cap's top face.
let o = pt(0, 0), ex = pt(1, 0), ey = pt(0, 1)
ctx.saveGState()
ctx.concatenate(CGAffineTransform(a: ex.x - o.x, b: ex.y - o.y, c: ey.x - o.x, d: ey.y - o.y, tx: o.x, ty: o.y))
let h = k, w = k * aspect
ctx.draw(mark, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
ctx.restoreGState()
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("wrote", a[2], "mark", mark.width, "x", mark.height)
