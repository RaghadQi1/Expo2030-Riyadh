import SwiftUI

enum DiscoverRoute: Hashable {
    case search(axis: ExpoAxis?)
    case allEvents
    case notifications
    case qrScanner
}

/// 08.01 «الرئيسية» — greeting, search, next stop, axes, opportunity card, upcoming events, recommendations.
/// Guest variant: «اهلاً بك» + banner «لإنشاء حسابك اضغط هنا».
struct DiscoverTab: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var path = NavigationPath()
    @State private var feed: Loadable<DiscoverFeed> = .idle
    @State private var saved: Set<String> = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Color.bgCanvas.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: DiscoverRoute.self) { route in
                    switch route {
                    case .search(let axis): DiscoverSearchView(initialAxis: axis)
                    case .allEvents: AllEventsView()
                    case .notifications: NotificationsView()
                    case .qrScanner: QRScannerView()
                    }
                }
                .detailDestinations()
        }
        .task(id: "\(app.planRevision)-\(app.isGuest)") { await load() }
    }

    @ViewBuilder private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if app.isGuest {
                    StatusBanner(text: "تصفح كزائر.", tone: .info, icon: .user,
                                 linkTitle: "لإنشاء حسابك اضغط هنا") { app.isAuthPresented = true }
                }
                if connectivity.isOffline {
                    StatusBanner(text: "أنت غير متصل · تعرض بيانات محفوظة (\(services.sync.lastSyncedText))",
                                 tone: .warning, icon: .refresh)
                }
                searchField
                switch feed {
                case .idle, .loading:
                    LoadingStateView(title: "نجهّز ترشيحاتك…")
                case .failed(let error):
                    ErrorStateView(error: error) { Task { await load() } }
                case .loaded(let feed):
                    feedSections(feed)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 4)
        }
        .refreshable { await load() }
        .tabBarSafeArea()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.isGuest ? "اهلاً بك" : "اهلاً، \(app.displayName ?? "")")
                    .textStyle(.title3).foregroundStyle(Color.textPrimary)
                Text("الأربعاء · المعرض مفتوح حتى 11:00 م").textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                // RTL: .topLeading is the top-right corner, where Figma puts the unread dot.
                ZStack(alignment: .topLeading) {
                    CircleIconButton(icon: .bell, accessibilityLabel: "التنبيهات، يوجد جديد") { path.append(DiscoverRoute.notifications) }
                    Circle().fill(Color.statusError).frame(width: 8, height: 8).padding(10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                CircleIconButton(icon: .qr, accessibilityLabel: "مسح رمز جناح") { path.append(DiscoverRoute.qrScanner) }
            }
        }
    }

    private var searchField: some View {
        Button { path.append(DiscoverRoute.search(axis: nil)) } label: {
            HStack(spacing: 10) {
                Icon(.search, size: 22, color: .textSecondary)
                Text("وش ودك تكتشف؟").textStyle(.subhead).foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.filter, size: 18, color: .brandPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(height: 44)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .cardShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("بحث: وش ودك تكتشف؟")
    }

    @ViewBuilder private func feedSections(_ feed: DiscoverFeed) -> some View {
        if let next = feed.nextStop {
            NextStopCard(summary: next) { app.openMap(.navigateToBooth("A7")) }
        } else if !app.isGuest || !app.hasPersonalized {
            planPromptCard
        }

        SectionHeader(title: "المحاور", actionTitle: "الكل") { path.append(DiscoverRoute.search(axis: nil)) }
        HStack {
            ForEach(ExpoAxis.allCases) { axis in
                AxisButton(axis: axis) { path.append(DiscoverRoute.search(axis: axis)) }
                if axis != ExpoAxis.allCases.last { Spacer(minLength: 0) }
            }
        }

        if let first = feed.opportunities.first {
            SectionHeader(title: "فرصة تناسبك الآن")
            NavigationLink(value: DetailRoute.pavilion(first.id)) {
                PavilionCard(pavilion: first, isSaved: saved.contains(first.id)) { Task { await toggleSave(first) } }
            }
            .buttonStyle(.plain)
        }

        SectionHeader(title: "فعاليات قادمة", actionTitle: "عرض الكل") { path.append(DiscoverRoute.allEvents) }
        if feed.upcomingEvents.isEmpty {
            EmptyStateView(icon: .clock, title: "لا فعاليات قادمة الآن", message: "نحدّث القائمة كلما أضافت الجهات المشاركة فعاليات جديدة.")
        }
        VStack(spacing: 12) {
            ForEach(Array(feed.upcomingEvents.prefix(3).enumerated()), id: \.element.id) { index, event in
                NavigationLink(value: DetailRoute.event(event.id)) {
                    EventRow(event: event, minutesUntilStart: index == 0 ? 12 : nil)
                }
                .buttonStyle(.plain)
            }
        }

        SectionHeader(title: "تجارب متنوعة قد تهمك", actionTitle: "المزيد") { path.append(DiscoverRoute.search(axis: nil)) }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(feed.recommendations) { p in
                    NavigationLink(value: DetailRoute.pavilion(p.id)) {
                        PavilionCard(pavilion: p, size: .carousel, isSaved: saved.contains(p.id)) { Task { await toggleSave(p) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, Spacing.screen)
        }
        .padding(.horizontal, -Spacing.screen)

        HStack(spacing: 12) {
            Icon(.qr, size: 22, color: .brandPrimary)
                .frame(width: 44, height: 44)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("امسح رمز جناح").textStyle(.headline).foregroundStyle(Color.textPrimary)
                Text("احفظ الجناح أو أكّد زيارتك وأضف ملاحظة.").textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.chevronLeft, size: 18, color: .textTertiary)
        }
        .padding(14)
        .cardBackground(radius: 20)
        .onTapGesture { path.append(DiscoverRoute.qrScanner) }
        .accessibilityAddTraits(.isButton)
    }

    private var planPromptCard: some View {
        HStack(spacing: 12) {
            Icon(.sparkles, size: 22, color: .white)
                .frame(width: 44, height: 44)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("كوّن خطة تناسب وقتك").textStyle(.headline).foregroundStyle(Color.textPrimary)
                Text("ست أسئلة قصيرة، والترشيحات ليست حجزًا.").textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("ابدأ") { app.selectedTab = .plan }
                .appButton(.mint, height: 40, fullWidth: false)
        }
        .padding(14)
        .cardBackground(radius: 20)
    }

    @MainActor private func load() async {
        if feed.value == nil { feed = .loading }
        do {
            let result = try await services.catalog.discoverFeed(personalized: !app.isGuest)
            withAnimation { feed = .loaded(result) }
            saved = Set(((try? await services.journey.saved()) ?? []).map(\.id))
        } catch let error as AppError {
            // Offline (17.02): keep showing what was already loaded.
            if feed.value == nil { feed = .failed(error) }
        } catch {
            if feed.value == nil { feed = .failed(.unknown) }
        }
    }

    @MainActor private func toggleSave(_ pavilion: Pavilion) async {
        guard let isSaved = try? await services.journey.toggleSaved(placeId: pavilion.id) else { return }
        if isSaved { saved.insert(pavilion.id) } else { saved.remove(pavilion.id) }
        toasts.show(isSaved ? "حُفظ في «رحلتي ← محفوظة»" : "أُزيل من المحفوظة", icon: .heart, iconColor: .brandPrimary)
    }
}
