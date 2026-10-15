import SwiftUI

/// 1.2 «البحث» (quick services, recent, nearest) and 1.3 «نتائج البحث».
struct MapSearchView: View {
    @Bindable var model: MapModel
    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var results: Loadable<[SearchResult]> = .idle
    @State private var nearest: [SearchResult] = []
    @FocusState private var focused: Bool

    /// Quick searches drawn in 1.2. Each maps to a query the map search understands.
    private let quick: [(String, AppIcon)] = [("دورات المياه", .droplet), ("المطاعم", .coffee), ("المصاعد", .accessible),
                                              ("نقاط المعلومات", .info), ("مساحة العمل", .briefcase)]
    @AppStorage("map.recentSearches") private var recentRaw = ""

    private var recent: [String] { recentRaw.split(separator: "|").map(String.init).filter { !$0.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Icon(.search, size: 20, color: .textSecondary)
                    TextField("ابحث عن جناح، جهة أو خدمة", text: $query)
                        .textStyle(.body)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { remember(query) }
                    if !query.isEmpty {
                        Button { query = "" } label: { Icon(.close, size: 14, color: .textTertiary).frame(width: 28, height: 28) }
                            .accessibilityLabel("مسح")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.brandPrimary, lineWidth: 1.5))
                Button("إلغاء") { model.isSearching = false }
                    .textStyle(.body).foregroundStyle(Color.brandPrimary)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        idleContent
                    } else {
                        resultsContent
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, 90)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if case .loaded(let list) = results, !list.isEmpty, !query.isEmpty {
                Button("عرض النتائج على الخريطة") {
                    remember(query)
                    model.isSearching = false
                    model.panel = .filterResults(list)
                }
                .appButton(.primary)
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, 8)
            }
        }
        .onAppear { focused = true }
        .task {
            if nearest.isEmpty {
                nearest = Array(((try? await services.map.search("", filter: MapFilter())) ?? []).prefix(3))
            }
        }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { results = .idle; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = .loading
            do { results = .loaded(try await services.map.search(q, filter: model.filter)) }
            catch let e as AppError { results = .failed(e) }
            catch { results = .failed(.unknown) }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        Text("بحث سريع").textStyle(.headline)
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(quick, id: \.0) { item in
                Button { query = item.0 } label: {
                    HStack(spacing: 6) {
                        Text(item.0).textStyle(.footnote).foregroundStyle(Color.textPrimary)
                        Icon(item.1, size: 16, color: .brandPrimary)
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Color.bgSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderDefault, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        if !recent.isEmpty {
            Text("عمليات بحث سابقة").textStyle(.headline)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(recent, id: \.self) { r in
                    Button { query = r } label: {
                        HStack(spacing: 8) {
                            Icon(.clock, size: 16, color: .textTertiary)
                            Text(r).textStyle(.body).foregroundStyle(Color.textPrimary)
                            Spacer()
                        }
                        .frame(minHeight: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !nearest.isEmpty {
            Text("الأقرب إليك").textStyle(.headline)
            VStack(spacing: 0) {
                ForEach(nearest) { r in
                    MapResultRow(booth: r.booth, subtitle: r.subtitle) { pick(r) }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch results {
        case .idle, .loading:
            LoadingStateView(title: "نبحث في الخريطة…")
        case .failed(let error):
            ErrorStateView(error: error) { let q = query; query = ""; query = q }
        case .loaded(let list) where list.isEmpty:
            EmptyStateView(icon: .search, title: "لا نتائج مطابقة",
                           message: "جرّبي اسم الجناح أو رقمه (مثل A7)، أو خففي الفلاتر.")
        case .loaded(let list):
            HStack {
                Text("\(ArabicDigits.format(list.count)) نتائج").textStyle(.headline)
                Spacer()
                Text("مرتبة حسب الأقرب").textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(list) { r in
                    MapResultRow(booth: r.booth, subtitle: r.subtitle) { pick(r) }
                    Divider()
                }
            }
        }
    }

    private func pick(_ r: SearchResult) {
        remember(r.booth.name)
        model.select(r.booth)
    }

    private func remember(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        recentRaw = ([t] + recent.filter { $0 != t }).prefix(5).joined(separator: "|")
    }
}

/// 1.4 «تصفية النتائج».
struct MapFilterSheet: View {
    @Bindable var model: MapModel
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MapFilter()
    @State private var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            MapPanelHeader(title: "تصفية النتائج", buttonIcon: .close, buttonLabel: "إغلاق") { dismiss() }

            Text("التصنيف").textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach([PlaceCategory.pavilions, .government, .companies, .services]) { c in
                    SelectableChip(title: c.title, isSelected: draft.category == c) {
                        draft.category = draft.category == c ? .all : c
                    }
                }
            }

            Text("مستوى الازدحام").textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                ForEach([CrowdLevel.low, .medium, .high], id: \.self) { level in
                    let on = draft.crowd.contains(level)
                    Button {
                        if on { draft.crowd.remove(level) } else { draft.crowd.insert(level) }
                    } label: {
                        Text(level.filterTitle).textStyle(.subheadStrong)
                            .foregroundStyle(level.color)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(on ? level.background : Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(on ? level.color : Color.borderDefault, lineWidth: on ? 1.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }

            Text("المسافة من موقعك").textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                ForEach([100, 200, 300, nil] as [Int?], id: \.self) { d in
                    SelectableChip(title: d.map { "\(ArabicDigits.format($0)) م" } ?? "أي مسافة",
                                   isSelected: draft.maxDistance == d) { draft.maxDistance = d }
                }
            }

            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(count.map { "عرض النتائج (\(ArabicDigits.format($0)))" } ?? "عرض النتائج") {
                    model.filter = draft
                    dismiss()
                    Task { await model.applyFilter() }
                }
                .appButton(.primary)
                .disabled(count == 0)
                Button("إعادة تعيين") { draft = MapFilter() }
                    .appButton(.mint).frame(width: 130)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onAppear { draft = model.filter }
        .task(id: draft) {
            count = (try? await services.map.search("", filter: draft))?.count
        }
    }
}
