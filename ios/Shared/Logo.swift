import SwiftUI

/// The AIRKEY mark: the mascot, a white keycap on its black switch with a lime light
/// (the image is `Mascot.xcassets/MascotMark`). `tab` and `color` are kept so call sites don't change.
struct KeycapMark: View {
    var size: CGFloat = 28
    var tab: Color = AK.accent
    var color: Color = AK.bone

    var body: some View {
        Image("MascotMark")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: size * 0.45) {
            KeycapMark(size: size * 1.25)
            Text("KEYBOTS")
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .tracking(size * 0.06)
                .foregroundStyle(AK.bone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("KEYBOTS")
    }
}
