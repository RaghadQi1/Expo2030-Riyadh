import SwiftUI

/// White bottom panel used by every «خريطتي» task sheet (grabber, radius 28, soft upward shadow).
struct MapPanelContainer<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber()
            content()
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: Radius.sheet, topTrailingRadius: Radius.sheet, style: .continuous)
                .fill(Color.bgSurface)
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .shadowTint.opacity(0.12), radius: 16, y: -4)
    }
}

/// Panel header: title block on the right, 32-pt round button on the left (back «›» / close «×»).
struct MapPanelHeader: View {
    var eyebrow: String? = nil
    let title: String
    var subtitle: String? = nil
    var icon: AppIcon? = nil
    var iconTint: Color = .brandPrimary
    var iconBackground: Color = .brandMint
    var buttonIcon: AppIcon = .chevronLeft
    var buttonLabel = "رجوع"
    var onButton: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon {
                Icon(icon, size: 22, color: iconTint)
                    .frame(width: 44, height: 44)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow { Text(eyebrow).textStyle(.caption).foregroundStyle(Color.textSecondary) }
                Text(title).textStyle(.title3).foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle { Text(subtitle).textStyle(.footnote).foregroundStyle(Color.textSecondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let onButton {
                Button(action: onButton) {
                    Icon(buttonIcon, size: 16, color: .textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.bgSurface2, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(buttonLabel)
            }
        }
    }
}

/// Grey stat chip with an icon («٤ د», «١٨٠ م»).
struct StatChip: View {
    var icon: AppIcon? = nil
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Text(text).textStyle(.caption).foregroundStyle(Color.textSecondary)
            if let icon { Icon(icon, size: 13, color: .textSecondary) }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.bgSurface2, in: Capsule())
    }
}

/// Glass control used on the map (48 pt).
struct MapControlButton: View {
    let icon: AppIcon
    let label: String
    var isActive = false
    var action: () -> Void

    var body: some View {
        GlassIconButton(icon: icon, size: 44, iconSize: 20,
                        iconColor: isActive ? .white : .textPrimary,
                        tint: isActive ? .brandPrimary : .glassTintStrong,
                        accessibilityLabel: label, action: action)
    }
}

/// Dark tooltip next to a map control («منظور علوي مسطّح…»).
struct MapHint: View {
    let text: String
    var icon: AppIcon? = nil
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Icon(icon, size: 14, color: .white) }
            Text(text).textStyle(.caption).foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.textPrimary.opacity(0.88), in: Capsule())
    }
}

/// Booth logo tile (mint 40, radius 12, brand initials).
struct BoothLogo: View {
    let text: String
    var size: CGFloat = 40
    var body: some View {
        Text(text)
            .font(AppFont.latin(size * 0.3, .semibold))
            .foregroundStyle(Color.brandPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(4)
            .frame(width: size, height: size)
            .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Booth photo, or an illustrated placeholder in the brand tint when the booth has no photo (Figma 2.1 uses shapes).
struct BoothPhoto: View {
    let booth: Booth
    var body: some View {
        if let photo = booth.photo {
            PhotoView(name: photo)
        } else {
            ZStack {
                LinearGradient(colors: [Color.brandMint, Color.brandPrimary.opacity(0.35)], startPoint: .topTrailing, endPoint: .bottomLeading)
                Circle().fill(Color.white.opacity(0.25)).frame(width: 90).offset(x: -60, y: 20)
                RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.18)).frame(width: 70, height: 50).offset(x: 70, y: -20)
                Text(booth.logoText).font(AppFont.latin(28, .semibold)).foregroundStyle(Color.brandPrimary.opacity(0.7))
            }
            .accessibilityHidden(true)
        }
    }
}

/// Route option row (2.3): radio + title on the right, minutes on the left, crowd + note below.
struct RouteOptionRow: View {
    let route: Route
    var title: String? = nil
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    RadioDot(isOn: isSelected)
                    Text(title ?? route.kind.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(ArabicDigits.minutes(route.minutes)).textStyle(.headline).foregroundStyle(Color.textPrimary)
                }
                HStack(spacing: 8) {
                    CrowdBadge(level: route.crowdOnRoute, style: .map)
                    if !route.note.isEmpty {
                        Text(route.note).textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Text("\(ArabicDigits.format(route.meters)) م").textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(14)
            .background(isSelected ? Color.brandMint : Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.brandPrimary : Color.borderDefault, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct RadioDot: View {
    var isOn: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Color.brandPrimary : Color.borderStrong, lineWidth: 1.5)
            if isOn { Circle().fill(Color.brandPrimary).padding(4) }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// White settings-style group (5.11).
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .cardShadow()
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: AppIcon
    var iconTint: Color = .brandPrimary
    var iconBackground: Color = .brandMint
    let title: String
    var titleColor: Color = .textPrimary
    var subtitle: String? = nil
    var showsDivider = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Icon(icon, size: 18, color: iconTint)
                    .frame(width: 36, height: 36)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.bodyStrong).foregroundStyle(titleColor)
                    if let subtitle { Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            if showsDivider { Divider().padding(.leading, 62) }
        }
    }
}

/// «مباشر» blue status pill (5.7 / 5.11).
struct LivePill: View {
    var text = "مباشر"
    var active = true
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(active ? Color.locationBlue : Color.textTertiary).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            Text(text).textStyle(.caption).foregroundStyle(active ? Color.locationBlue : Color.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(active ? Color.locationBlueBg : Color.bgSurface2, in: Capsule())
    }
}
