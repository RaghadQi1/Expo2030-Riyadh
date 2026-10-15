import SwiftUI

/// «خريطتي» — indoor hall map (Figma sections «خريطتي ١ – ١١»).
struct LegacyMapTab: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toast
    @State private var model = MapModel()
    @State private var panelHeight: CGFloat = 0
    @State private var askedLocation = false

    var body: some View {
        ZStack(alignment: .top) {
            HallMapView(model: model, bottomInset: panelHeight, topInset: model.navigation == nil ? 150 : 170)
                .ignoresSafeArea()
                .opacity(model.isLoaded ? 1 : 0.4)

            if !model.isLoaded {
                if let error = model.loadError {
                    ErrorStateView(error: error) { Task { await model.load() } }
                        .cardBackground()
                        .padding(Spacing.screen)
                        .frame(maxHeight: .infinity)
                } else {
                    LoadingStateView(title: "جارٍ تحميل خريطة المعرض…").frame(maxHeight: .infinity)
                }
            }

            VStack(spacing: 10) {
                if model.navigation != nil {
                    NavigationTopCard(model: model)
                } else {
                    MapTopBar(model: model)
                }
                MapStatusChips(model: model)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 6)

            controls
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            panel
                .background(GeometryReader { geo in
                    Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
                })
        }
        .onPreferenceChange(PanelHeightKey.self) { panelHeight = $0 }
        .overlay {
            if model.isSearching {
                MapSearchView(model: model)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.panel)
        .animation(.easeInOut(duration: 0.2), value: model.isSearching)
        .background {
            if model.panel.hidesTabBar || model.isSearching { Color.clear.hidesMainChrome() }
        }
        .sheet(item: $model.sheet) { sheet in
            sheetContent(sheet)
        }
        .task {
            model.attach(services)
            if !model.isLoaded { await model.load() }
            if model.permissions.status == .notDetermined, !askedLocation {
                askedLocation = true
                model.sheet = .locationExplainer
            }
        }
        .task(id: app.mapRequest) {
            guard let request = app.mapRequest else { return }
            model.attach(services)
            await model.handle(request)
            app.mapRequest = nil
        }
        .onChange(of: model.permissions.status) { _, _ in
            Task { await model.refreshLocation() }
        }
    }

    // MARK: Controls (left column in RTL)

    private var controls: some View {
        HStack(alignment: .top) {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if model.navigation == nil {
                    HStack(spacing: 8) {
                        MapControlButton(icon: .cube, label: model.isFlat ? "العودة للمجسم" : "منظور علوي مسطّح", isActive: model.isFlat) {
                            model.isFlat.toggle()
                        }
                        if model.isFlat {
                            MapHint(text: "منظور علوي مسطّح، اضغطي المكعب للعودة للمجسم")
                                .environment(\.layoutDirection, .rightToLeft)
                                .allowsHitTesting(false)
                        }
                    }
                    MapControlButton(icon: .plus, label: "تكبير") { model.zoom(by: 1.3) }
                    MapControlButton(icon: .minus, label: "تصغير") { model.zoom(by: 1 / 1.3) }
                    MapControlButton(icon: .users, label: "الأصدقاء على الخريطة") { model.panel = .friends }
                } else {
                    MapControlButton(icon: .cube, label: "منظور علوي مسطّح", isActive: model.isFlat) { model.isFlat.toggle() }
                    MapControlButton(icon: .users, label: "الأصدقاء على الخريطة") { model.panel = .friends }
                }
                Spacer()
                if model.showScaleBar { ScaleBar(zoom: model.camera.zoom) }
                MapControlButton(icon: .navigate, label: "موقعي", isActive: model.isFollowing && model.location != nil) {
                    model.recenter()
                }
            }
            .padding(.top, model.navigation == nil ? 120 : 160)
            .padding(.bottom, 12)
            .environment(\.layoutDirection, .leftToRight)
        }
        .padding(.horizontal, Spacing.screen)
        .padding(.bottom, model.panel == .none ? 84 : panelHeight)
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var panel: some View {
        if model.isLoaded {
            MapPanelSwitch(model: model)

        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: MapSheet) -> some View {
        switch sheet {
        case .filter:
            MapFilterSheet(model: model).presentationDetents([.medium, .large])
        case .compareRoutes(let target, let routes, let current):
            CompareRoutesSheet(model: model, target: target, routes: routes, current: current)
                .presentationDetents([.medium])
        case .note(let booth):
            BoothNoteSheet(model: model, booth: booth).presentationDetents([.medium, .large])
        case .invite:
            InviteSheet(model: model).presentationDetents([.large])
        case .scanFriend:
            ScanFriendSheet(model: model)
        case .incomingInvite(let invite):
            IncomingInviteSheet(model: model, invite: invite).presentationDetents([.medium])
        case .shareMode(let friend):
            ShareModeSheet(model: model, friend: friend)
        case .shareSettings(let friend):
            ShareSettingsSheet(model: model, friendId: friend.id)
        case .locationExplainer:
            LocationExplainerSheet {
                model.sheet = nil
                model.permissions.requestWhenInUse()
            } onLater: {
                model.sheet = nil
            }
            .presentationDetents([.medium, .large])
        case .notificationsExplainer:
            NotificationsExplainerSheet {
                model.sheet = nil
                Task { await model.permissions.requestNotifications() }
            } onLater: {
                model.sheet = nil
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// «١٠ م» scale indicator while zooming (1.9).
struct ScaleBar: View {
    let zoom: CGFloat
    var body: some View {
        VStack(spacing: 2) {
            Text("١٠ م").font(AppFont.arabic(10, .semibold)).foregroundStyle(Color.textPrimary)
            Rectangle().fill(Color.textPrimary)
                .frame(width: 10 / MapCamera.metersPerPoint * zoom, height: 3)
                .overlay(alignment: .leading) { Rectangle().fill(Color.textPrimary).frame(width: 1.5, height: 8) }
                .overlay(alignment: .trailing) { Rectangle().fill(Color.textPrimary).frame(width: 1.5, height: 8) }
        }
        .padding(6)
        .glassBackground(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel("مقياس الرسم: ١٠ أمتار")
    }
}

// MARK: - Top bar (1.1)

struct MapTopBar: View {
    @Bindable var model: MapModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { model.isSearching = true } label: {
                    HStack(spacing: 8) {
                        Icon(.search, size: 20, color: .textSecondary)
                        Text("ابحث عن جناح، جهة أو خدمة")
                            .textStyle(.subhead).foregroundStyle(Color.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .glassBackground(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .glassShadow()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ابحث عن جناح، جهة أو خدمة")

                squareButton(.filter, label: model.filter.isEmpty ? "تصفية النتائج" : "تصفية النتائج، مفعّلة",
                             active: !model.filter.isEmpty) { model.sheet = .filter }
                squareButton(.addPerson, label: "الأصدقاء ومشاركة الموقع") { model.panel = .friends }
            }

            if !model.filter.isEmpty, case .filterResults = model.panel {
                // 1.5 active filters pill
                HStack(spacing: 8) {
                    Button { model.clearFilter() } label: {
                        HStack(spacing: 6) {
                            Text(model.filter.summary).textStyle(.caption).foregroundStyle(.white)
                            Icon(.close, size: 14, color: .white)
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Color.brandPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("مسح الفلاتر: \(model.filter.summary)")
                    Button("تعديل") { model.sheet = .filter }
                        .textStyle(.caption).foregroundStyle(Color.brandPrimary)
                        .padding(.horizontal, 12).frame(height: 36)
                        .glassBackground(Capsule())
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([PlaceCategory.all, .pavilions, .government, .companies, .services]) { c in
                            let selected = model.category == c
                            Button { model.setCategory(c) } label: {
                                Text(c.title).textStyle(.caption)
                                    .foregroundStyle(selected ? Color.white : Color.textPrimary)
                                    .padding(.horizontal, 14).frame(height: 36)
                                    .background {
                                        if selected { Capsule().fill(Color.brandPrimary) }
                                        else { Capsule().fill(.clear).glassBackground(Capsule()) }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    private func squareButton(_ icon: AppIcon, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 22, color: active ? .white : .textPrimary)
                .frame(width: 52, height: 52)
                .background {
                    if active { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.brandPrimary) }
                    else { Color.clear.glassBackground(RoundedRectangle(cornerRadius: 20, style: .continuous)) }
                }
                .glassShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Explore-mode banners (1.7), sharing chip (5.6 / 5.20) and low-accuracy banner (4.13).
struct MapStatusChips: View {
    @Bindable var model: MapModel
    @Environment(ToastCenter.self) private var toast
    @State private var confirmEndVisit = false
    @Environment(AppServices.self) private var services

    var body: some View {
        VStack(spacing: 8) {
            if model.permissions.isApproximate && model.permissions.canShowLocation {
                LowAccuracyBanner()
            }
            if !model.isFollowing {
                HStack(spacing: 6) {
                    MapHint(text: model.navigation != nil ? "اسحبي الخريطة للاستكشاف، والتوجيه مستمر"
                                                          : "وضع الاستكشاف، التتبع متوقف مؤقتًا", icon: .eye)
                    if let d = model.distanceToMeText {
                        Text(d).textStyle(.caption).foregroundStyle(Color.locationBlue)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.locationBlueBg, in: Capsule())
                    }
                    Spacer()
                }
            }
            if let friend = model.mySharingFriend, model.navigation == nil {
                sharingChip(friend)
            }
        }
        .confirmationDialog("إنهاء زيارتك للمعرض؟", isPresented: $confirmEndVisit, titleVisibility: .visible) {
            Button("إنهاء الزيارة", role: .destructive) {
                Task {
                    try? await services.friends.endVisit()
                    await model.reloadFriends()
                    toast.show("انتهت زيارتك وتوقفت مشاركة موقعك")
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("ستتوقف مشاركة موقعك مع \(model.mySharingFriend?.name ?? "صديقاتك") فورًا، وتبقى زياراتك وملاحظاتك محفوظة.")
        }
    }

    @ViewBuilder
    private func sharingChip(_ friend: Friend) -> some View {
        HStack(spacing: 8) {
            Button { model.sheet = .shareSettings(friend) } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.locationBlue).frame(width: 8, height: 8)
                    Text(sharingText(friend)).textStyle(.caption).foregroundStyle(Color.locationBlue)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.locationBlueBg, in: Capsule())
            }
            .buttonStyle(.plain)
            if friend.myShare == .untilEndOfVisit {
                Button("إنهاء الزيارة") { confirmEndVisit = true }
                    .textStyle(.caption).foregroundStyle(Color.statusError)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.statusErrorBg, in: Capsule())
            }
            Spacer()
        }
    }

    private func sharingText(_ f: Friend) -> String {
        if f.myShare == .untilEndOfVisit { return "تشاركين موقعك حتى نهاية زيارتك" }
        let left = max(0, (f.myShareEndsAt?.minutes ?? model.now.minutes) - model.now.minutes)
        return "تشاركين موقعك مع \(f.name)، باقي \(ArabicDigits.format(left)) د"
    }
}
