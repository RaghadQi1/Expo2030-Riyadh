import SwiftUI

/// Search + filters over pavilions (from the Discover search field, «الكل», axes and «المزيد»).
struct DiscoverSearchView: View {
    var initialAxis: ExpoAxis? = nil

    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var filters = SearchFilters()
    @State private var results: Loadable<[Pavilion]> = .idle
    @State private var showFilters = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Icon(.search, size: 20, color: .textSecondary)
                    TextField("وش ودك تكتشف؟", text: $query)
                        .textStyle(.body)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if !query.isEmpty {
                        Button { query = "" } label: { Icon(.close, size: 16, color: .textTertiary) }
                            .accessibilityLabel("مسح")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Button { showFilters = true } label: {
                    Icon(.filter, size: 18, color: filters.isEmpty ? .brandPrimary : .white)
                        .frame(width: 44, height: 44)
                        .background(filters.isEmpty ? Color.brandMint : Color.brandPrimary,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .accessibilityLabel(filters.isEmpty ? "الفلاتر" : "الفلاتر، مفعّلة")
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ExpoAxis.allCases) { axis in
                        SelectableChip(title: axis.title, isSelected: filters.axes.contains(axis)) {
                            if filters.axes.contains(axis) { filters.axes.remove(axis) } else { filters.axes.insert(axis) }
                        }
                    }
                }
                .padding(.horizontal, Spacing.screen)
            }

            Group {
                switch results {
                case .idle, .loading:
                    LoadingStateView()
                case .failed(let error):
                    ErrorStateView(error: error) { Task { await search() } }
                case .loaded(let list) where list.isEmpty:
                    EmptyStateView(icon: .search, title: "لا نتائج مطابقة",
                                   message: "جرّب كلمة أخرى أو خفّف الفلاتر.",
                                   actionTitle: filters.isEmpty ? nil : "مسح الفلاتر") { filters = SearchFilters() }
                case .loaded(let list):
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            Text("\(list.count) نتيجة").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(list) { p in
                                NavigationLink(value: DetailRoute.pavilion(p.id)) { PavilionCard(pavilion: p) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(Spacing.screen)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color.bgCanvas)
        .appNavigationChrome(title: initialAxis.map { "محور \($0.title)" } ?? "اكتشف")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .sheet(isPresented: $showFilters) {
            DiscoverFilterSheet(filters: $filters)
                .presentationDetents([.medium])
        }
        .task(id: "\(query)|\(filters.axes.map(\.rawValue).sorted())|\(filters.lowCrowdOnly)|\(String(describing: filters.maxDistanceMeters))") {
            try? await Task.sleep(for: .milliseconds(250))
            await search()
        }
        .onAppear {
            if let initialAxis, filters.axes.isEmpty { filters.axes = [initialAxis] }
        }
    }

    @MainActor private func search() async {
        if results.value == nil { results = .loading }
        do {
            var list = try await services.catalog.pavilions(filters: filters)
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty {
                let matches = Set(try await services.catalog.search(q).map(\.id))
                list = list.filter { matches.contains($0.id) }
            }
            results = .loaded(list)
        } catch let error as AppError {
            results = .failed(error)
        } catch {
            results = .failed(.unknown)
        }
    }
}

struct DiscoverFilterSheet: View {
    @Binding var filters: SearchFilters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("ازدحام منخفض فقط", isOn: $filters.lowCrowdOnly).textStyle(.body)
                Toggle("مفتوح الآن", isOn: $filters.openNow).textStyle(.body)
                Text("المسافة من موقعك").textStyle(.headline)
                HStack(spacing: 8) {
                    ForEach([nil, 300, 500, 1000] as [Int?], id: \.self) { d in
                        SelectableChip(title: d.map { "حتى \($0) م" } ?? "أي مسافة", isSelected: filters.maxDistanceMeters == d) {
                            filters.maxDistanceMeters = d
                        }
                    }
                }
                Text("المسافات تقديرية وتظهر فقط عند توفر موقعك.").textStyle(.caption).foregroundStyle(Color.textTertiary)
                Spacer()
                HStack(spacing: 10) {
                    Button("عرض النتائج") { dismiss() }.appButton(.primary)
                    Button("مسح") { filters = SearchFilters() }.appButton(.tertiary)
                }
            }
            .tint(.brandPrimary)
            .padding(20)
            .appNavigationChrome(title: "تصفية النتائج")
        }
    }
}

/// «فعاليات قادمة ← عرض الكل».
struct AllEventsView: View {
    @Environment(AppServices.self) private var services
    @State private var events: Loadable<[ExpoEvent]> = .idle

    var body: some View {
        Group {
            switch events {
            case .idle, .loading: LoadingStateView()
            case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
            case .loaded(let list) where list.isEmpty:
                EmptyStateView(icon: .clock, title: "لا فعاليات قادمة الآن")
            case .loaded(let list):
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(list) { e in
                            NavigationLink(value: DetailRoute.event(e.id)) { EventRow(event: e) }.buttonStyle(.plain)
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgCanvas)
        .appNavigationChrome(title: "فعاليات قادمة")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task { await load() }
    }

    @MainActor private func load() async {
        events = .loading
        do { events = .loaded(try await services.catalog.events()) }
        catch let e as AppError { events = .failed(e) } catch { events = .failed(.unknown) }
    }
}

/// Notification centre (bell on Discover). Demo content only — real pushes need the backend + APNs.
struct NotificationsView: View {
    private struct Item: Identifiable {
        let id: Int
        let icon: AppIcon
        let title: String
        let detail: String
        let time: String
    }

    private let items: [Item] = [
        Item(id: 1, icon: .users, title: "الجناح القادم مزدحم", detail: "المدن الذكية · انتظار ~25 د. افتح «خطتي» لرؤية البدائل.", time: "قبل 3 د"),
        Item(id: 2, icon: .clock, title: "عرض «مدينة 2050» يبدأ قريبًا", detail: "يبدأ 4:00 م في جناح المدن الذكية.", time: "قبل 12 د"),
        Item(id: 3, icon: .addPerson, title: "دعوة تواصل من ذكرى", detail: "افتح «الخريطة ← الأصدقاء» للرد على الدعوة.", time: "قبل 20 د"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                StatusBanner(text: "هذه التنبيهات لا تُرسل إشعارات فعلية.", tone: .warning)
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Icon(item.icon, size: 20, color: .brandPrimary)
                            .frame(width: 40, height: 40)
                            .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).textStyle(.headline)
                            Text(item.detail).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.time).textStyle(.caption2).foregroundStyle(Color.textTertiary)
                    }
                    .padding(14)
                    .cardBackground(radius: 18)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Spacing.screen)
        }
        .background(Color.bgCanvas)
        .appNavigationChrome(title: "التنبيهات")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
    }
}
