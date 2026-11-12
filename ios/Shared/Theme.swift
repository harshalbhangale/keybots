import SwiftUI

/// AIRKEY's look: deep ink, warm bone type, one mint accent, and two signal
/// colours that only ever mean "needs you" (amber) and "stopped" (red).
enum AK {
    static let ink = Color(hex: 0x0A0A0B)
    static let surface = Color(hex: 0x141416)
    static let raised = Color(hex: 0x1C1C1F)
    static let line = Color(hex: 0x26262A)
    static let bone = Color(hex: 0xF2EEE6)
    static let muted = Color(hex: 0x8C877F)
    static let faint = Color(hex: 0x56534E)
    static let mint = Color(hex: 0x00E59B)
    static let amber = Color(hex: 0xFFB224)
    static let red = Color(hex: 0xFF4D4F)

    static let radius: CGFloat = 14
    static let gutter: CGFloat = 20

    static func title(_ size: CGFloat = 30) -> Font { .system(size: size, weight: .semibold, design: .default) }
    static let body = Font.system(size: 16, weight: .regular)
    static let label = Font.system(size: 12, weight: .semibold).width(.expanded)
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static func number(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold).monospacedDigit() }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// The three outcomes, and how each one looks everywhere.
enum Signal {
    case allow, warn, block, quote, neutral

    var color: Color {
        switch self {
        case .allow: AK.mint
        case .warn: AK.amber
        case .block: AK.red
        case .quote: AK.bone
        case .neutral: AK.muted
        }
    }

    var word: String {
        switch self {
        case .allow: "PAID"
        case .warn: "APPROVE?"
        case .block: "BLOCKED"
        case .quote: "QUOTE"
        case .neutral: "NOT SENT"
        }
    }

    init(outcome: String) {
        switch outcome {
        case "paid": self = .allow
        case "approval": self = .warn
        case "blocked": self = .block
        case "quoted": self = .quote
        default: self = .neutral
        }
    }
}
