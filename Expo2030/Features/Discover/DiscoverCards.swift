import SwiftUI

/// Figma «Card/Pavilion» (1:3807): photo, crowd chip, save, entry + axis tags, name, type · organiser,
/// walk + hours, recommendation reason and data freshness. No ratings or invented match scores.
struct PavilionCard: View {
    enum Size { case large, carousel }
    let pavilion: Pavilion
    var size: Size = .large
    var isSaved = false
    var onSave: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                PhotoView(name: pavilion.photo)
                    .overlay(Color.black.opacity(0.18))
                HStack(alignment: .top) {
                    CrowdBadge(level: pavilion.live.crowd)
                        .padding(2)
                        .background(Color.bgSurfaceTranslucent, in: Capsule())
                    Spacer()
                    Button(action: onSave) {
                        Icon(.heart, size: 20, color: isSaved ? .crowdHigh : .textPrimary)
                            .frame(width: 40, height: 40)
                            .glassBackground(Circle(), tint: .glassTint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSaved ? "إزالة من المحفوظة" : "حفظ")
                }
                .padding(12)
            }
            .frame(height: size == .large ? 190 : 150)
            .clipped()

            VStack(alignment: .leading, spacing: size == .large ? 12 : 8) {
                HStack(spacing: 6) {
                    Tag(text: pavilion.axis.title, background: pavilion.axis.color)
                    Tag(text: pavilion.entry.title, foreground: entryForeground, background: entryBackground)
                }
                Text(pavilion.name)
                    .textStyle(size == .large ? .title3 : .headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text("\(pavilion.experienceType) · الجهة: \(pavilion.organization)")
                    .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 12) {
                    if let walk = pavilion.walkMinutes, let distance = pavilion.distanceMeters {
                        meta(.walk, "\(walk) د مشيًا · \(distance) م")
                    }
                    meta(.clock, "\(pavilion.hours.replacingOccurrences(of: " – ", with: "–")) · \(pavilion.durationMinutes) د")
                }
                if let reason = pavilion.recommendationReason {
                    HStack(spacing: 6) {
                        Icon(.sparkles, size: 14, color: .brandPrimary)
                        Text(reason).textStyle(.caption).foregroundStyle(Color.brandPrimary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if size == .large {
                    LiveFreshness(status: pavilion.live)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: size == .carousel ? 264 : nil)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .combine)
    }

    private var entryForeground: Color {
        if case .externalBooking = pavilion.entry { return .statusInfo }
        return .statusSuccess
    }

    private var entryBackground: Color {
        if case .externalBooking = pavilion.entry { return .statusInfoBg }
        return .statusSuccessBg
    }

    private func meta(_ icon: AppIcon, _ text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 14, color: .textSecondary)
            Text(text).textStyle(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
        }
    }
}

/// Figma «Data Freshness» (1:3794): «محدَّث قبل دقيقتين» + refresh (green), stale > 10 min = warning + clock.
struct LiveFreshness: View {
    let status: LiveStatus
    var body: some View {
        HStack(spacing: 4) {
            Icon(status.isStale ? .clock : .refresh, size: 13, color: status.isStale ? .statusWarning : .statusSuccess)
            Text(status.isStale ? "آخر تحديث قبل \(status.updatedMinutesAgo) دقيقة" : shortText)
                .textStyle(.caption2)
                .foregroundStyle(status.isStale ? Color.statusWarning : Color.statusSuccess)
        }
        .accessibilityElement(children: .combine)
    }

    private var shortText: String {
        switch status.updatedMinutesAgo {
        case 0: "محدَّث الآن"
        case 1: "محدَّث قبل دقيقة"
        case 2: "محدَّث قبل دقيقتين"
        default: "محدَّث قبل \(status.updatedMinutesAgo) دقائق"
        }
    }
}

/// Figma «Card/Event Row»: chevron (left), texts, mint time block (right).
struct EventRow: View {
    let event: ExpoEvent
    var minutesUntilStart: Int? = nil

    var body: some View {
        HStack(spacing: 12) {
            Text(event.start.h24)
                .font(AppFont.latin(17, .semibold))
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                statusTag
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.chevronLeft, size: 18, color: .textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [event.venue.components(separatedBy: " · ").last ?? event.venue, "\(event.durationMinutes) د"]
        if event.isPinnedInPlan { parts.append("مثبتة في خطتك ★") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var statusTag: some View {
        if case .externalBooking = event.entry {
            Tag(text: "يتطلب حجزًا خارجيًا", foreground: .statusInfo, background: .statusInfoBg)
        } else if let m = minutesUntilStart, m <= 15 {
            Tag(text: "يبدأ بعد \(m) د", foreground: .statusWarning, background: .statusWarningBg)
        } else {
            Tag(text: "يبدأ \(event.start.arabic12h)", foreground: .textSecondary, background: .bgSurface2)
        }
    }
}

/// Discover «رحلتك اليوم» card — aerial night photo, scrim, route glow and «ابدأ الاتجاهات».
struct NextStopCard: View {
    let summary: NextStopSummary
    var onDirections: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Artwork layer uses absolute Figma positions, so it is laid out left-to-right.
            ZStack(alignment: .topLeading) {
                Image("photo-expo-aerial-night").resizable().scaledToFill()
                    .frame(height: 223).frame(maxWidth: .infinity).clipped()
                LinearGradient(stops: [.init(color: Color(red: 10 / 255, green: 13 / 255, blue: 18 / 255).opacity(0.58), location: 0.09),
                                       .init(color: Color(red: 12 / 255, green: 22 / 255, blue: 38 / 255).opacity(0.58), location: 0.37),
                                       .init(color: Color(red: 14 / 255, green: 42 / 255, blue: 40 / 255).opacity(0.58), location: 0.66)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RouteGlow()
                    .frame(width: 134, height: 107, alignment: .topLeading)
                    .padding(.leading, 43)
                    .padding(.top, 87)
            }
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.progressText).textStyle(.footnote).foregroundStyle(Color.brandAccent)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule().fill(Color.brandAccent).frame(width: geo.size.width * summary.progress)
                        }
                    }
                    .frame(height: 4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary.title).font(AppFont.arabic(16, .semibold)).foregroundStyle(Color.white)
                    Text(summary.subtitle).textStyle(.footnote).foregroundStyle(Color.white)
                    Text(summary.startsAt).textStyle(.caption).foregroundStyle(Color.brandAccent)
                }
                .frame(maxWidth: 225, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 27)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDirections) {
                ButtonLabel(title: "ابدأ الاتجاهات", icon: .navigate)
            }
            .appButton(.primary, height: 45, fullWidth: false)
            .frame(width: 160)
            .padding(.leading, 24)
            .padding(.top, 164)
        }
        .frame(height: 223)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 12)
        .accessibilityElement(children: .contain)
    }
}

/// Decorative glowing route drawn over the aerial photo.
private struct RouteGlow: View {
    var body: some View {
        let points: [CGPoint] = [CGPoint(x: 0, y: 104), CGPoint(x: 28, y: 86), CGPoint(x: 44, y: 70), CGPoint(x: 62, y: 66),
                                 CGPoint(x: 76, y: 44), CGPoint(x: 96, y: 36), CGPoint(x: 108, y: 18), CGPoint(x: 128, y: 14)]
        ZStack(alignment: .topLeading) {
            Path { p in p.addLines(points) }
                .stroke(Color.brandAccent.opacity(0.35), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                .blur(radius: 4)
            Path { p in p.addLines(points) }
                .stroke(Color.brandAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            Circle().fill(Color.white).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.brandAccent, lineWidth: 3))
                .padding(.leading, 122)
                .padding(.top, 8)
        }
        .accessibilityHidden(true)
    }
}

/// Axis circle (62 pt) with label — «المحاور».
struct AxisButton: View {
    let axis: ExpoAxis
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Icon(axis.icon, size: 26, color: .white)
                    .frame(width: 62, height: 62)
                    .background(axis.color, in: Circle())
                Text(axis.title).textStyle(.caption).foregroundStyle(Color.textPrimary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("محور \(axis.title)")
    }
}
