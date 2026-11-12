// Renders the AIRKEY app icon (1024x1024): the keycap mark on ink.
// swift tools/make-icon.swift AirKey/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
func c(_ hex: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) }

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

c(0x0A0A0B).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let cap: CGFloat = 520
let capRect = NSRect(x: (size - cap) / 2 - 18, y: (size - cap) / 2, width: cap, height: cap)
let path = NSBezierPath(roundedRect: capRect, xRadius: cap * 0.26, yRadius: cap * 0.26)
path.lineWidth = cap * 0.085
c(0xF2EEE6).setStroke()
path.stroke()

let tabW = cap * 0.13, tabH = cap * 0.46
let tab = NSBezierPath(roundedRect: NSRect(x: capRect.maxX - tabW / 2 + cap * 0.065, y: capRect.midY - tabH / 2, width: tabW, height: tabH), xRadius: tabW / 2, yRadius: tabW / 2)
c(0xC6F25A).setFill()
tab.fill()

let a = NSAttributedString(string: "A", attributes: [.font: NSFont.systemFont(ofSize: cap * 0.5, weight: .bold), .foregroundColor: c(0xF2EEE6)])
let s = a.size()
a.draw(at: NSPoint(x: capRect.midX - s.width / 2, y: capRect.midY - s.height / 2))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
