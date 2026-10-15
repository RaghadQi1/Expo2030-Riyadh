import SwiftUI

// MARK: - Crowd badge (Figma «Crowd Badge» 1:3781 and «خريطتي/Crowd Badge» 1:674)

extension CrowdLevel {
    var color: Color {
        switch self {
        case .low: .crowdLow
        case .medium: .crowdMedium
        case .high: .crowdHigh
        case .unknown: .crowdUnknown
        }
    }

    var background: Color {
        switch self {
        case .low: .crowdLowBg
        case .medium: .crowdMediumBg
        case .high: .crowdHighBg
        case .unknown: .crowdUnknownBg
        }
    }

    /// Wording used by the plan / discover screens.
    var badgeTitle: String {
        switch self {
        case .low: "ازدحام منخفض"
        case .medium: "ازدحام متوسط"
        case .high: "ازدحام مرتفع"
        case .unknown: "ازدحام غير معروف"
        }
    }

    /// Wording used by «خريطتي».
    var mapTitle: String {
        switch self {
        case .low: "هادئ"
        case .medium: "ازدحام متوسط"
        case .high: "مزدحم"
        case .unknown: "غير معروف"
        }
    }
}

/// Crowd level — always shape/icon + word + colour, never colour alone.
struct CrowdBadge: View {
    enum Style { case standard, map, mapCompact }
    let level: CrowdLevel
    var style: Style = .standard

    var body: some View {
        HStack(spacing: style == .standard ? 6 : 4) {
            // RTL: first child sits on the right (glyph/icon on the right, as drawn).
            if style == .standard {
                Text(level.glyph).font(AppFont.latin(12, .medium)).foregroundStyle(level.color)
                Text(level.badgeTitle).textStyle(.caption)
                    .foregroundStyle(level == .unknown ? Color.textSecondary : level.color)
            } else {
                Text(level.mapTitle)
                    .font(style == .mapCompact ? AppFont.arabic(10.2, .medium) : AppFont.arabic(12, .medium))
                    .foregroundStyle(level.color)
                Icon(level == .low ? .quiet : (level == .unknown ? .info : .busy), size: style == .mapCompact ? 12 : 14, color: level.color)
            }
        }
        .padding(.horizontal, style == .mapCompact ? 8.5 : 10)
        .padding(.vertical, style == .mapCompact ? 3.4 : 4)
        .background(level.background, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style == .standard ? level.badgeTitle : level.mapTitle)
    }
}

// MARK: - Chips & pills

/// Filter / interest chip (Figma «Chip» 1:4252). Selected = mint fill + check (not colour alone).
struct SelectableChip: View {
    let title: String
    var isSelected: Bool
    var icon: AppIcon? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected { Icon(.check, size: 16, color: .brandPrimary) }
                else if let icon { Icon(icon, size: 16, color: .textSecondary) }
                Text(title).textStyle(.subhead)
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textPrimary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(isSelected ? Color.brandMint : Color.bgSurface, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.brandPrimary : Color.borderDefault, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// White outlined action pill with a 16-pt icon («أنهي زيارتي», «أضف محطة»…).
struct ActionPill: View {
    let title: String
    var icon: AppIcon? = nil
    var style: Style = .outline
    var action: () -> Void

    enum Style { case outline, mint }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16, color: style == .mint ? .brandPrimary : .textPrimary) }
                Text(title)
                    .font(style == .mint ? AppFont.arabic(12, .medium) : AppFont.arabic(13, .regular))
                    .foregroundStyle(style == .mint ? Color.brandPrimary : Color.textPrimary)
            }
            .padding(.horizontal, style == .mint ? 14 : 12)
            .padding(.vertical, 8)
            .background(style == .mint ? Color.brandMint : Color.bgSurface, in: Capsule())
            .overlay {
                if style == .outline { Capsule().strokeBorder(Color.borderDefault, lineWidth: 1) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small rounded tag (AR/Caption 2) — «جديد · بديل…», «★ أولوية مثبتة», «حذف».
struct Tag: View {
    let text: String
    var foreground: Color = .textOnImage
    var background: Color = .brandPrimary
    var icon: AppIcon? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 12, color: foreground) }
            Text(text).textStyle(.caption2).foregroundStyle(foreground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(background, in: Capsule())
    }
}

/// Grey info pill («18 د مشي», «٣ د مشيًا»).
struct InfoPill: View {
    let text: String
    var background: Color = .bgSurface2
    var foreground: Color = .textSecondary
    var body: some View {
        Text(text).textStyle(.caption).foregroundStyle(foreground)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

/// «محدّث قبل دقيقتين · المصدر: …» — data freshness line. Stale (> 10 min) turns warning.
struct FreshnessLine: View {
    let status: LiveStatus
    var body: some View {
        HStack(spacing: 5) {
            Icon(.refresh, size: 13, color: status.isStale ? .statusWarning : .crowdLow)
            Text(status.freshnessText).textStyle(.caption)
                .foregroundStyle(status.isStale ? Color.statusWarning : Color.textTertiary)
        }
    }
}

// MARK: - Bottom action bar

/// Translucent bottom bar holding the primary action(s) of a screen (Figma «Bottom action bar»).
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 8) { content() }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color.bgSurfaceTranslucent.ignoresSafeArea(edges: .bottom))
            .shadow(color: Color.shadowTint.opacity(0.12), radius: 12, y: -4)
    }
}

// MARK: - Photo

/// Image from the asset catalog that fills its frame (photos are decorative unless a label is given).
struct PhotoView: View {
    let name: String?
    var label: String? = nil
    var body: some View {
        GeometryReader { geo in
            if let name {
                Image(name).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
            } else {
                LinearGradient(colors: [Color(hex: 0x1A2447), Color(hex: 0x8C614D), Color(hex: 0x47382E)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }
}

/// Avatar (52×56, radius 20, brand hairline) with initials fallback.
struct AvatarView: View {
    let name: String
    var image: String? = nil
    var width: CGFloat = 56
    var height: CGFloat = 52
    var radius: CGFloat = 20

    var body: some View {
        ZStack {
            if let image {
                Image(image).resizable().scaledToFill()
            } else {
                Color.brandPrimary
                Text(String(name.prefix(1))).textStyle(.headline).foregroundStyle(Color.brandOnPrimary)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

// MARK: - Flow layout (wrapping chips)

/// Simple wrapping layout for chips (iOS 16+ Layout). Respects the RTL layout direction.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

extension TimeOfDay {
    /// «3:30» (no suffix) used in timeline time columns (EN/Footnote).
    var shortTime: String {
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12):\(String(format: "%02d", minute))"
    }
}
