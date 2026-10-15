import SwiftUI

struct SaudiIndoorMapView: View {
    @ObservedObject var store: ExpoStore
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero

    private var floor: Int { store.floor }
    private func matrix(_ size: CGSize) -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(size.width / 780,size.height / 575) * zoom
        return (scale,CGPoint(x:size.width/2 - 380*scale+pan.width,
                              y:size.height/2 - 290*scale+pan.height))
    }
    var body: some View {
        GeometryReader { geo in
            Canvas(opaque: false, colorMode: .nonLinear) { context, size in
                let t = matrix(size)
                context.translateBy(x:t.origin.x,y:t.origin.y)
                context.scaleBy(x:t.scale,y:t.scale)
                render(context:&context)
            }
            .background(Color(red:0.86,green:0.90,blue:0.85))
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance:5)
                .onChanged { value in
                    pan = CGSize(width:committedPan.width+value.translation.width,
                                 height:committedPan.height+value.translation.height)
                }
                .onEnded { _ in committedPan=pan })
            .simultaneousGesture(MagnificationGesture()
                .onChanged { value in zoom=max(0.7,min(3.3,committedZoom*value)) }
                .onEnded { _ in committedZoom=zoom })
            .simultaneousGesture(SpatialTapGesture().onEnded { gesture in
                if store.navigating { return }
                let t=matrix(geo.size)
                let p=ExpoNavPoint(Double((gesture.location.x-t.origin.x)/t.scale),
                               Double((gesture.location.y-t.origin.y)/t.scale))
                if store.placementMode { store.placeAt(p);return }
                if let item=store.dataset.indoor.spaces.filter({$0.floor==floor})
                    .min(by:{$0.center.distance(to:p)<$1.center.distance(to:p)}),
                   item.center.distance(to:p)<95 { store.selectSpace(item.id) }
            })
            .onChange(of: store.position) { _, position in
                guard store.navigating, position.zone == .indoor else { return }
                let scale = min(geo.size.width / 780, geo.size.height / 575) * zoom
                pan = CGSize(width: CGFloat(380 - position.point.x) * scale,
                             height: CGFloat(290 - position.point.y) * scale)
                committedPan = pan
            }
            .onChange(of: store.navigating) { _, active in
                if active {
                    zoom = 1.55
                    committedZoom = zoom
                } else {
                    // Keep the last map position after cancelling walking.
                    committedPan = pan
                }
            }
            .overlay(alignment: .topLeading) {
                if !store.navigating {
                    VStack(alignment: .leading, spacing: 5) {
                        Button {
                            Task { await store.toggleHackathonCrowdPreview() }
                        } label: {
                            HStack(spacing: 6) {
                                if store.demoLoading { ProgressView() }
                                Image(systemName: "chart.bar.xaxis")
                                Text(store.demoEnabled ? "العودة للوقت الحالي" : "تجربة الزحمة · 6 م")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.regularMaterial, in: Capsule())
                        }
                        .disabled(store.demoLoading)
                        if store.demoEnabled && store.crowdReady {
                            Text("توقع محاكاة · الأحد 6 مساءً")
                                .font(.system(size: 10))
                                .padding(6)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .foregroundStyle(.primary)
                    .padding(12)
                }
            }
            .overlay(alignment:.bottomTrailing) {
                if !store.navigating {
                  VStack(spacing:9) {
                    Button { zoom=min(3.3,zoom*1.3);committedZoom=zoom } label: {
                        Image(systemName:"plus.magnifyingglass")
                    }
                    Button { zoom=max(0.7,zoom/1.3);committedZoom=zoom } label: {
                        Image(systemName:"minus.magnifyingglass")
                    }
                    Button { zoom=1; committedZoom=1; pan = .zero; committedPan = .zero } label: {
                        Image(systemName:"scope")
                    }
                }
                .font(.system(size:16,weight:.bold))
                .foregroundStyle(.white)
                .padding(12)
                .background(.thinMaterial,in:RoundedRectangle(cornerRadius:18))
                  .padding(15)
                }
            }
        }
    }
    // Native architectural drawing: every original room boundary and entrance
    // is preserved. Furniture and textures are illustrative (not navigable walls).
    private let wall = Color(red: 0.46, green: 0.52, blue: 0.48)
    private let textInk = Color(red: 0.15, green: 0.29, blue: 0.28)
    private let stone = Color(red: 0.97, green: 0.95, blue: 0.90)

    private func rectangle(_ c: inout GraphicsContext, _ rect: CGRect,
                           radius: CGFloat, fill: Color, stroke: Color, line: CGFloat = 2) {
        let p = Path(roundedRect: rect, cornerRadius: radius)
        c.fill(p, with: .color(fill))
        c.stroke(p, with: .color(stroke), lineWidth: line)
    }
    private func line(_ c: inout GraphicsContext, _ a: CGPoint, _ b: CGPoint,
                      color: Color, width: CGFloat = 2, dash: [CGFloat] = []) {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        c.stroke(p, with: .color(color),
                 style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
    }
    private func circle(_ c: inout GraphicsContext, x: CGFloat, y: CGFloat,
                        r: CGFloat, fill: Color, stroke: Color, line: CGFloat = 1.5) {
        let p = Path(ellipseIn: CGRect(x: x-r, y: y-r, width: 2*r, height: 2*r))
        c.fill(p, with: .color(fill))
        c.stroke(p, with: .color(stroke), lineWidth: line)
    }
    private func label(_ c: inout GraphicsContext, _ value: String, x: CGFloat, y: CGFloat,
                       size: CGFloat = 14, color: Color? = nil, bold: Bool = true) {
        c.draw(Text(value).font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundColor(color ?? textInk), at: CGPoint(x: x, y: y))
    }
    private func roomRect(_ id: String) -> CGRect {
        guard let r = IndoorGeometry.rooms[id] else { return .zero }
        return CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }
    private func room(_ c: inout GraphicsContext, id: String, color: Color,
                      name: String, subtitle: String? = nil) {
        guard let geometry = IndoorGeometry.rooms[id],
              let space = store.dataset.indoor.spaces.first(where: { $0.id == id }) else { return }
        let rect = CGRect(x: geometry.x, y: geometry.y, width: geometry.width, height: geometry.height)
        let selected = store.selectedSpaceID == id
        let highlight = Color(red: 0.06, green: 0.57, blue: 0.79)
        // Soft ambient shadow + double-line architectural room walls.
        rectangle(&c, rect.offsetBy(dx: 3, dy: 4), radius: 10,
                  fill: Color.black.opacity(0.07), stroke: Color.clear, line: 0)
        rectangle(&c, rect, radius: 8, fill: color,
                  stroke: selected ? highlight : Color(red: 0.51, green: 0.55, blue: 0.51), line: selected ? 5 : 4)
        c.stroke(Path(roundedRect: rect.insetBy(dx: 7, dy: 7), cornerRadius: 5),
                 with: .color(.white.opacity(0.77)), lineWidth: 1.7)
        // The threshold lies on the dataset's real booth-door position.
        circle(&c, x: space.entrance.x, y: space.entrance.y, r: 7.5,
               fill: .white, stroke: selected ? highlight : Color(red: 0.34, green: 0.65, blue: 0.56), line: 3)
        label(&c, name, x: rect.midX, y: rect.midY + 14, size: 13)
        if let subtitle {
            label(&c, subtitle, x: rect.midX, y: rect.midY + 30,
                  size: 10, color: Color(red: 0.37, green: 0.48, blue: 0.45), bold: false)
        }
        // Furniture/exhibit geometry is inside the actual rooms; no new routing obstacles.
        switch id {
        case "B013", "B015":
            for i in 0..<3 {
                let xx = rect.minX + 26 + CGFloat(i)*38
                rectangle(&c, CGRect(x: xx-10, y: rect.minY+17, width: 21, height: 15),
                          radius: 2, fill: .white.opacity(0.88), stroke: wall.opacity(0.55), line: 1)
                line(&c, CGPoint(x: xx, y: rect.minY+32), CGPoint(x: xx, y: rect.minY+43),
                     color: wall.opacity(0.65), width: 1)
            }
        case "B014", "B016":
            for i in 0..<3 {
                circle(&c, x: rect.minX+29+CGFloat(i)*39, y: rect.minY+28,
                       r: 11, fill: .white.opacity(0.75), stroke: wall.opacity(0.55))
                circle(&c, x: rect.minX+29+CGFloat(i)*39, y: rect.minY+28,
                       r: 4, fill: Color(red: 0.69, green: 0.84, blue: 0.78), stroke: .clear)
            }
        case "stage":
            rectangle(&c, CGRect(x: rect.minX+15, y: rect.minY+12, width: rect.width-30, height: 22),
                      radius: 5, fill: Color(red: 0.58, green: 0.43, blue: 0.29),
                      stroke: Color(red: 0.39, green: 0.34, blue: 0.28), line: 2)
            for col in 0..<5 {
                circle(&c, x: rect.minX+25+CGFloat(col)*19, y: rect.minY+48,
                       r: 4, fill: .white.opacity(0.9), stroke: wall.opacity(0.55), line: 1)
            }
        case "cafe":
            for col in 0..<3 {
                circle(&c, x: rect.minX+25+CGFloat(col)*36, y: rect.minY+20,
                       r: 10, fill: Color(red: 0.97, green: 0.95, blue: 0.86), stroke: wall.opacity(0.7))
            }
        case "wc":
            for col in 0..<3 {
                let xx = rect.minX+7+CGFloat(col)*17
                rectangle(&c, CGRect(x: xx, y: rect.minY+7, width: 14, height: 19),
                          radius: 1, fill: .white.opacity(0.65), stroke: wall.opacity(0.6), line: 1)
            }
        case "prayer":
            for col in 0..<5 {
                line(&c, CGPoint(x: rect.minX+12+CGFloat(col)*21, y: rect.minY+14),
                     CGPoint(x: rect.minX+12+CGFloat(col)*21, y: rect.minY+31),
                     color: Color(red: 0.48, green: 0.64, blue: 0.54), width: 2)
            }
        case "lift1", "lift2":
            let a = rect.midX
            line(&c, CGPoint(x: a, y: rect.minY+8), CGPoint(x: a, y: rect.minY+28),
                 color: Color(red: 0.31, green: 0.42, blue: 0.45), width: 3)
        default: break
        }
    }
    private func drawRoute(_ c: inout GraphicsContext, _ plan: RoutePlan,
                           color: Color, selected: Bool) {
        for part in plan.segments where !part.isVertical &&
            part.from.floor == floor && part.to.floor == floor {
            let a = CGPoint(x: part.from.point.x, y: part.from.point.y)
            let b = CGPoint(x: part.to.point.x, y: part.to.point.y)
            // The stronger route is chosen for walking. Both share exact graph geometry.
            line(&c, a, b, color: .white.opacity(0.94), width: selected ? 16 : 12)
            line(&c, a, b, color: color.opacity(selected ? 1 : 0.82),
                 width: selected ? 8 : 6, dash: selected ? [] : [12, 5])
        }
    }

    private func render(context c: inout GraphicsContext) {
        // A terraced outline, slab shadows, paving joints, planted beds, and the
        // real graph-built corridors replace the prototype's flat block diagram.
        rectangle(&c, CGRect(x: 27, y: 35, width: 706, height: 481), radius: 43,
                  fill: Color.black.opacity(0.09), stroke: .clear, line: 0)
        rectangle(&c, CGRect(x: 30, y: 29, width: 700, height: 480), radius: 45,
                  fill: Color(red: 0.95, green: 0.94, blue: 0.90),
                  stroke: Color(red: 0.43, green: 0.53, blue: 0.47), line: 7)
        c.stroke(Path(roundedRect: CGRect(x: 41, y: 40, width: 678, height: 457), cornerRadius: 36),
                 with: .color(.white), lineWidth: 4)
        // Restrained stone joint pattern (architectural planning texture).
        for x in stride(from: 65, through: 698, by: 24) {
            line(&c, CGPoint(x: CGFloat(x), y: 64), CGPoint(x: CGFloat(x), y: 485),
                 color: Color(red: 0.81, green: 0.82, blue: 0.77).opacity(0.35), width: 0.7)
        }
        for y in stride(from: 80, through: 483, by: 24) {
            line(&c, CGPoint(x: 58, y: CGFloat(y)), CGPoint(x: 704, y: CGFloat(y)),
                 color: Color(red: 0.81, green: 0.82, blue: 0.77).opacity(0.35), width: 0.7)
        }
        // The highlighted walkable floor follows EXACTLY the navigation graph.
        for edge in store.indoor.edges where !edge.isVertical {
            guard let a = store.indoor.nodes[edge.from]?.position,
                  let b = store.indoor.nodes[edge.to]?.position,
                  a.floor == floor && b.floor == floor else { continue }
            var segment = Path()
            segment.move(to: CGPoint(x: a.point.x, y: a.point.y))
            segment.addLine(to: CGPoint(x: b.point.x, y: b.point.y))
            c.stroke(segment, with: .color(Color(red: 0.67, green: 0.76, blue: 0.72)),
                     style: StrokeStyle(lineWidth: 34, lineCap: .round, lineJoin: .round))
            c.stroke(segment, with: .color(Color(red: 0.98, green: 0.98, blue: 0.94)),
                     style: StrokeStyle(lineWidth: 27, lineCap: .round, lineJoin: .round))
        }
        // Central illuminated atrium — a ground-floor gathering space and
        // an upper-floor overlooking gallery. Its center is deliberately open.
        rectangle(&c, CGRect(x: 314, y: 208, width: 131, height: 108), radius: 33,
                  fill: floor == 1 ? Color(red: 0.86, green: 0.92, blue: 0.85) : Color(red: 0.88, green: 0.94, blue: 0.93),
                  stroke: Color(red: 0.58, green: 0.72, blue: 0.67), line: 2)
        for index in 0..<4 {
            let xx = 335 + CGFloat(index)*29
            line(&c, CGPoint(x: xx, y: 227), CGPoint(x: xx, y: 297),
                 color: Color(red: 0.58, green: 0.70, blue: 0.64).opacity(0.56), width: 1.4)
        }
        label(&c, floor == 1 ? "الردهة المركزية" : "بهو الإطلالة", x: 380, y: 255, size: 12)
        label(&c, floor == 1 ? "استقبال ومعارض" : "إطلالة على الدور الأول", x: 380, y: 274,
              size: 9, color: Color(red: 0.45, green: 0.54, blue: 0.49), bold: false)
        // Structural columns and planters around the atrium, outside its path.
        for (x, y) in [(300,190), (461,190), (300,323), (462,323)] {
            circle(&c, x: CGFloat(x), y: CGFloat(y), r: 7,
                   fill: Color(red: 0.59, green: 0.73, blue: 0.62),
                   stroke: Color(red: 0.36, green: 0.53, blue: 0.43), line: 1)
        }
        // Reuse the exact room rectangles + booth doors from Geometry and JSON.
        if floor == 1 {
            room(&c, id: "stage", color: Color(red: 0.86, green: 0.77, blue: 0.64), name: "المنصة")
            room(&c, id: "B013", color: Color(red: 0.92, green: 0.85, blue: 0.72), name: "التراث السعودي", subtitle: "B013 · عرض تراثي")
            room(&c, id: "B014", color: Color(red: 0.79, green: 0.90, blue: 0.85), name: "بيت الفنون", subtitle: "B014 · معرض تفاعلي")
            room(&c, id: "cafe", color: Color(red: 0.92, green: 0.85, blue: 0.73), name: "مقهى")
            room(&c, id: "wc", color: Color(red: 0.83, green: 0.87, blue: 0.88), name: "خدمات")
            room(&c, id: "exit", color: Color(red: 0.87, green: 0.86, blue: 0.78), name: "خروج")
        } else {
            room(&c, id: "B015", color: Color(red: 0.92, green: 0.84, blue: 0.72), name: "سوق الحرف", subtitle: "B015 · تجربة حرفية")
            room(&c, id: "B016", color: Color(red: 0.79, green: 0.90, blue: 0.86), name: "المتحف المستقبلي", subtitle: "B016 · معرض رقمي")
            room(&c, id: "prayer", color: Color(red: 0.90, green: 0.88, blue: 0.78), name: "المصلى")
            // Exhibition lounge: an open furniture grouping, not a room/wall.
            rectangle(&c, CGRect(x: 201, y: 122, width: 358, height: 86), radius: 30,
                      fill: Color(red: 0.90, green: 0.94, blue: 0.88).opacity(0.68),
                      stroke: Color(red: 0.64, green: 0.77, blue: 0.69), line: 2)
            label(&c, "معرض الدور الثاني", x: 380, y: 163, size: 14)
            label(&c, "منطقة مشاهدة مفتوحة", x: 380, y: 185, size: 10,
                  color: Color(red: 0.41, green: 0.53, blue: 0.47), bold: false)
        }
        room(&c, id: "lift\(floor)", color: Color(red: 0.74, green: 0.83, blue: 0.85), name: "مصعد")

        // Front glass entrance, with two symmetrical door leaves.
        if floor == 1 {
            rectangle(&c, CGRect(x: 345, y: 492, width: 70, height: 13), radius: 3,
                      fill: Color(red: 0.71, green: 0.88, blue: 0.85),
                      stroke: Color(red: 0.31, green: 0.56, blue: 0.53), line: 2)
            line(&c, CGPoint(x: 380, y: 492), CGPoint(x: 380, y: 505),
                 color: Color(red: 0.27, green: 0.52, blue: 0.5), width: 2)
            label(&c, "المدخل الرئيسي", x: 380, y: 532, size: 13)
        }
        label(&c, "EXPO 2030 · SAUDI PAVILION", x: 380, y: 63,
              size: 14, color: Color(red: 0.30, green: 0.44, blue: 0.39))
        label(&c, floor == 1 ? "01 / الدور الأول" : "02 / الدور الثاني",
              x: 93, y: 72, size: 12, color: Color(red: 0.42, green: 0.57, blue: 0.50))

        // Crowd heatmap: real Random Forest OUTPUT on each drawn corridor.
        // The predictions are based on generated training data plus the
        // simulated event schedule, never on live people counters.
        if store.crowdReady {
            for edge in store.indoor.edges where !edge.isVertical {
                guard let a = store.indoor.nodes[edge.from]?.position,
                      let b = store.indoor.nodes[edge.to]?.position,
                      a.floor == floor, b.floor == floor,
                      let factor = store.crowdFactor(for: edge) else { continue }
                let color: Color = factor >= 1.55 ? .red : (factor >= 1.12 ? .orange : .green)
                line(&c, CGPoint(x:a.point.x,y:a.point.y),
                     CGPoint(x:b.point.x,y:b.point.y),
                     color:color.opacity(store.routeVisible ? 0.45 : 0.72),width:store.routeVisible ? 6 : 5)
            }
        }
        // Both lines correspond to real graph routes, evaluated at the SAME hour:
        // red = geometrically shortest, blue = least predicted walking time.
        // When they overlap, show only blue rather than inventing a red detour.
        if store.routeVisible {
            let red = Color(red: 0.86, green: 0.19, blue: 0.19)
            let blue = Color(red: 0.04, green: 0.49, blue: 0.93)
            // Selected route is drawn last and receives the stronger stroke.
            if store.routePreference == .shortest {
                if let fast = store.fastestRoute {
                    drawRoute(&c, fast, color: blue, selected: false)
                }
                if store.distinctRouteOptions, let shortest = store.shortestRoute {
                    drawRoute(&c, shortest, color: red, selected: true)
                }
            } else {
                if store.distinctRouteOptions, let shortest = store.shortestRoute {
                    drawRoute(&c, shortest, color: red, selected: false)
                }
                if let fast = store.fastestRoute ?? store.route {
                    drawRoute(&c, fast, color: blue, selected: true)
                }
            }
        }
        if let space = store.selectedSpace, space.floor == floor {
            circle(&c, x: space.entrance.x, y: space.entrance.y, r: 12,
                   fill: Color(red: 0.08, green: 0.56, blue: 0.84), stroke: .white, line: 4)
        }
        if store.position.floor == floor {
            let p = store.position.point
            circle(&c, x: p.x, y: p.y, r: 18,
                   fill: Color.blue.opacity(0.17), stroke: .clear)
            circle(&c, x: p.x, y: p.y, r: 9,
                   fill: Color(red: 0.04, green: 0.49, blue: 0.92), stroke: .white, line: 4)
            if !store.navigating {
                label(&c, "موقعك", x: p.x+40, y: p.y-6, size: 13, color: .blue)
            }
        }
        if let plan = store.route, plan.levels.count > 1 {
            label(&c, "الطريق يمر بالمصعد · تبديل الأدوار تلقائيًا",
                  x: 380, y: 558, size: 12, color: .blue)
        }
    }
}
