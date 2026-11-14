import SwiftUI

/// A token's mark, the same in the app and the keyboard: NEAR's official
/// mark (bundled), USDC's mark drawn to its spec (Circle's blue disc, a white
/// dollar sign between two arcs), and a letter on a disc for anything else.
/// Nothing is fetched at run time.
struct TokenMark: View {
    let symbol: String
    var size: CGFloat = 18

    var body: some View {
        switch symbol.uppercased() {
        case "NEAR", "WNEAR":
            Image("NearMark").resizable().interpolation(.high).scaledToFill()
                .frame(width: size, height: size).clipShape(Circle())
                .accessibilityLabel("NEAR")
        case "USDC":
            USDCMark(size: size).accessibilityLabel("USDC")
        default:
            Text(String(symbol.prefix(1)).uppercased())
                .font(.system(size: size * 0.55, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(Color.primary.opacity(0.14), in: Circle())
                .accessibilityLabel(symbol)
        }
    }
}

/// USDC's mark: blue disc, white "$", a white arc either side.
struct USDCMark: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x2775CA))
            Canvas { ctx, s in
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let r = s.width * 0.36
                for (from, to) in [(118.0, 242.0), (-62.0, 62.0)] {
                    var arc = Path()
                    arc.addArc(center: c, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                    ctx.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: s.width * 0.075, lineCap: .round))
                }
            }
            Text("$")
                .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Two marks for a swap, the first over the second: NEAR → USDC.
struct TokenPair: View {
    let from: String
    let to: String
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: -size * 0.3) {
            TokenMark(symbol: from, size: size)
            TokenMark(symbol: to, size: size)
                .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(from) to \(to)")
    }

    static let known = ["NEAR", "WNEAR", "USDC", "USDT"]

    /// The first two token symbols named in a line, in order: "Swapped 0.28 NEAR for 0.60 USDC" is NEAR, USDC.
    static func symbols(in line: String) -> (String, String)? {
        let words = line.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { known.contains($0) }
        guard words.count >= 2, words[0] != words[1] else { return nil }
        return (words[0], words[1])
    }
}
