import SwiftUI

/// The AIRKEY mark: a keycap with a mint side tab. The tab is the "leash":
/// the same tab marks agent keys on the keyboard.
struct KeycapMark: View {
    var size: CGFloat = 28
    var tab: Color = AK.mint

    var body: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(AK.bone, lineWidth: max(1.5, size * 0.085))
                .frame(width: size, height: size)
            Capsule()
                .fill(tab)
                .frame(width: max(2, size * 0.13), height: size * 0.46)
                .offset(x: size * 0.065)
            Text("A")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(AK.bone)
                .frame(width: size, height: size)
        }
        .frame(width: size + size * 0.07, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: size * 0.45) {
            KeycapMark(size: size * 1.25)
            Text("AIRKEY")
                .font(.system(size: size, weight: .heavy).width(.expanded))
                .tracking(size * 0.06)
                .foregroundStyle(AK.bone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AIRKEY")
    }
}
