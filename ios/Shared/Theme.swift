import SwiftUI

/// AIRKEY's look: deep ink, warm bone type, one mint accent, and two signal
/// colours that only ever mean "needs you" (amber) and "stopped" (red).
/// Content sits on quiet translucent surfaces; Liquid Glass is kept for the
/// things you touch: bars, buttons and the chips that report an outcome.
enum AK {
    static let ink = Color(hex: 0x09090B)
    static let surface = Color.white.opacity(0.055)
    static let raised = Color.white.opacity(0.10)
    static let line = Color.white.opacity(0.08)
    static let bone = Color(hex: 0xF2EEE6)
    static let muted = Color(hex: 0xF2EEE6, opacity: 0.58)
    static let faint = Color(hex: 0xF2EEE6, opacity: 0.34)
    static let mint = Color(hex: 0x00E59B)
    static let amber = Color(hex: 0xFFB224)
    static let red = Color(hex: 0xFF4D4F)

    static let radius: CGFloat = 22
    static let gutter: CGFloat = 20

    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static func number(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
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

/// The outcomes, and how each one looks everywhere.
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

    /// Short caps word for chips and shared receipts.
    var word: String {
        switch self {
        case .allow: "PAID"
        case .warn: "APPROVE?"
        case .block: "BLOCKED"
        case .quote: "QUOTE"
        case .neutral: "NOT SENT"
        }
    }

    var title: String {
        switch self {
        case .allow: "Paid"
        case .warn: "Needs your approval"
        case .block: "Blocked"
        case .quote: "Quote"
        case .neutral: "Not sent"
        }
    }

    var icon: String {
        switch self {
        case .allow: "checkmark"
        case .warn: "hand.raised.fill"
        case .block: "xmark"
        case .quote: "arrow.left.arrow.right"
        case .neutral: "minus"
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

/// The app's backdrop: ink, with one soft light at the top that takes the
/// colour of what's going on (mint: all good, amber: waiting for you, red: stopped).
/// It gives the glass something to bend.
struct Ambient: View {
    var tint: Color = AK.mint

    var body: some View {
        ZStack(alignment: .top) {
            AK.ink
            EllipticalGradient(
                colors: [tint.opacity(0.26), tint.opacity(0.07), .clear],
                center: .top,
                startRadiusFraction: 0,
                endRadiusFraction: 0.9
            )
            .frame(height: 460)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: tint)
    }
}
