import SwiftUI
import Combine

private enum ExpoStyle {
    static let green = Color(red: 0.08, green: 0.29, blue: 0.26)
    static let mint = Color(red: 0.12, green: 0.48, blue: 0.39)
    static let gold = Color(red: 0.73, green: 0.53, blue: 0.29)
    static let ocean = Color(red: 0.04, green: 0.48, blue: 0.80)
    static let ivory = Color(red: 0.97, green: 0.96, blue: 0.92)
}

private func walkDuration(_ seconds: Double) -> String {
    seconds < 60 ? "\(Int(ceil(seconds))) ثانية" : "\(Int(ceil(seconds / 60))) دقيقة"
}

struct ExpoHomeView: View {
    @StateObject private var store: ExpoStore
    @State private var explorerPresented = false
    @State private var explorerTab = "pavilions"
    private let timer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    init(store: ExpoStore) { _store = StateObject(wrappedValue: store) }

    var body: some View {
        ZStack {
            if store.mode == .outdoor {
                Outdoor3DMapView(store: store).ignoresSafeArea()
            } else {
                SaudiIndoorMapView(store: store).ignoresSafeArea()
            }
            LinearGradient(colors: [ExpoStyle.green.opacity(0.25), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 9) {
                if store.navigating && store.mode == .indoor {
                    walkingHeader
                } else {
                    header
                    controls
                    if store.mode == .indoor {
                        floorControl
                    }
                }
                if let toast = store.toast, !store.navigating {
                    HStack(spacing: 7) {
                        Image(systemName: "info.circle.fill")
                        Text(toast).font(.system(size: 11)).lineLimit(2)
                        Spacer(minLength: 2)
                        Button { store.toast = nil } label: { Image(systemName: "xmark.circle.fill") }
                    }
                    .padding(11)
                    .foregroundStyle(ExpoStyle.green)
                    .background(ExpoStyle.ivory, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 14)
                }
                Spacer(minLength: 0)
                if store.navigating && store.mode == .indoor {
                    compactWalkingBar
                } else {
                    bottomPanel
                }
            }
            // Keep the first project's original floating tab bar usable, without
            // covering this imported map's bottom route actions.
            .padding(.bottom, 82)
        }
        .onReceive(timer) { store.tick(date: $0) }
        .task { await store.refreshFromBackend() }
        .sheet(isPresented: $explorerPresented) {
            ExpoExplorer(store: store, startTab: explorerTab)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").foregroundStyle(ExpoStyle.gold)
                    Text("EXPO 2030 RIYADH")
                        .font(.system(size: 10, weight: .black, design: .rounded)).tracking(1)
                }
                Text(store.mode == .outdoor ? "استكشف أجنحة إكسبو" : "جناح السعودية")
                    .font(.system(size: 18, weight: .bold))
            }
            Spacer(minLength: 2)
            Button {
                Task { await store.refreshFromBackend() }
            } label: {
                Image(systemName: store.backendLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 15, weight: .bold))
                    .padding(10)
                    .background(.white.opacity(0.17), in: Circle())
            }
            .disabled(store.backendLoading)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(ExpoStyle.green.opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 14)
        .padding(.top, 7)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if store.mode == .outdoor {
                outdoorGateChip
                Button { openExplorer("pavilions") } label: { chip("الأجنحة", icon: "building.2") }
                Button { openExplorer("events") } label: { chip("الفعاليات", icon: "calendar") }
                Spacer(minLength: 0)
                Button { store.cameraRevision += 1 } label: {
                    Image(systemName: "scope").font(.system(size: 18, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                crowdStatusChip
                Button { openExplorer("events") } label: { chip("الفعاليات", icon: "calendar") }
                Button { store.exitSaudi() } label: { chip("الخارجية", icon: "arrow.uturn.backward") }
            }
        }
        .foregroundStyle(ExpoStyle.green)
        .padding(.horizontal, 14)
    }
    private var crowdStatusChip: some View {
        let level = store.selectedRouteCrowd?.level ?? store.crowdForecast?.peakLevel ?? 0
        let textLabel = store.selectedRouteCrowd != nil ? "زحمة " + routeCrowdLabel(level) : (store.crowdForecast?.status ?? "توقع الزحمة")
        return HStack(spacing: 6) {
            Circle().fill(routeCrowdColor(level)).frame(width: 9, height: 9)
            Text(store.crowdLoading || store.demoLoading ? "جاري التوقع" : textLabel)
                .lineLimit(1)
        }
        .font(.system(size: 11, weight: .bold))
        .padding(.horizontal, 10)
        .frame(height: 39)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    private var outdoorGateChip: some View {
        Menu {
            ForEach(store.dataset.gates.gates, id: \.id) { gate in
                Button {
                    store.chooseGate(gate.id)
                } label: {
                    Label(gate.name_ar, systemImage: store.selectedGateID == gate.id ? "checkmark.circle.fill" : "door.left.hand.open")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "door.left.hand.open")
                Text(store.selectedGateName)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 11, weight: .bold))
            .padding(.horizontal, 9)
            .frame(height: 39)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func openExplorer(_ tab: String) { explorerTab = tab; explorerPresented = true }
    private func chip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 11, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 39)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var floorControl: some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { level in
                Button { store.floor = level } label: {
                    Text(level == 1 ? "الدور الأول" : "الدور الثاني")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(store.floor == level ? .white : ExpoStyle.green)
                        .background(store.floor == level ? ExpoStyle.green : .white.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 11))
                }
            }
            if store.floor != store.position.floor {
                Button { store.floor = store.position.floor } label: {
                    Image(systemName: "location.fill")
                        .frame(width: 38, height: 38)
                        .background(.white, in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
        .padding(6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
    }
    // Shows the current floor's model-derived crowd forecast even when no
    // destination is selected and even if both route choices are identical.
    private var crowdIndicator: some View {
        let summary = store.crowdForecast
        let statusColor: Color = {
            switch summary?.peakLevel {
            case 2: return Color(red: 0.76, green: 0.24, blue: 0.21)
            case 1: return Color(red: 0.72, green: 0.44, blue: 0.13)
            default: return ExpoStyle.mint
            }
        }()
        return HStack(spacing: 10) {
            if store.crowdLoading || store.demoLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: store.crowdReady ? "person.3.fill" : "wifi.slash")
                    .foregroundStyle(store.crowdReady ? statusColor : .secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("الزحمة المتوقعة · الدور \(store.floor)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ExpoStyle.green)
                if let summary, !store.crowdLoading, !store.demoLoading {
                    Text(summary.status)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text("مؤشر عام للدور")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                } else {
                    Text(store.crowdLoading || store.demoLoading ? "جاري حساب الزحمة…" : "التوقع غير متاح")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !store.crowdLoading && !store.demoLoading, let reason = store.crowdFailureReason {
                        Text(reason)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 1)
            if let summary, !store.crowdLoading, !store.demoLoading {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(summary.congested) من \(summary.total) ممر")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusColor)
                    EmptyView()
                }
            } else if !store.crowdLoading && !store.demoLoading && !store.demoEnabled {
                Button {
                    Task { await store.refreshCrowdPrediction() }
                } label: { Image(systemName: "arrow.clockwise") }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ExpoStyle.mint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    // Optional gate selector is on the map itself, not a launch prerequisite.
    private var optionalOutdoorGatePicker: some View {
        HStack(spacing: 7) {
            Image(systemName: "door.left.hand.open")
                .foregroundStyle(ExpoStyle.mint)
            Text("الانطلاق من")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(store.dataset.gates.gates, id: \.id) { gate in
                    Button {
                        store.chooseGate(gate.id)
                    } label: {
                        Label(gate.name_ar, systemImage:
                              store.selectedGateID == gate.id ? "checkmark.circle.fill" : "door.left.hand.open")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(store.selectedGateName)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ExpoStyle.green)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.white, in: Capsule())
            }
            Spacer(minLength: 0)
            Text("اختياري")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.mode == .outdoor {
                if let pavilionID = store.selectedLocationID {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.selectedTitle ?? "الموقع")
                                .font(.system(size: 15, weight: .bold))
                            if let metres = store.gateDistance(to: pavilionID) {
                                Text("يبعد \(Int(metres.rounded())) م من \(store.selectedGateName)")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Button {
                            store.clearRoute()
                            store.selectedLocationID = nil
                            store.selectedEventID = nil
                            store.selectedSpaceID = nil
                        } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                    if pavilionID == "sa" {
                        Button { store.enterSaudi() } label: {
                            Label("دخول جناح السعودية", systemImage: "door.left.hand.open")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(ExpoPrimaryStyle())
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill").foregroundStyle(ExpoStyle.mint)
                        Text("اختاري بوابة من الأعلى ثم اضغطي جناحًا على الخريطة")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                }
            } else if !store.hasSelection {
                HStack(spacing: 9) {
                    Image(systemName: "map.fill").font(.system(size: 20)).foregroundStyle(ExpoStyle.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("حددي البداية والوجهة")
                            .font(.system(size: 14, weight: .bold))
                        Text("اختاري موقعك ثم اختاري فعالية")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    Button { store.placementMode.toggle() } label: {
                        Label(store.placementMode ? "المسي ممرًا" : "حدد موقعي", systemImage: "mappin.circle")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(ExpoSecondaryStyle())
                    Button { openExplorer("events") } label: {
                        Label("الفعاليات", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(ExpoPrimaryStyle())
                }
            } else if let route = store.route, store.mode == .indoor {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13)).foregroundStyle(ExpoStyle.mint)
                    Text(store.selectedTitle ?? "الوجهة")
                        .font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Button("تغيير البداية") { store.placementMode = true }
                        .font(.system(size: 10, weight: .bold))
                }
                if store.placementMode {
                    Text("المسي ممرًا لتحديد نقطة البداية")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ExpoStyle.mint)
                }
                if store.distinctRouteOptions,
                   let fastest = store.fastestRoute,
                   let shortest = store.shortestRoute {
                    HStack(spacing: 8) {
                        routeOption("الأسرع", plan: fastest, tint: ExpoStyle.ocean,
                                    isChosen: store.routePreference == .fastest) {
                            store.chooseRoute(.fastest)
                        }
                        routeOption("الأقصر", plan: shortest, tint: .red,
                                    isChosen: store.routePreference == .shortest) {
                            store.chooseRoute(.shortest)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        compactMetric("المسافة", "\(Int(route.metres.rounded())) م", icon: "figure.walk")
                        compactMetric("الوقت", walkDuration(route.seconds), icon: "clock")
                    }
                }
                routeCrowdExplanation
                Button { store.startNavigation() } label: {
                    Label(store.routePreference == .fastest ? "ابدأ المشي · الطريق الأزرق" : "ابدأ المشي · الطريق الأحمر",
                          systemImage: "figure.walk.motion")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ExpoPrimaryStyle())
                .disabled(store.crowdLoading || store.demoLoading || store.placementMode)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(ExpoStyle.ivory, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 10, y: -3)
    }
    private func routeOption(_ title: String, plan: RoutePlan, tint: Color,
                             isChosen: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text(title).font(.system(size: 11, weight: .bold))
                    Spacer(minLength: 0)
                    if isChosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(tint) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(walkDuration(plan.seconds)).font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 0)
                    Text("\(Int(plan.metres.rounded())) م")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(ExpoStyle.green)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(isChosen ? 1.0 : 0.35), lineWidth: isChosen ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func routeCrowdLabel(_ level: Int) -> String {
        switch level {
        case 2: return "عالية"
        case 1: return "متوسطة"
        default: return "خفيفة"
        }
    }
    private func routeCrowdColor(_ level: Int) -> Color {
        switch level {
        case 2: return Color(red: 0.80, green: 0.25, blue: 0.23)
        case 1: return Color(red: 0.73, green: 0.46, blue: 0.12)
        default: return ExpoStyle.mint
        }
    }
    /// Always present for a selected indoor destination, not just AI demo mode.
    private var routeCrowdExplanation: some View {
        HStack(spacing: 6) {
            if let summary = store.selectedRouteCrowd {
                Circle().fill(routeCrowdColor(summary.level)).frame(width: 7, height: 7)
                Text("زحمة المسار: \(routeCrowdLabel(summary.level))")
                    .foregroundStyle(routeCrowdColor(summary.level))
            } else {
                Image(systemName: "info.circle")
                Text("توقع الزحمة غير متاح")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(simplifiedRouteDecisionText)
                .foregroundStyle(ExpoStyle.green)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.vertical, 3)
    }
    private var simplifiedRouteDecisionText: String {
        if store.distinctRouteOptions {
            return store.routePreference == .fastest ? "الطريق الأزرق هو الأسرع الآن." : "الطريق الأحمر هو الأقصر مسافة."
        }
        return "نفس المسار الأقصر هو الأسرع أيضًا."
    }

    private func compactMetric(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(ExpoStyle.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12, weight: .bold)).foregroundStyle(ExpoStyle.green)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private var walkingHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk.motion")
                .foregroundStyle(ExpoStyle.mint)
            Text("إرشاد المشي داخل الجناح")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text("الدور \(store.position.floor)").font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(ExpoStyle.green)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 14)
        .padding(.top, 7)
    }
    private var compactWalkingBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedTitle ?? "الوجهة")
                        .font(.system(size: 14, weight: .bold)).lineLimit(1)
                    Text("المتبقي \(Int(store.metersRemaining.rounded())) م · \(walkDuration(store.secondsRemaining))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    if let summary = store.selectedRouteCrowd {
                        HStack(spacing: 5) {
                            Circle().fill(routeCrowdColor(summary.level)).frame(width: 7, height: 7)
                            Text("زحمة الطريق المختار: \(routeCrowdLabel(summary.level))")
                                .font(.system(size: 10, weight: .medium))
                        }
                    } else {
                        Text("توقع زحمة المسار غير متاح")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { store.cancelWalking() } label: {
                    Label("إلغاء", systemImage: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(ExpoStyle.green, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if let route = store.route {
                ProgressView(value: min(1, store.elapsed / max(1, route.seconds)))
                    .tint(ExpoStyle.ocean)
            }
        }
        .padding(13)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.bottom, 7)
    }
}

private struct ExpoPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).frame(minHeight: 41)
            .background(ExpoStyle.green, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
private struct ExpoSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ExpoStyle.green)
            .padding(.horizontal, 10).frame(minHeight: 41)
            .background(Color(red: 0.85, green: 0.91, blue: 0.87),
                        in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct ExpoExplorer: View {
    @ObservedObject var store: ExpoStore
    let startTab: String
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "pavilions"
    @State private var search = ""
    @State private var category = "الكل"

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                if store.mode == .outdoor {
                    HStack {
                        Image(systemName: "door.left.hand.open")
                        Text("اختاري جناحًا أو فعالية")
                        Spacer()
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ExpoStyle.green)
                    .padding(.horizontal, 17)
                }
                if store.mode == .outdoor {
                    Picker("المحتوى", selection: $tab) {
                        Text("الأجنحة").tag("pavilions")
                        Text("الفعاليات").tag("events")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                if store.mode == .indoor || tab == "events" {
                    let categories = Set(allEvents.map(\.category)).sorted()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(["الكل"] + categories, id: \.self) { cat in
                                Button(cat) { category = cat }
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(category == cat ? ExpoStyle.green : .gray.opacity(0.1), in: Capsule())
                                    .foregroundStyle(category == cat ? .white : ExpoStyle.green)
                            }
                        }.padding(.horizontal)
                    }
                }
                List {
                    if store.mode == .outdoor && tab == "pavilions" {
                        ForEach(store.sortedPavilions.filter {
                            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                        }) { pavilion in
                            Button {
                                store.selectLocation(pavilion.id)
                                dismiss()
                            } label: {
                                HStack(spacing: 11) {
                                    Image(systemName: "building.2.crop.circle")
                                        .font(.system(size: 23)).foregroundStyle(ExpoStyle.mint)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pavilion.name).font(.system(size: 14, weight: .bold))
                                        Text("\(store.dataset.events(for: pavilion.id).count) فعالية · \(store.dataset.booths(for: pavilion.id).count) بوث")
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 2)
                                    if let d = store.gateDistance(to: pavilion.id) {
                                        Text("\(Int(d.rounded())) م").font(.system(size: 12, weight: .bold))
                                    }
                                }.foregroundStyle(ExpoStyle.green)
                            }
                        }
                    } else {
                        ForEach(filteredEvents) { event in
                            Button {
                                store.selectEvent(event.id)
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundStyle(ExpoStyle.gold)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title_ar)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(store.dataset.booths.first(where: { $0.id == event.booth_id })?.name_ar ?? event.booth_id)
                                            .font(.system(size: 11)).foregroundStyle(.secondary)
                                        Text("\(event.start_time) – \(event.end_time)")
                                            .font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 3)
                                    if store.mode == .outdoor,
                                       let id = store.pavilionID(for: event),
                                       let d = store.gateDistance(to: id) {
                                        Text("\(Int(d.rounded())) م")
                                            .font(.system(size: 11, weight: .bold))
                                    } else if let space = store.dataset.space(for: event.booth_id) {
                                        Text("الدور \(space.floor)")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                }.foregroundStyle(ExpoStyle.green)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle(store.mode == .indoor ? "فعاليات جناح السعودية" : "استكشف إكسبو")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("إغلاق") { dismiss() } } }
            .searchable(text: $search, prompt: store.mode == .indoor ? "ابحث عن فعالية" : "ابحث عن جناح أو فعالية")
            .onAppear { tab = store.mode == .indoor ? "events" : startTab }
        }
    }
    private var allEvents: [ExpoNavEvent] {
        store.mode == .indoor ? store.dataset.events(for: "sa") : store.sortedEvents
    }
    private var filteredEvents: [ExpoNavEvent] {
        allEvents.filter { event in
            (category == "الكل" || event.category == category) &&
            (search.isEmpty || event.title_ar.localizedCaseInsensitiveContains(search) ||
             store.dataset.booths.first(where: { $0.id == event.booth_id })?
                .name_ar.localizedCaseInsensitiveContains(search) == true)
        }
    }
}
