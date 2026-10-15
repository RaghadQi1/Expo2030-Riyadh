import SwiftUI

/// Icons exported from the Figma file (Assets.xcassets/Icons, vector, template-rendered so
/// they take the foreground color like the Figma strokes do).
enum AppIcon: String, CaseIterable {
    case accessible, addPerson = "add-person", bell, briefcase, camera, check
    case chevronLeft = "chevron-left", chevronRight = "chevron-right"
    case clock, close, coffee, compass, cube, door, droplet, file, filter, flag, flashlight
    case eye, globe, heart, home, image, info, journey, link, lock, mail, map, mic, minus, navigate
    case note, plan, plus, qr, recenter, refresh, route, search, send, share, sparkles, star
    case trash, undo, user, users, volume, walk, warning
    case turnLeft = "turn-left", turnRight = "turn-right", landmark, busy, quiet, compare

    var assetName: String { "icon-\(rawValue)" }
}

extension Image {
    init(_ icon: AppIcon) {
        self.init(icon.assetName)
    }
}

/// Sized icon view (Figma icons are square frames: 14, 16, 18, 20, 22, 24, 26 pt).
struct Icon: View {
    let icon: AppIcon
    var size: CGFloat = 22
    var color: Color? = nil
    /// Chevrons point "forward" in RTL. Set to false for icons that must not mirror.
    var flipsForRTL: Bool = false

    init(_ icon: AppIcon, size: CGFloat = 22, color: Color? = nil, flipsForRTL: Bool = false) {
        self.icon = icon
        self.size = size
        self.color = color
        self.flipsForRTL = flipsForRTL
    }

    var body: some View {
        Image(icon)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .modifier(OptionalForeground(color: color))
            .flipsForRightToLeftLayoutDirection(flipsForRTL)
            .accessibilityHidden(true)
    }
}

/// `nil` keeps the inherited foreground style (e.g. a button's label color).
private struct OptionalForeground: ViewModifier {
    let color: Color?
    func body(content: Content) -> some View {
        if let color { content.foregroundStyle(color) } else { content }
    }
}

/// The down chevron is the Figma chevron-left asset rotated (no separate export exists).
struct ChevronDown: View {
    var size: CGFloat = 18
    var color: Color = .textSecondary
    var body: some View {
        Icon(.chevronLeft, size: size, color: color).rotationEffect(.degrees(-90))
    }
}
