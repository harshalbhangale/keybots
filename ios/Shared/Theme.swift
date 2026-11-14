import SwiftUI

/// AIRKEY's look: deep ink, warm bone type, one lime accent, and two signal
/// colours that only ever mean "needs you" (amber) and "stopped" (red).
/// Content sits on quiet translucent surfaces; Liquid Glass is kept for the
/// things you touch: bars, buttons and the chips that report an outcome.
enum AK {
    /// Text on lime, and the keyboard's dark ink. The same in light and dark.
    static let ink = Color(hex: 0x09090B)
    // The app follows the phone's appearance: these change with light and dark.
    // (The keyboard uses only ink, accent, amber and red.)
    static let canvas = Color(light: 0xF2F2F7, dark: 0x000000)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let raised = Color(light: 0xE9E9EE, dark: 0x2C2C2E)
    static let line = Color(light: 0x3C3C43, dark: 0x545458, opacity: 0.22)
    static let bone = Color(light: 0x111113, dark: 0xF5F5F7)
    static let muted = Color(light: 0x3C3C43, dark: 0xEBEBF5, opacity: 0.62)
    static let faint = Color(light: 0x3C3C43, dark: 0xEBEBF5, opacity: 0.32)
    /// The one accent, and the colour of "all good".
    static let accent = Color(hex: 0xC6F45B)
    /// Lime as text or an icon: lime on dark, a deep olive on light so it can be read.
    static let accentText = Color(light: 0x4C6B00, dark: 0xC6F45B)
    static let amber = Color(hex: 0xFFB224)
    static let red = Color(hex: 0xFF4D4F)
    /// Amber and red as text: darker on light backgrounds.
    static let amberText = Color(light: 0xB25E00, dark: 0xFFB224)
    static let redText = Color(light: 0xD70015, dark: 0xFF5A5C)

    static let radius: CGFloat = 22
    static let gutter: CGFloat = 20

    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static func number(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .semibold, design: .rounded).monospacedDigit() }
}

extension Color {
    /// A colour that follows light and dark.
    init(light: UInt32, dark: UInt32, opacity: Double = 1) {
        self.init(uiColor: UIColor { t in
            let hex = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
    }

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
    case allow, warn, block, quote, watch, neutral

    var color: Color {
        switch self {
        case .allow: AK.accent
        case .warn: AK.amber
        case .block: AK.red
        case .quote, .watch: AK.bone
        case .neutral: AK.muted
        }
    }

    /// The colour for text and icons: deeper on light backgrounds.
    var text: Color {
        switch self {
        case .allow: AK.accentText
        case .warn: AK.amberText
        case .block: AK.redText
        case .quote, .watch: AK.bone
        case .neutral: AK.muted
        }
    }

    /// Short caps word for chips and shared receipts.
    var word: String {
        switch self {
        case .allow: "PAID"
        case .warn: "WAITING"
        case .block: "BLOCKED"
        case .quote: "QUOTE"
        case .watch: "WATCHING"
        case .neutral: "NOT SENT"
        }
    }

    var title: String {
        switch self {
        case .allow: "Paid"
        case .warn: "Waiting for you"
        case .block: "Blocked"
        case .quote: "Quote"
        case .watch: "Watching the price"
        case .neutral: "Not sent"
        }
    }

    var icon: String {
        switch self {
        case .allow: "checkmark"
        case .warn: "hand.raised.fill"
        case .block: "xmark"
        case .quote: "arrow.left.arrow.right"
        case .watch: "eye"
        case .neutral: "minus"
        }
    }

    /// Outcomes that are information, not a verdict: drawn quietly, without a signal colour.
    var plain: Bool { self == .quote || self == .watch || self == .neutral }

    init(outcome: String) {
        switch outcome {
        case "paid", "swapped": self = .allow
        case "approval": self = .warn
        case "blocked": self = .block
        case "quoted": self = .quote
        case "watching": self = .watch
        default: self = .neutral
        }
    }
}

/// The app's backdrop: one flat system-grouped colour. `tint` is kept for
/// callers; the state now shows in the content, not the background.
struct Ambient: View {
    var tint: Color = AK.accent

    var body: some View {
        AK.canvas.ignoresSafeArea()
    }
}
