import SwiftUI

/// Pin on the illustrative site map (Figma «Map/Pavilion Pin» 1:3965): rounded square, distinct from round
/// friend pins. Crowd is shown as border colour + symbol, never colour alone.
struct SitePin: Identifiable, Hashable {
    enum PinState: Hashable { case normal, selected, crowded }
    var id: String
    var name: String
    var point: MapPoint
    var state: PinState = .normal
}

struct SiteRoute: Identifiable, Hashable {
    var id: String
    var points: [MapPoint]
    var isFaded = false
}

/// Viewport onto «Map/Base» (640 × 1000 illustrative site map — not an official plan). The base artwork
/// is the local asset `map-site-base`; pins, routes and the user dot are SwiftUI overlays in map coordinates.
struct SiteMapView: View {
    var center: MapPoint
    var pins: [SitePin] = []
    var routes: [SiteRoute] = []
    var user: MapPoint? = nil
    var scale: CGFloat = 1
    var onPinTap: ((SitePin) -> Void)? = nil

    @State private var drag: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero

    static let size = CGSize(width: 640, height: 1000)

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width / 2 - center.x * scale + drag.width + liveDrag.width,
                                 y: geo.size.height / 2 - center.y * scale + drag.height + liveDrag.height)
            ZStack(alignment: .topLeading) {
                Color(hex: 0xEDEBE3)
                Image("map-site-base")
                    .resizable()
                    .frame(width: Self.size.width * scale, height: Self.size.height * scale)
                    .offset(x: origin.x, y: origin.y)
                    .accessibilityHidden(true)

                ForEach(routes) { route in
                    Path { path in
                        guard let first = route.points.first else { return }
                        path.move(to: CGPoint(x: origin.x + first.x * scale, y: origin.y + first.y * scale))
                        for p in route.points.dropFirst() {
                            path.addLine(to: CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale))
                        }
                    }
                    .stroke(route.isFaded ? Color.textTertiary.opacity(0.5) : Color.brandPrimary,
                            style: StrokeStyle(lineWidth: route.isFaded ? 3 : 5, lineCap: .round, lineJoin: .round,
                                               dash: route.isFaded ? [6, 6] : []))
                    .accessibilityHidden(true)
                }

                ForEach(pins) { pin in
                    PavilionPinView(pin: pin)
                        .position(x: origin.x + pin.point.x * scale, y: origin.y + pin.point.y * scale + 10)
                        .onTapGesture { onPinTap?(pin) }
                }

                if let user {
                    UserLocationDot()
                        .position(x: origin.x + user.x * scale, y: origin.y + user.y * scale)
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        drag.width += value.translation.width
                        drag.height += value.translation.height
                    }
            )
        }
        // Map coordinates are absolute; keep the canvas left-to-right regardless of the RTL UI.
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("خريطة توضيحية للمعرض")
    }
}

struct PavilionPinView: View {
    let pin: SitePin

    var body: some View {
        VStack(spacing: 2) {
            switch pin.state {
            case .selected:
                Icon(.door, size: 24, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .cardShadow()
            case .crowded:
                Icon(.door, size: 19, color: .crowdHigh)
                    .frame(width: 34, height: 34)
                    .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.crowdHigh, lineWidth: 2))
                    .cardShadow()
            case .normal:
                Icon(.door, size: 16, color: .brandPrimary)
                    .frame(width: 28, height: 28)
                    .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 1.5))
            }
            HStack(spacing: 3) {
                Text(pin.name).font(AppFont.arabic(11, .medium)).foregroundStyle(Color.textPrimary)
                if pin.state == .crowded {
                    Text("■").font(AppFont.latin(11, .medium)).foregroundStyle(Color.crowdHigh)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.bgSurfaceTranslucent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pin.state == .crowded ? "\(pin.name)، مزدحم" : pin.name)
        .accessibilityAddTraits(.isButton)
    }
}

/// Figma «Map/User Location» (precise): blue dot with white ring and soft accuracy halo.
struct UserLocationDot: View {
    var approximate = false
    var body: some View {
        ZStack {
            if approximate {
                Circle().fill(Color.locationBlue.opacity(0.10)).frame(width: 120, height: 120)
                Circle().strokeBorder(Color.locationBlue.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .frame(width: 120, height: 120)
            } else {
                Circle().fill(Color.locationBlue.opacity(0.16)).frame(width: 60, height: 60)
                Circle().fill(Color.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                Circle().fill(Color.locationBlue).frame(width: 16, height: 16)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(approximate ? "موقعك التقريبي" : "موقعك")
    }
}
