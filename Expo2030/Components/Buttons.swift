import SwiftUI

/// Figma component "Button" (1:2730): height 52, radius 16, AR/Button text.
/// Variants observed in the file: Primary, Secondary (mint outline), Tertiary (neutral outline),
/// Ghost/Text (no background), Destructive and Glass (over imagery).
enum AppButtonVariant {
    case primary
    case secondary      // #F1F8F4 fill + 1.5pt brand stroke (e.g. «إنشاء حساب» on Welcome)
    case tertiary       // 1pt border/strong outline (e.g. «إنشاء حساب بدلًا من ذلك»)
    case mint           // Figma "Secondary": brand/mint fill, brand text
    case text           // text-only, 44pt high (e.g. «المتابعة كضيف»)
    case destructive    // status/error fill
    case destructiveOutline
}

struct AppButtonStyle: ButtonStyle {
    var variant: AppButtonVariant = .primary
    var height: CGFloat = 52
    var isLoading = false
    var fullWidth = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        ZStack {
            configuration.label
                .textStyle(.button)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .opacity(isLoading ? 0 : 1)
            if isLoading {
                ProgressView().tint(foreground)
                    .accessibilityLabel("جارٍ التحميل")
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 20)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .frame(height: variant == .text ? 44 : height)
        .background(background(pressed: pressed), in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        .overlay {
            switch variant {
            case .secondary:
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 1.5)
            case .tertiary:
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Color.borderStrong, lineWidth: 1)
            case .destructiveOutline:
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(Color.statusError, lineWidth: 1)
            default:
                EmptyView()
            }
        }
        .opacity(isEnabled ? 1 : 0.38)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: pressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive: return .brandOnPrimary
        case .secondary, .tertiary, .mint, .text: return .brandPrimary
        case .destructiveOutline: return .statusError
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary: return pressed ? .brandPrimaryPressed : .brandPrimary
        case .secondary: return Color(red: 0xf1 / 255, green: 0xf8 / 255, blue: 0xf4 / 255).opacity(pressed ? 0.8 : 1)
        case .mint: return pressed ? .brandMint.opacity(0.7) : .brandMint
        case .tertiary, .text, .destructiveOutline: return pressed ? .bgSurface2 : .clear
        case .destructive: return pressed ? .statusError.opacity(0.85) : .statusError
        }
    }
}

extension View {
    func appButton(_ variant: AppButtonVariant = .primary, isLoading: Bool = false, height: CGFloat = 52, fullWidth: Bool = true) -> some View {
        buttonStyle(AppButtonStyle(variant: variant, height: height, isLoading: isLoading, fullWidth: fullWidth))
    }
}

/// Label with an optional trailing (visual-left in RTL) icon, as the Figma Button `showIcon`.
struct ButtonLabel: View {
    let title: String
    var icon: AppIcon? = nil
    var iconSize: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if let icon {
                Icon(icon, size: iconSize)
            }
        }
    }
}

/// Small circular/rounded icon button used in headers (QR, notifications, close, back…).
struct CircleIconButton: View {
    let icon: AppIcon
    var size: CGFloat = 44
    var iconSize: CGFloat = 22
    var background: Color = .bgSurface
    var foreground: Color = .textPrimary
    var shadow = true
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: foreground)
                .frame(width: size, height: size)
                .background(background, in: Circle())
                .modifier(OptionalCardShadow(enabled: shadow))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct OptionalCardShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.cardShadow() } else { content }
    }
}

/// Glass round button used over photos and on the map (48pt, glass/tint fill, border/default stroke).
struct GlassIconButton: View {
    let icon: AppIcon
    var size: CGFloat = 48
    var iconSize: CGFloat = 22
    var iconColor: Color = .textPrimary
    var tint: Color = .glassTint
    var stroke: Color = .borderDefault
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize, color: iconColor)
                .frame(width: size, height: size)
                .glassBackground(Circle(), tint: tint, stroke: stroke)
                .glassShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
