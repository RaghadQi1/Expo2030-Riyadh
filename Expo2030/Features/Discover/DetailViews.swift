import SwiftUI

// MARK: - 08.06 / 08.10 Pavilion detail

struct PavilionDetailView: View {
    let pavilionId: String

    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var state: Loadable<Pavilion> = .idle
    @State private var addedTime: TimeOfDay?
    @State private var isAdding = false
    @State private var isSaved = false
    @State private var isPinned = false
    @State private var conflict: PlanConflict?
    @State private var showNote = false
    @State private var showProfileShare = false

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingStateView().frame(maxHeight: .infinity)
            case .failed(let error):
                VStack {
                    DetailTopBar(onBack: { dismiss() })
                    ErrorStateView(error: error) { Task { await load() } }
                    Spacer()
                }
            case .loaded(let p):
                content(p)
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesMainChrome()
        .task { await load() }
        .sheet(item: $conflict) { c in
            ConflictSheet(conflict: c) { option in
                Task {
                    _ = try? await services.plan.resolveConflict(c, with: option)
                    conflict = nil
                    app.planRevision += 1
                    toasts.show(option.id == "later" ? "حُفظت في «محفوظة» دون تغيير الخطة." : "حُدّثت خطتك. الإضافة ليست حجزًا مؤكدًا.")
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNote) {
            if let p = state.value {
                NavigationStack { NoteEditorView(note: VisitNote(id: UUID().uuidString, placeId: p.id, placeName: p.name)) }
            }
        }
        .sheet(isPresented: $showProfileShare) {
            NavigationStack { ShareProfileView() }
        }
    }

    private func content(_ p: Pavilion) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotoView(name: p.photo, label: p.name)
                    .overlay(Color.black.opacity(0.3))
                    .frame(height: 330)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {   // RTL: entry tag on the right, axis on the left (as drawn)
                        DetailTag(text: p.entry.title,
                                  foreground: isExternal(p.entry) ? .statusInfo : .statusSuccess,
                                  background: isExternal(p.entry) ? .statusInfoBg : .statusSuccessBg)
                        DetailTag(text: p.axis.title, foreground: .white, background: p.axis.color)
                    }
                    Text(p.name).textStyle(.title1).foregroundStyle(Color.textPrimary)
                    Text("الجهة: \(p.organization) · \(p.experienceType)").textStyle(.subhead).foregroundStyle(Color.textSecondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            CrowdBadge(level: p.live.crowd)
                            if let wait = p.live.waitMinutes {
                                Text("انتظار ~\(wait) د").font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
                            }
                        }
                        FreshnessLine(status: p.live)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))

                    FactGrid(facts: [
                        Fact(icon: .clock, label: "مدة الزيارة", value: "\(p.durationMinutes) دقيقة"),
                        Fact(icon: .clock, label: "الوقت", value: p.hours),
                        Fact(icon: .door, label: "المدخل", value: p.entrance),
                        Fact(icon: .globe, label: "اللغة", value: p.languages),
                    ])

                    DetailSection(title: "عن التجربة") {
                        Text(p.about).textStyle(.body).foregroundStyle(Color.textSecondary)
                    }
                    DetailSection(title: "ما الذي ستختبره؟") {
                        ForEach(p.highlights, id: \.self) { BulletRow(text: $0, icon: .check, color: .brandPrimary) }
                    }
                    DetailSection(title: "شروط الحضور") {
                        ForEach(p.attendanceRules, id: \.self) { BulletRow(text: $0, icon: .info, color: .textSecondary) }
                    }
                    DetailSection(title: "الإتاحة") {
                        AccessibilityCard(items: p.accessibility, verifiedOn: p.accessibilityVerifiedOn)
                    }
                    DetailSection(title: "الموقع والمدخل") {
                        SiteMapView(center: p.sitePoint, pins: [SitePin(id: p.id, name: p.shortName, point: p.sitePoint, state: .selected)])
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        Text(p.entranceNote + (p.walkMinutes.map { " · \($0) د مشيًا من موقعك" } ?? ""))
                            .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }

                    HStack(spacing: 8) {
                        SecondaryAction(icon: .heart, title: isSaved ? "محفوظ" : "احفظ") { Task { await toggleSave(p) } }
                        SecondaryAction(icon: .note, title: "أضف ملاحظة") { showNote = true }
                        SecondaryAction(icon: .briefcase, title: "ملفي المهني") {
                            if app.isGuest { app.isAuthPresented = true } else { showProfileShare = true }
                        }
                        ShareLink(item: shareText(p)) {
                            SecondaryActionLabel(icon: .share, title: "مشاركة الرابط")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .background(Color.bgSurface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .padding(.top, -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            DetailTopBar(isSaved: isSaved, shareText: shareText(p), onBack: { dismiss() }, onSave: { Task { await toggleSave(p) } })
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    if let addedTime {
                        Button {} label: { ButtonLabel(title: "مضاف للخطة · \(addedTime.arabic12h)", icon: .check) }
                            .appButton(.mint)
                            .disabled(true)
                            .accessibilityLabel("مضاف للخطة، الساعة \(addedTime.arabic12h)")
                    } else {
                        Button("أضف إلى خطتي") { Task { await add(p) } }
                            .appButton(.primary, isLoading: isAdding)
                    }
                    Button { app.openMap(.navigateToBooth("A7")) } label: { Icon(.navigate, size: 24, color: .brandPrimary) }
                        .frame(width: 52, height: 52)
                        .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityLabel("الاتجاهات")
                    Button {
                        isPinned.toggle()
                        toasts.show(isPinned ? "ثبّتناه كأولوية في خطتك ★" : "أزلنا التثبيت", icon: .star, iconColor: .axisCoop)
                    } label: {
                        Icon(.star, size: 24, color: isPinned ? .white : .brandPrimary)
                    }
                    .frame(width: 52, height: 52)
                    .background(isPinned ? Color.axisCoop : Color.brandMint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(isPinned ? "إلغاء التثبيت كأولوية" : "تثبيت كأولوية")
                }
            }
        }
    }

    private func isExternal(_ e: EntryPolicy) -> Bool {
        if case .externalBooking = e { return true }
        return false
    }

    private func shareText(_ p: Pavilion) -> String {
        "\(p.name) — \(p.experienceType) في إكسبو 2030 الرياض. (رابط: expo2030.example/p/\(p.id))"
    }

    @MainActor private func load() async {
        state = .loading
        do {
            let p = try await services.catalog.pavilion(id: pavilionId)
            state = .loaded(p)
            isSaved = ((try? await services.journey.saved()) ?? []).contains { $0.id == p.id }
        } catch let error as AppError { state = .failed(error) } catch { state = .failed(.unknown) }
    }

    @MainActor private func add(_ p: Pavilion) async {
        isAdding = true
        defer { isAdding = false }
        do {
            switch try await services.plan.add(itemId: p.id) {
            case .added(let position, let time):
                withAnimation { addedTime = time }
                app.planRevision += 1
                toasts.show("أُضيف للخطة كمحطة \(position) · ليس حجزًا مؤكدًا")
            case .conflict(let c):
                conflict = c
            }
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }

    @MainActor private func toggleSave(_ p: Pavilion) async {
        guard let saved = try? await services.journey.toggleSaved(placeId: p.id) else { return }
        isSaved = saved
        toasts.show(saved ? "حُفظ في «رحلتي ← محفوظة»" : "أُزيل من المحفوظة", icon: .heart, iconColor: .brandPrimary)
    }
}

// MARK: - 08.07 Event detail (external booking)

struct EventDetailView: View {
    let eventId: String

    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var state: Loadable<ExpoEvent> = .idle
    @State private var showExternal = false
    @State private var conflict: PlanConflict?
    @State private var isAdding = false
    @State private var visitedBookingSite = false
    @State private var markedBooked = false

    var body: some View {
        Group {
            switch state {
            case .idle, .loading: LoadingStateView().frame(maxHeight: .infinity)
            case .failed(let error):
                VStack {
                    DetailTopBar(onBack: { dismiss() })
                    ErrorStateView(error: error) { Task { await load() } }
                    Spacer()
                }
            case .loaded(let e): content(e)
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesMainChrome()
        .task { await load() }
        .sheet(isPresented: $showExternal) {
            if let e = state.value, case .externalBooking(let provider, let url) = e.entry {
                ExternalLinkSheet(provider: provider, url: url) {
                    showExternal = false
                    visitedBookingSite = true
                    openURL(url)
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(item: $conflict) { c in
            ConflictSheet(conflict: c) { option in
                Task {
                    _ = try? await services.plan.resolveConflict(c, with: option)
                    conflict = nil
                    app.planRevision += 1
                    toasts.show(option.id == "later" ? "حُفظت في «محفوظة» دون تغيير الخطة." : "حُدّثت خطتك. الإضافة ليست حجزًا مؤكدًا.")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func content(_ e: ExpoEvent) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotoView(name: e.photo, label: e.title)
                    .overlay(Color.black.opacity(0.3))
                    .frame(height: 330)
                    .clipped()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 6) {
                        if case .externalBooking = e.entry {
                            DetailTag(text: "يتطلب حجزًا خارجيًا", foreground: .statusInfo, background: .statusInfoBg)
                        } else {
                            DetailTag(text: e.entry.title, foreground: .statusSuccess, background: .statusSuccessBg)
                        }
                        DetailTag(text: e.axis.title, foreground: .white, background: e.axis.color)
                        if markedBooked {
                            DetailTag(text: "✓ حجز مؤكد (حسب تعليمك)", foreground: .statusSuccess, background: .statusSuccessBg)
                        }
                    }
                    Text(e.title).textStyle(.title1).foregroundStyle(Color.textPrimary)
                    Text("الجهة: \(e.organizer) · \(e.format)").textStyle(.subhead).foregroundStyle(Color.textSecondary)

                    if let capacity = e.capacity {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("المقاعد: \(capacity) مقعدًا").font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
                            FreshnessLine(status: LiveStatus(crowd: .unknown, updatedMinutesAgo: 2))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))
                    }

                    FactGrid(facts: [
                        Fact(icon: .clock, label: "المدة", value: "\(e.durationMinutes) دقيقة"),
                        Fact(icon: .clock, label: "الموعد", value: e.timeRange),
                        Fact(icon: .door, label: "المكان", value: e.venue),
                        Fact(icon: .globe, label: "اللغة", value: e.language),
                    ])

                    DetailSection(title: "عن الفعالية") {
                        Text(e.about).textStyle(.body).foregroundStyle(Color.textSecondary)
                    }
                    if !e.takeaways.isEmpty {
                        DetailSection(title: "ماذا ستستفيد؟") {
                            ForEach(e.takeaways, id: \.self) { BulletRow(text: $0, icon: .check, color: .brandPrimary) }
                        }
                    }
                    if !e.attendanceRules.isEmpty {
                        DetailSection(title: "شروط الحضور") {
                            ForEach(e.attendanceRules, id: \.self) { BulletRow(text: $0, icon: .info, color: .textSecondary) }
                        }
                    }
                    if !e.accessibility.isEmpty {
                        DetailSection(title: "الإتاحة") {
                            AccessibilityCard(items: e.accessibility, verifiedOn: e.accessibilityVerifiedOn)
                        }
                    }
                    if visitedBookingSite && !markedBooked {
                        StatusBanner(text: "رجعت من موقع الحجز؟ لا نعرف النتيجة تلقائيًا.", tone: .info,
                                     actionTitle: "علّمه كحجز مؤكد") { markedBooked = true }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .background(Color.bgSurface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
                .padding(.top, -28)
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            DetailTopBar(shareText: "\(e.title) — \(e.start.arabic12h) في إكسبو 2030 الرياض.", onBack: { dismiss() })
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    Button("أضف إلى خطتي") { Task { await add(e) } }
                        .appButton(.primary, isLoading: isAdding)
                    if case .externalBooking = e.entry {
                        Button("انتقل للحجز") { showExternal = true }.appButton(.mint)
                    }
                }
                Text("الحجز يتم في موقع الجهة المنظمة. الإضافة للخطة ليست حجزًا مؤكدًا.")
                    .textStyle(.caption).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @MainActor private func load() async {
        state = .loading
        do { state = .loaded(try await services.catalog.event(id: eventId)) }
        catch let error as AppError { state = .failed(error) } catch { state = .failed(.unknown) }
    }

    @MainActor private func add(_ e: ExpoEvent) async {
        isAdding = true
        defer { isAdding = false }
        do {
            switch try await services.plan.add(itemId: e.id) {
            case .added(let position, _):
                app.planRevision += 1
                toasts.show("أُضيف للخطة كمحطة \(position) · ليس حجزًا مؤكدًا")
            case .conflict(let c):
                conflict = c
            }
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }
}

// MARK: - Sheets

/// Figma «Conflict sheet» (1:12870).
struct ConflictSheet: View {
    let conflict: PlanConflict
    var onResolve: (ConflictOption) -> Void

    @State private var selectedId: String = ""
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetGrabber()
            Text(conflict.title).textStyle(.title3).foregroundStyle(Color.textPrimary)
            Text(conflict.message).textStyle(.body).foregroundStyle(Color.textSecondary)
            ForEach(conflict.options) { option in
                let isSelected = option.id == selectedId
                Button {
                    selectedId = option.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(option.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                            if option.isSuggested {
                                Tag(text: "مقترح", background: .brandPrimary)
                            }
                        }
                        Text(option.detail).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(isSelected ? Color.brandMint : Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isSelected ? Color.brandPrimary : Color.borderDefault, lineWidth: isSelected ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Button("معاينة التغيير") {
                guard let option = conflict.options.first(where: { $0.id == selectedId }) else { return }
                isApplying = true
                onResolve(option)
            }
            .appButton(.primary, isLoading: isApplying)
            .disabled(selectedId.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .onAppear { selectedId = conflict.options.first(where: \.isSuggested)?.id ?? "" }
    }
}

/// Figma «External link sheet» (1:12860). Opening the organiser's site is a real external link;
/// the app never learns the booking result.
struct ExternalLinkSheet: View {
    let provider: String
    let url: URL
    var onContinue: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetGrabber()
            Icon(.link, size: 26, color: .statusInfo)
                .frame(width: 56, height: 56)
                .background(Color.statusInfoBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("ستنتقل إلى موقع الجهة المنظمة").textStyle(.title3).foregroundStyle(Color.textPrimary)
            Text("الحجز وتأكيده يتمان لدى «\(provider)». لن نعرف نتيجة الحجز تلقائيًا؛ بعد العودة يمكنك تعليمها كـ«حجز مؤكد».")
                .textStyle(.body).foregroundStyle(Color.textSecondary)
            Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(AppFont.latin(13, .regular)).foregroundStyle(Color.textTertiary)
                .environment(\.layoutDirection, .leftToRight)
            Button("متابعة إلى الموقع", action: onContinue).appButton(.primary)
            Button("إلغاء") { dismiss() }.appButton(.text)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Shared detail pieces

/// Glass back / save / share buttons over the hero photo (Navigation Bar «Over Image»).
struct DetailTopBar: View {
    var isSaved: Bool? = nil
    var shareText: String? = nil
    var onBack: () -> Void
    var onSave: (() -> Void)? = nil

    var body: some View {
        HStack {
            GlassIconButton(icon: .chevronRight, size: 44, iconSize: 24, accessibilityLabel: "رجوع", action: onBack)
            Spacer()
            if let isSaved, let onSave {
                GlassIconButton(icon: .heart, size: 44, iconColor: isSaved ? .crowdHigh : .textPrimary,
                                accessibilityLabel: isSaved ? "إزالة من المحفوظة" : "حفظ", action: onSave)
            }
            if let shareText {
                ShareLink(item: shareText) {
                    Icon(.share, size: 22, color: .textPrimary)
                        .frame(width: 44, height: 44)
                        .glassBackground(Circle(), tint: .glassTint, stroke: .borderDefault)
                        .glassShadow()
                }
                .accessibilityLabel("مشاركة")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct DetailTag: View {
    let text: String
    var foreground: Color
    var background: Color
    var body: some View {
        Text(text).textStyle(.caption).foregroundStyle(foreground)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(background, in: Capsule())
    }
}

struct Fact: Hashable {
    let icon: AppIcon
    let label: String
    let value: String
}

/// 2 × 2 grid of fact tiles (bg/surface-2, radius 16).
struct FactGrid: View {
    let facts: [Fact]
    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { i in
                GridRow {
                    tile(facts[i])
                    if i + 1 < facts.count { tile(facts[i + 1]) }
                }
            }
        }
    }

    private func tile(_ f: Fact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Icon(f.icon, size: 14, color: .textTertiary)
                Text(f.label).textStyle(.caption).foregroundStyle(Color.textTertiary)
            }
            Text(f.value).font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).textStyle(.title3).foregroundStyle(Color.textPrimary).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

struct BulletRow: View {
    let text: String
    var icon: AppIcon
    var color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(icon, size: 18, color: color).padding(.top, 4)
            Text(text).textStyle(.body).foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// «الإتاحة» card: ✓ available, ✕ not available, ⓘ «لا تتوفر معلومة»; verification line.
struct AccessibilityCard: View {
    let items: [AccessibilityFeature]
    let verifiedOn: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    switch item.available {
                    case .some(true): Icon(.check, size: 18, color: .statusSuccess)
                    case .some(false): Icon(.close, size: 18, color: .statusError)
                    case .none: Icon(.info, size: 18, color: .textTertiary)
                    }
                    Text(item.title).textStyle(.subhead)
                        .foregroundStyle(item.available == nil ? Color.textTertiary : Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
            Text("موثّق من الجهة المشاركة · \(verifiedOn)").textStyle(.caption).foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))
    }
}

struct SecondaryActionLabel: View {
    let icon: AppIcon
    let title: String
    var body: some View {
        VStack(spacing: 4) {
            Icon(icon, size: 22, color: .textPrimary)
            Text(title).textStyle(.caption).foregroundStyle(Color.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SecondaryAction: View {
    let icon: AppIcon
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { SecondaryActionLabel(icon: icon, title: title) }
            .buttonStyle(.plain)
    }
}
