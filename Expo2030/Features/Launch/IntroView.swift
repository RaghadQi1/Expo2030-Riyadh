import SwiftUI

/// 05.01 – 05.04: native launch screen (Info.plist) → light lines → glass sweep → reveal to photo.
/// Frames: A (0 ms) lines begin, B (450 ms) lines + glass sweep, C (1100 ms) reveal to photo.
struct IntroView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0   // 0 = launch (05.01), 1 = A, 2 = B, 3 = C

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Color.brandPrimary

                // C · «Photo/Canyon Pavilions» placeholder gradient (90%) + brand scrim.
                ZStack {
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x334561), location: 0),
                        .init(color: Color(hex: 0xC7855C), location: 0.55),
                        .init(color: Color(hex: 0x8C5438), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .opacity(0.9)
                    LinearGradient(stops: [
                        .init(color: Color(red: 0, green: 79 / 255, blue: 59 / 255).opacity(0.85), location: 0),
                        .init(color: Color(red: 0, green: 79 / 255, blue: 59 / 255).opacity(0.35), location: 0.6),
                        .init(color: Color(red: 0, green: 79 / 255, blue: 59 / 255).opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .opacity(stage >= 3 ? 1 : 0)

                // Diamond light lines (Ring 1).
                Image("intro-diamond-ring")
                    .resizable()
                    .scaledToFit()
                    .frame(width: (stage >= 2 ? 371.6 : 315) / 393 * w)
                    .opacity(stage == 0 || stage >= 3 ? 0 : 1)

                // Glass light sweep: 220×1200, rotated 20°, white 16% centre, blur 12.
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.16), .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 220, height: 1200)
                    .blur(radius: 12)
                    .rotationEffect(.degrees(20))
                    .offset(x: sweepOffset(width: w))
                    .opacity(stage == 2 ? 1 : 0)
                    .environment(\.layoutDirection, .leftToRight)

                // Logo (white): 240 centred → 250 → 180 at top.
                Image("logo-expo-riyadh")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: logoWidth)
                    .position(x: w / 2, y: stage >= 3 ? 140 : h / 2)
                    .accessibilityLabel("إكسبو 2030 الرياض")
            }
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    private var logoWidth: CGFloat {
        switch stage {
        case 2: 250
        case 3: 180
        default: 240
        }
    }

    private func sweepOffset(width: CGFloat) -> CGFloat {
        // Figma x positions of the sweep: −400 (A) → 90 (B) → 520 (C), relative to a 393pt frame.
        let x: CGFloat = stage <= 1 ? -400 : (stage == 2 ? 90 : 520)
        return (x + 308) - width / 2
    }

    @MainActor
    private func run() async {
        if reduceMotion {
            stage = 3
            try? await Task.sleep(for: .milliseconds(700))
            onFinished()
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.45)) { stage = 1 }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeInOut(duration: 0.65)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(650))
        withAnimation(.easeInOut(duration: 0.7)) { stage = 3 }
        try? await Task.sleep(for: .milliseconds(1100))
        onFinished()
    }
}
