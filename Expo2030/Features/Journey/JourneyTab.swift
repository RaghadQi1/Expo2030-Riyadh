import SwiftUI

enum JourneyRoute: Hashable {
    case summary
    case note(VisitNote)
}

/// «رحلتي» (13.01 visited · 13.09 saved · notes · follow-up; 17.04 / 17.06 sync states).
struct JourneyTab: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(ConnectivityMonitor.self) private var connectivity

    @State private var path = NavigationPath()
    @State private var tab: JourneySection = .visited
    @State private var visits: Loadable<[JourneyVisit]> = .idle
    @State private var saved: Loadable<[SavedPlace]> = .idle
    @State private var notes: Loadable<[VisitNote]> = .idle
    @State private var followUps: Loadable<[FollowUpItem]> = .idle

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    tabs
                    syncBanner
                    switch tab {
                    case .visited: visitedList
                    case .saved: savedList
                    case .notes: notesList
                    case .followUp: followUpList
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, 4)
            }
            .refreshable { await load() }
            .tabBarSafeArea()
            .background(Color.bgCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: JourneyRoute.self) { route in
                switch route {
                case .summary: JourneySummaryView()
                case .note(let note): NoteEditorView(note: note)
                }
            }
            .detailDestinations()
        }
        .task(id: "\(app.journeyRevision)") { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("رحلتي").textStyle(.largeTitle).foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { path.append(JourneyRoute.summary) } label: {
                HStack(spacing: 6) {
                    Text("ملخص اليوم").textStyle(.caption)
                    Icon(.sparkles, size: 16)
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Color.brandMint, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(JourneySection.allCases) { t in
                Button { withAnimation(.easeInOut(duration: 0.2)) { tab = t } } label: {
                    VStack(spacing: 6) {
                        Text(t.title).textStyle(tab == t ? .subheadStrong : .subhead)
                            .foregroundStyle(tab == t ? Color.brandPrimary : Color.textSecondary)
                        Capsule().fill(tab == t ? Color.brandPrimary : .clear).frame(width: 40, height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var syncBanner: some View {
        let pending = notes.value?.filter(\.isPendingSync).count ?? 0
        if pending > 0 {
            StatusBanner(text: "\(pending) \(pending == 1 ? "ملاحظة" : "ملاحظات") بانتظار المزامنة · محفوظة على جهازك ولن تُفقد",
                         tone: .warning, icon: .refresh)
        } else if connectivity.isOffline {
            StatusBanner(text: "أنت غير متصل · ما تكتبه يُحفظ على جهازك ويُزامَن لاحقًا", tone: .warning, icon: .refresh)
        }
    }

    // MARK: Visited (13.01)

    @ViewBuilder
    private var visitedList: some View {
        switch visits {
        case .idle, .loading: LoadingStateView()
        case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
        case .loaded(let list) where list.isEmpty:
            EmptyStateView(icon: .journey, title: "لا زيارات بعد",
                           message: "أكّدي زيارتك من صفحة الجناح أو امسحي رمزه، وستظهر هنا.")
        case .loaded(let list):
            Text("\(Self.todayTitle) · \(list.filter { $0.confirmation == .confirmed }.count) زيارات")
                .textStyle(.caption).foregroundStyle(Color.textSecondary)
            VStack(spacing: 12) {
                ForEach(list) { visit in
                    Button { open(placeId: visit.placeId) } label: { VisitCard(visit: visit) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if visit.confirmation != .confirmed {
                                Button { Task { await confirm(visit) } } label: { Label("أكد زيارتي", systemImage: "checkmark") }
                            }
                        }
                }
            }
        }
    }

    // MARK: Saved (13.09)

    @ViewBuilder
    private var savedList: some View {
        switch saved {
        case .idle, .loading: LoadingStateView()
        case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
        case .loaded(let list) where list.isEmpty:
            EmptyStateView(icon: .heart, title: "لا عناصر محفوظة",
                           message: "اضغطي ♡ على أي جناح لتجديه هنا لاحقًا.")
        case .loaded(let list):
            Text("\(list.count) عناصر محفوظة").textStyle(.caption).foregroundStyle(Color.textSecondary)
            VStack(spacing: 14) {
                ForEach(list) { place in
                    Button { open(placeId: place.id) } label: {
                        SavedPlaceCard(place: place) { Task { await unsave(place) } }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Notes

    @ViewBuilder
    private var notesList: some View {
        switch notes {
        case .idle, .loading: LoadingStateView()
        case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
        case .loaded(let list) where list.isEmpty:
            EmptyStateView(icon: .note, title: "لا ملاحظات بعد",
                           message: "أضيفي ملاحظة من صفحة الجناح أو بعد مسح رمزه.")
        case .loaded(let list):
            VStack(spacing: 12) {
                ForEach(list) { note in
                    Button { path.append(JourneyRoute.note(note)) } label: { NoteCard(note: note) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Follow-up

    @ViewBuilder
    private var followUpList: some View {
        switch followUps {
        case .idle, .loading: LoadingStateView()
        case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
        case .loaded(let list) where list.isEmpty:
            EmptyStateView(icon: .flag, title: "لا شيء للمتابعة",
                           message: "أسئلة «للمتابعة» في ملاحظاتك وخطواتك القادمة تظهر هنا.")
        case .loaded(let list):
            VStack(spacing: 0) {
                ForEach(list) { item in
                    Button { Task { await toggle(item) } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(item.isDone ? Color.brandPrimary : Color.borderStrong)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).textStyle(.body)
                                    .foregroundStyle(item.isDone ? Color.textTertiary : Color.textPrimary)
                                    .strikethrough(item.isDone)
                                Text(item.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.isDone ? .isSelected : [])
                    Divider()
                }
            }
            .padding(.horizontal, 14)
            .cardBackground(radius: 20)
        }
    }

    // MARK: Actions

    private static var todayTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA@numbers=latn")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: Date())
    }

    private func open(placeId: String) {
        // Hall booths (A7, B6…) open on the map; pavilions open their detail page.
        if placeId.count <= 3, placeId.first?.isLetter == true, placeId.dropFirst().allSatisfy(\.isNumber) {
            app.openMap(.showBooth(placeId))
        } else {
            path.append(DetailRoute.pavilion(placeId))
        }
    }

    @MainActor private func load() async {
        async let v = result { try await services.journey.visits() }
        async let s = result { try await services.journey.saved() }
        async let n = result { try await services.journey.notes() }
        async let f = result { try await services.journey.followUps() }
        // On failure (e.g. offline) keep what is already on screen.
        let (rv, rs, rn, rf) = await (v, s, n, f)
        if rv.value != nil || visits.value == nil { visits = rv }
        if rs.value != nil || saved.value == nil { saved = rs }
        if rn.value != nil || notes.value == nil { notes = rn }
        if rf.value != nil || followUps.value == nil { followUps = rf }
    }

    private func result<T>(_ fetch: () async throws -> T) async -> Loadable<T> {
        do { return .loaded(try await fetch()) }
        catch let e as AppError { return .failed(e) }
        catch { return .failed(.unknown) }
    }

    @MainActor private func confirm(_ visit: JourneyVisit) async {
        do {
            try await services.journey.confirmVisit(placeId: visit.placeId)
            toasts.show("تم تأكيد زيارتك")
            await load()
        } catch {
            toasts.show((error as? AppError)?.message ?? "تعذّر تأكيد الزيارة", icon: .warning, iconColor: .statusError)
        }
    }

    @MainActor private func unsave(_ place: SavedPlace) async {
        _ = try? await services.journey.toggleSaved(placeId: place.id)
        if case .loaded(var list) = saved {
            list.removeAll { $0.id == place.id }
            saved = .loaded(list)
        }
        toasts.show("أُزيل من المحفوظات", icon: .heart, iconColor: .textSecondary)
    }

    @MainActor private func toggle(_ item: FollowUpItem) async {
        guard case .loaded(var list) = followUps, let i = list.firstIndex(where: { $0.id == item.id }) else { return }
        list[i].isDone.toggle()
        followUps = .loaded(list)
        do { try await services.journey.setFollowUp(id: item.id, done: list[i].isDone) }
        catch {
            list[i].isDone.toggle()
            followUps = .loaded(list)
            toasts.show("تعذّر الحفظ الآن", icon: .warning, iconColor: .statusError)
        }
    }
}

// MARK: - Cards

struct VisitCard: View {
    let visit: JourneyVisit
    var body: some View {
        HStack(spacing: 12) {
            PhotoView(name: visit.thumbnail).frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                Text(visit.timeText).textStyle(.caption).foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    switch visit.confirmation {
                    case .confirmed:
                        Tag(text: "✓ زيارة أكدتها", foreground: .statusSuccess, background: .statusSuccessBg)
                    case .scannedOnly:
                        Tag(text: "لم تؤكد الزيارة", foreground: .textSecondary, background: .bgSurface2)
                    }
                    if let extras = visit.extrasText {
                        Tag(text: extras, foreground: .brandPrimary, background: .brandMint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.chevronLeft, size: 16, color: .textTertiary)
        }
        .padding(12)
        .cardBackground(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

struct SavedPlaceCard: View {
    let place: SavedPlace
    var onUnsave: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PhotoView(name: place.photo).frame(height: 150).clipped()
                Button(action: onUnsave) {
                    Icon(.heart, size: 18, color: .statusError)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.92), in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel("إزالة من المحفوظات")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(place.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                Text(place.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            .padding(14)
        }
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .cardShadow()
    }
}

struct NoteCard: View {
    let note: VisitNote
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.placeName).textStyle(.caption).foregroundStyle(Color.brandPrimary)
                Spacer()
                if note.isPendingSync {
                    Tag(text: "بانتظار المزامنة", foreground: .statusWarning, background: .statusWarningBg, icon: .refresh)
                }
            }
            if !note.title.isEmpty { Text(note.title).textStyle(.headline).foregroundStyle(Color.textPrimary) }
            if !note.preview.isEmpty && note.preview != note.title {
                Text(note.preview).textStyle(.footnote).foregroundStyle(Color.textSecondary).lineLimit(2)
            }
            if !note.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(note.attachments) { a in
                        Tag(text: a.kind.title, foreground: .textSecondary, background: .bgSurface2,
                            icon: a.kind == .photo ? .image : (a.kind == .voice ? .mic : .link))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: 20)
        .accessibilityElement(children: .combine)
    }
}
