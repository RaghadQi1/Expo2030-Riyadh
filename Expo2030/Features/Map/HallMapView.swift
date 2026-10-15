import SwiftUI

/// The exhibition-hall map («خريطتي/Map/Exhibition», 496 × 1357.8 pt) with pan, pinch-zoom and tap-to-select.
///
/// Layers (bottom → top):
/// 1. `map-exhibition-base` (booth artwork exported from Figma, no text),
/// 2. crowd heat, highlights, routes and the text labels — drawn in map space and scaled with the map,
/// 3. markers (me, friend, pins, numbered badges) — drawn in screen space so they keep their size.
///
/// The whole view runs left-to-right internally so map coordinates and offsets are never mirrored by RTL.
struct HallMapView: View {
    @Bindable var model: MapModel
    /// Height covered by the bottom panel, so the camera centre stays in the visible part of the map.
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 0

    @State private var dragTranslation: CGSize = .zero
    @State private var pinch: CGFloat = 1

    private let size = CGSize(width: HallMap.width, height: HallMap.height)

    var body: some View {
        GeometryReader { geo in
            let projection = makeProjection(in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.mapGround
                mapLayer
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .scaleEffect(projection.zoom, anchor: .topLeading)
                    .offset(x: projection.origin.x, y: projection.origin.y)
                markerLayer(projection)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(panGesture(zoom: projection.zoom).simultaneously(with: zoomGesture))
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                let p = projection.mapPoint(value.location)
                if let booth = model.booth(at: p), model.navigation == nil { model.select(booth) }
            })
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("خريطة قاعة المعرض")
    }

    // MARK: Projection

    struct Projection {
        var zoom: CGFloat
        var center: MapPoint
        var viewportCenter: CGPoint

        func screen(_ p: MapPoint) -> CGPoint {
            CGPoint(x: viewportCenter.x + (p.x - center.x) * zoom, y: viewportCenter.y + (p.y - center.y) * zoom)
        }
        func mapPoint(_ s: CGPoint) -> MapPoint {
            MapPoint(x: center.x + (s.x - viewportCenter.x) / zoom, y: center.y + (s.y - viewportCenter.y) / zoom)
        }
        var origin: CGPoint { screen(MapPoint(x: 0, y: 0)) }
    }

    private func makeProjection(in viewport: CGSize) -> Projection {
        let zoom = min(MapCamera.maxZoom, max(MapCamera.minZoom, model.camera.zoom * pinch))
        let center = MapPoint(x: model.camera.center.x - dragTranslation.width / zoom,
                              y: model.camera.center.y - dragTranslation.height / zoom)
        let visibleHeight = viewport.height - bottomInset - topInset
        return Projection(zoom: zoom, center: center,
                          viewportCenter: CGPoint(x: viewport.width / 2, y: topInset + visibleHeight / 2))
    }

    // MARK: Gestures

    private func panGesture(zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                dragTranslation = value.translation
                if model.isFollowing { model.isFollowing = false }
            }
            .onEnded { value in
                model.camera.center = MapPoint(x: model.camera.center.x - value.translation.width / zoom,
                                               y: model.camera.center.y - value.translation.height / zoom)
                dragTranslation = .zero
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinch = value.magnification
                model.showScaleBar = true
            }
            .onEnded { value in
                model.camera.zoom = min(MapCamera.maxZoom, max(MapCamera.minZoom, model.camera.zoom * value.magnification))
                pinch = 1
                model.flashScaleBar()
            }
    }

    // MARK: Map-space layer

    private var highlightedIds: Set<String> {
        var ids = model.boothIds(in: model.category)
        switch model.panel {
        case .booth(let b, _), .arrived(let b), .nextStop(let b): ids.insert(b.id)
        case .filterResults(let results): ids.formUnion(results.map(\.booth.id))
        case .alternatives(_, let alts): ids.formUnion(alts.map(\.booth.id))
        case .replaceReview(_, let to): ids.insert(to.id)
        case .routeOptions(.booth(let b), _, _): ids.insert(b.id)
        default: break
        }
        if let nav = model.navigation, case .booth(let b) = nav.target { ids.insert(b.id) }
        return ids
    }

    private var primaryRoute: [MapPoint]? {
        if let nav = model.navigation { return nav.route.path }
        switch model.panel {
        case .routeOptions(_, let routes, let selected):
            return routes.first { $0.kind == selected }?.path
        case .nextStop:
            return model.previewRoutes.first?.path
        case .meetingReview:
            return model.meetingPreviewRoute?.path
        default:
            return nil
        }
    }

    private var secondaryRoute: [MapPoint]? {
        if case .routeOptions(_, let routes, let selected) = model.panel, routes.count > 1 {
            return routes.first { $0.kind != selected }?.path
        }
        return nil
    }

    /// Friend's walking line to the meeting point (6.2 «طريق ذكرى»).
    private var friendRoute: [MapPoint]? {
        guard case .meetingReview(let point) = model.panel,
              let from = model.meetingFriend?.location?.point else { return nil }
        return [from, MapPoint(x: from.x, y: point.point.y + 24), point.point]
    }

    private var mapLayer: some View {
        ZStack(alignment: .topLeading) {
            Image("map-exhibition-base")
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .accessibilityHidden(true)

            ForEach(model.hotspots) { spot in
                Image(spot.level == .high ? "map-heat-busy" : "map-heat-medium")
                    .resizable()
                    .frame(width: spot.frame.width, height: spot.frame.height)
                    .offset(x: spot.frame.x, y: spot.frame.y)
                    .accessibilityHidden(true)
            }

            let highlighted = highlightedIds
            ForEach(model.booths.filter { highlighted.contains($0.id) }) { booth in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brandPrimary.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.brandPrimary, lineWidth: 3))
                    .shadow(color: Color.brandPrimary.opacity(0.25), radius: 6)
                    .frame(width: booth.frame.width, height: booth.frame.height)
                    .offset(x: booth.frame.x, y: booth.frame.y)
            }

            if let path = secondaryRoute {
                RoutePath(points: path)
                    .stroke(Color(hex: 0x7D8A99), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round, dash: [6, 5]))
            }
            if let path = friendRoute {
                RoutePath(points: path)
                    .stroke(Color.crowdHigh, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round, dash: [6, 4]))
            }
            if let path = primaryRoute {
                RoutePath(points: path)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                RoutePath(points: path)
                    .stroke(Color.locationBlue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                RoutePath(points: path)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 7]))
            }

            ForEach(model.booths) { booth in
                BoothMapLabel(name: booth.name, isHighlighted: highlighted.contains(booth.id))
                    .offset(x: booth.labelPoint.x, y: booth.labelPoint.y)
            }

            ForEach(model.landmarks) { mark in
                Group {
                    if mark.kind == .gate { GatePill(name: mark.name) } else { SmallMapLabel(name: mark.name) }
                }
                .offset(x: mark.point.x, y: mark.point.y)
            }

            ForEach(model.hotspots) { spot in
                CrowdBadge(level: spot.level, style: .mapCompact)
                    .environment(\.layoutDirection, .rightToLeft)
                    .offset(x: spot.badgePoint.x, y: spot.badgePoint.y)
            }
        }
    }

    // MARK: Screen-space markers

    @ViewBuilder
    private func markerLayer(_ projection: Projection) -> some View {
        // Numbered alternatives (3.2).
        if case .alternatives(_, let alts) = model.panel {
            ForEach(alts) { alt in
                NumberBadge(number: alt.rank)
                    .position(projection.screen(MapPoint(x: alt.booth.frame.x + alt.booth.frame.width, y: alt.booth.frame.y)))
            }
        }

        // Destination pin.
        if let pin = destinationPin {
            MapPin(icon: pin.icon, label: pin.label)
                .position(projection.screen(pin.point))
                .offset(y: pin.label == nil ? -24 : -12)
        }

        // Friends (5.6).
        ForEach(model.visibleFriends) { friend in
            if let loc = friend.location {
                Button {
                    model.panel = .friendCard(friend)
                } label: {
                    FriendMapPin(friend: friend)
                }
                .buttonStyle(.plain)
                .position(projection.screen(loc.point))
                .accessibilityLabel("\(friend.name)، \(loc.areaText)")
            }
        }

        // Me.
        if let me = mePoint {
            MeMarker(lowAccuracy: model.location?.accuracy == .low || model.permissions.isApproximate,
                     radius: 15 / MapCamera.metersPerPoint * projection.zoom)
                .position(projection.screen(me))
                .allowsHitTesting(false)
                .accessibilityLabel("موقعك")
        }
    }

    private var mePoint: MapPoint? {
        if let step = model.navigation?.step { return step.position }
        return model.location?.point
    }

    private struct PinInfo { var point: MapPoint; var icon: AppIcon; var label: String? }

    private var destinationPin: PinInfo? {
        func entrance(_ b: Booth) -> MapPoint { MapPoint(x: b.frame.x + b.frame.width, y: b.frame.center.y) }
        if let nav = model.navigation {
            switch nav.target {
            case .booth(let b): return PinInfo(point: entrance(b), icon: .door)
            case .meetingPoint(let m): return PinInfo(point: m.point, icon: .users, label: m.name.components(separatedBy: " – ").first)
            case .friend: return nil
            }
        }
        switch model.panel {
        case .routeOptions(.booth(let b), _, _), .nextStop(let b), .replaceReview(_, let b):
            return PinInfo(point: entrance(b), icon: .door)
        case .arrived(let b):
            return PinInfo(point: entrance(b), icon: .flag)
        case .meetingReview(let m), .meetingArrived(let m):
            return PinInfo(point: m.point, icon: .users, label: m.name.components(separatedBy: " – ").first)
        case .meetingStatus:
            if let m = model.agreedPoint ?? model.proposedPoint {
                return PinInfo(point: m.point, icon: .users, label: m.name.components(separatedBy: " – ").first)
            }
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Map pieces

struct RoutePath: Shape {
    let points: [MapPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: CGPoint(x: first.x, y: first.y))
        for pt in points.dropFirst() { p.addLine(to: CGPoint(x: pt.x, y: pt.y)) }
        return p
    }
}

/// White booth label (Figma: white 96%, r12, IBM Plex Arabic SemiBold 10.54). Highlighted booths use brand.
struct BoothMapLabel: View {
    let name: String
    var isHighlighted = false
    var body: some View {
        Text(name)
            .font(AppFont.arabic(10.54, .semibold))
            .foregroundStyle(isHighlighted ? Color.white : Color(hex: 0x16211C))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6.82)
            .padding(.vertical, 1.86)
            .background(isHighlighted ? Color.brandPrimary : Color.white.opacity(0.96),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Color(red: 0, green: 26 / 255, blue: 13 / 255).opacity(0.14), radius: 1.5, y: 1.24)
            .accessibilityHidden(true)
    }
}

/// Green gate pill with a door glyph («البوابة ٨»).
struct GatePill: View {
    let name: String
    var body: some View {
        HStack(spacing: 3) {
            Text(name).font(AppFont.arabic(8.68, .semibold))
            Icon(.door, size: 9, color: .white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.brandPrimary, in: Capsule())
        .environment(\.layoutDirection, .rightToLeft)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct SmallMapLabel: View {
    let name: String
    var body: some View {
        Text(name)
            .font(AppFont.arabic(8.68, .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.9), in: Capsule())
            .fixedSize()
            .accessibilityHidden(true)
    }
}

struct NumberBadge: View {
    let number: Int
    var body: some View {
        Text(ArabicDigits.format(number))
            .font(AppFont.arabic(12, .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Color.brandPrimary, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .shadowTint.opacity(0.2), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

/// Brand teardrop pin (destination door, meeting point) with an optional label under it.
struct MapPin: View {
    let icon: AppIcon
    var label: String? = nil
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                PinShape().fill(Color.brandPrimary)
                PinShape().stroke(.white, lineWidth: 2)
                Icon(icon, size: 18, color: .white).offset(y: -4)
            }
            .frame(width: 38, height: 48)
            .shadow(color: .shadowTint.opacity(0.25), radius: 4, y: 2)
            if let label {
                Text(label)
                    .font(AppFont.arabic(11, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.brandPrimary, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: r), radius: r, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Visitor position: Figma «Me» marker (blue dot + heading cone). Low accuracy shows a wide halo without heading.
struct MeMarker: View {
    var lowAccuracy = false
    var radius: CGFloat = 30
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if lowAccuracy {
                Circle().fill(Color.locationBlue.opacity(0.14))
                    .overlay(Circle().strokeBorder(Color.locationBlue.opacity(0.35), lineWidth: 1))
                    .frame(width: radius * 2, height: radius * 2)
                Circle().fill(Color.locationBlue.opacity(0.6))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .frame(width: 18, height: 18)
            } else {
                Circle().fill(Color.locationBlue.opacity(0.18))
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulse ? 1.1 : 0.85)
                    .opacity(pulse ? 0.4 : 0.8)
                Image("map-me-marker").resizable().frame(width: 96, height: 96)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Friend photo on the map (5.6): live = blue ring + dot, stale = grey ring.
struct FriendMapPin: View {
    let friend: Friend
    var body: some View {
        let stale = friend.location?.isStale ?? true
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                AvatarView(name: friend.name, image: friend.avatar, width: 44, height: 44, radius: 22)
                    .overlay(Circle().strokeBorder(stale ? Color.textTertiary : Color.locationBlue, lineWidth: 3))
                    .padding(4)
                    .background(Circle().fill(.white))
                    .saturation(stale ? 0.3 : 1)
                Circle().fill(stale ? Color.textTertiary : Color.locationBlue)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 14, height: 14)
            }
            Text(friend.name)
                .font(AppFont.arabic(10, .semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .background(Color.white.opacity(0.9), in: Capsule())
        }
        .shadow(color: .shadowTint.opacity(0.18), radius: 4, y: 2)
    }
}
