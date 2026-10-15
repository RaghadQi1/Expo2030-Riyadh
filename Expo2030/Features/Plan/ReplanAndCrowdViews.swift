import SwiftUI

/// 09.05 «خطة معدّلة مقترحة» — reason banner, diff, impact, the plan after the change; reject / adopt.
struct ReplanView: View {
    let proposal: ReplanProposal
    var onDone: (_ applied: Bool) -> Void

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @State private var isApplying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StatusBanner(text: proposal.reason.bannerText, tone: .info)
                Text("ما الذي تغيّر").textStyle(.title3).foregroundStyle(Color.textPrimary)
                ForEach(proposal.diff) { DiffRow(item: $0) }
                Text("الأثر").textStyle(.title3).foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    ForEach(proposal.impact) { ImpactTile(metric: $0) }
                }
                Text("بعد التعديل").textStyle(.title3).foregroundStyle(Color.textPrimary)
                VStack(spacing: 12) {
                    ForEach(Array(proposal.after.steps.enumerated()), id: \.element.id) { index, step in
                        PlanTimelineRow(step: step, isLast: index == proposal.after.steps.count - 1)
                    }
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    Button("اعتماد التعديل") { Task { await apply() } }
                        .appButton(.primary, isLoading: isApplying)
                    Button("رفض") { onDone(false) }
                        .appButton(.tertiary)
                }
                Text("يمكنك التراجع خلال 10 دقائق من «خطتي».")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .appNavigationChrome(title: "خطة معدّلة مقترحة")
        .hidesMainChrome()
    }

    @MainActor
    private func apply() async {
        isApplying = true
        defer { isApplying = false }
        do {
            _ = try await services.plan.apply(proposal)
            toasts.show("حُدّثت خطتك. يمكنك التراجع خلال 10 دقائق.")
            onDone(true)
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }
}

// MARK: - 09.07 Crowded pavilion → 3 alternatives

struct CrowdAlternativesView: View {
    let situation: CrowdSituation
    var onPreview: (CrowdAlternative) -> Void
    var onChoose: (CrowdAlternative) -> Void
    var onKeepOriginal: () -> Void
    var onPostpone: () -> Void

    @State private var choosingId: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            SiteMapView(center: MapPoint(x: 470, y: 360),
                        pins: [SitePin(id: situation.pavilion.id, name: situation.pavilion.shortName,
                                       point: situation.pavilion.sitePoint, state: .crowded)],
                        routes: [SiteRoute(id: "r", points: [MapPoint(x: 430, y: 300), MapPoint(x: 470, y: 330),
                                                              situation.pavilion.sitePoint])],
                        user: MapPoint(x: 430, y: 300))
                .ignoresSafeArea()

            sheet
        }
        .toolbar(.visible, for: .navigationBar)
        .appNavigationChrome(title: "")
        .hidesMainChrome()
    }

    private var sheet: some View {
        VStack(spacing: 12) {
            SheetGrabber()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Icon(.users, size: 22, color: .crowdHigh)
                        .frame(width: 44, height: 44)
                        .background(Color.crowdHighBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("الجناح القادم مزدحم").textStyle(.title3).foregroundStyle(Color.textPrimary)
                        Text("هذه بدائل تناسبك — أو أكمل كما خططت.").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(situation.title).font(AppFont.arabic(12, .medium)).foregroundStyle(Color.textPrimary)
                        HStack(spacing: 6) {
                            CrowdBadge(level: .high)
                            Text("انتظار ~\(situation.waitMinutes) د").textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Icon(.refresh, size: 13, color: .statusSuccess)
                        Text(situation.freshnessText).textStyle(.caption2).foregroundStyle(Color.statusSuccess)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(situation.alternatives) { alt in
                        AlternativeCard(alternative: alt, total: situation.alternatives.count,
                                        isChoosing: choosingId == alt.id,
                                        onPreview: { onPreview(alt) },
                                        onChoose: {
                                            choosingId = alt.id
                                            onChoose(alt)
                                        })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                Button("أجّل الأصلي", action: onPostpone).appButton(.mint)
                Button("أكمل إلى الأصلي", action: onKeepOriginal).appButton(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .background(Color.bgSurface, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .shadow(color: Color.shadowTint.opacity(0.12), radius: 12, y: -4)
    }
}

/// Figma «Card/Alternative Pavilion» (1:4013), 300 pt wide.
struct AlternativeCard: View {
    let alternative: CrowdAlternative
    let total: Int
    var isChoosing = false
    var onPreview: () -> Void
    var onChoose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                PhotoView(name: alternative.photo)
                    .overlay(Color.black.opacity(0.15))
                    .frame(height: 118)
                Text("بديل \(alternative.rank) من \(total)").textStyle(.caption).foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.bgSurfaceTranslucent, in: Capsule())
                    .padding(12)
            }
            .frame(height: 118)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(alternative.pavilion.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                Text(alternative.whyText).textStyle(.footnote).foregroundStyle(Color.brandPrimary)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        metric(.walk, "\(alternative.walkMinutes) د مشيًا")
                        metric(.clock, "المدة \(alternative.durationMinutes) د")
                    }
                    GridRow {
                        metric(.warning, alternative.crowd == .unknown ? "الازدحام: غير معروف" : alternative.crowd.badgeTitle,
                               muted: alternative.crowd == .unknown)
                        metric(.clock, alternative.waitText, muted: alternative.waitText.contains("غير معروف"))
                    }
                    GridRow {
                        metric(.check, alternative.entryText)
                        metric(.info, alternative.languages)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("الأثر على خطتك").textStyle(.caption2).foregroundStyle(Color.textTertiary)
                    Text(alternative.planImpact).textStyle(.caption).foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 4) {
                    Icon(alternative.isStale ? .clock : .refresh, size: 13,
                         color: alternative.isStale ? .statusWarning : .statusSuccess)
                    Text(alternative.freshnessText).textStyle(.caption2)
                        .foregroundStyle(alternative.isStale ? Color.statusWarning : Color.statusSuccess)
                }
                HStack(spacing: 8) {
                    Button(action: onChoose) {
                        Group {
                            if isChoosing { ProgressView().tint(.white) } else { Text("اختر هذا الجناح") }
                        }
                        .font(AppFont.arabic(12, .medium))
                        .foregroundStyle(Color.brandOnPrimary)
                        .frame(maxWidth: .infinity, minHeight: 47)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button(action: onPreview) {
                        Text("معاينة").font(AppFont.arabic(12, .medium)).foregroundStyle(Color.brandPrimary)
                            .frame(maxWidth: .infinity, minHeight: 47)
                            .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .cardShadow()
        .accessibilityElement(children: .contain)
    }

    private func metric(_ icon: AppIcon, _ text: String, muted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 14, color: muted ? .textTertiary : .textSecondary)
            Text(text).textStyle(.caption).foregroundStyle(muted ? Color.textTertiary : Color.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 09.08 «معاينة: … بدل المدن الذكية» — new route on the site map + the changed timeline.
struct AlternativePreviewView: View {
    let alternative: CrowdAlternative
    var onBack: () -> Void
    var onConfirm: () -> Void

    @State private var confirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SiteMapView(center: MapPoint(x: 480, y: 290),
                            pins: [SitePin(id: "p2", name: "المدن الذكية", point: MapPoint(x: 520, y: 360), state: .crowded),
                                   SitePin(id: alternative.pavilion.id, name: alternative.pavilion.shortName,
                                           point: alternative.pavilion.sitePoint, state: .selected)],
                            routes: [SiteRoute(id: "old", points: [MapPoint(x: 430, y: 300), MapPoint(x: 520, y: 360)], isFaded: true),
                                     SiteRoute(id: "new", points: [MapPoint(x: 430, y: 300), MapPoint(x: 500, y: 270),
                                                                    alternative.pavilion.sitePoint])],
                            user: MapPoint(x: 430, y: 300))
                    .frame(height: 360)
                    .padding(.horizontal, -Spacing.screen)

                Text("معاينة: \(alternative.pavilion.name.replacingOccurrences(of: " والاستكشاف", with: "")) بدل المدن الذكية")
                    .textStyle(.title3).foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    previewMetric("الوصول", alternative.arrival.arabic12h)
                    previewMetric("المسافة", "\(alternative.distanceMeters) م")
                    previewMetric("المشي", "\(alternative.walkMinutes) د")
                }
                VStack(spacing: 12) {
                    PlanTimelineRow(step: PlanStep(id: "a", time: alternative.arrival, kind: .experience(placeId: alternative.pavilion.id),
                                                   title: alternative.pavilion.name, subtitle: alternative.previewSubtitle,
                                                   change: .new(reason: "بديل عن المدن الذكية")))
                    PlanTimelineRow(step: PlanStep(id: "b", time: TimeOfDay(16, 30), kind: .experience(placeId: "e-robot-workshop"),
                                                   title: "ورشة «ابنِ روبوتك الأول»", isPriority: true))
                    PlanTimelineRow(step: PlanStep(id: "c", time: TimeOfDay(17, 18), kind: .experience(placeId: "e-city-2050"),
                                                   title: "المدن الذكية (مؤجَّل)", subtitle: "5:18 م · 12 د · قد يبقى مزدحمًا",
                                                   change: .new(reason: "أُجّل بسبب الازدحام")), isLast: true)
                }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.bottom, 24)
        }
        .background(Color.bgCanvas)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    Button("تأكيد الاستبدال") {
                        confirming = true
                        onConfirm()
                    }
                    .appButton(.primary, isLoading: confirming)
                    Button("رجوع للبدائل", action: onBack).appButton(.tertiary)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .hidesMainChrome()
    }

    private func previewMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).textStyle(.caption2).foregroundStyle(Color.textTertiary)
            Text(value).textStyle(.headline).foregroundStyle(Color.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// «أضف محطة» — pick a pavilion or event to add (not a booking). Conflicts open the conflict sheet.
struct AddStopSheet: View {
    var onAdded: () -> Void
    var onProposed: ((ReplanProposal) -> Void)? = nil

    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var state: Loadable<([Pavilion], [ExpoEvent])> = .idle
    @State private var conflict: PlanConflict?
    @State private var busyId: String?
    @State private var aiMode = false
    @State private var aiCandidates: [PriorityCandidate] = []

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .loading: LoadingStateView()
                case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
                case .loaded(let (pavilions, events)):
                    List {
                        if aiMode {
                            Section("محطات مناسبة لوقت زيارتك · من بيانات إكسبو") {
                                ForEach(aiCandidates) { candidate in
                                    row(id: candidate.id, title: candidate.title, subtitle: candidate.subtitle)
                                }
                            }
                        } else {
                        Section("فعاليات قادمة") {
                            ForEach(events) { e in row(id: e.id, title: e.title, subtitle: "\(e.start.arabic12h) · \(e.venue)") }
                        }
                        Section("الأجنحة") {
                            ForEach(pavilions) { p in row(id: p.id, title: p.name, subtitle: "\(p.axis.title) · \(p.experienceType)") }
                        }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .appNavigationChrome(title: "أضف محطة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
        }
        .task { await load() }
        .sheet(item: $conflict) { c in
            ConflictSheet(conflict: c) { option in
                Task {
                    _ = try? await services.plan.resolveConflict(c, with: option)
                    conflict = nil
                    onAdded()
                    dismiss()
                    toasts.show(option.id == "later" ? "حُفظ في «رحلتي» دون تغيير الخطة." : "حُدّثت خطتك. الإضافة ليست حجزًا مؤكدًا.")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func row(id: String, title: String, subtitle: String) -> some View {
        Button {
            Task { await add(id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.bodyStrong).foregroundStyle(Color.textPrimary)
                    Text(subtitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if busyId == id { ProgressView() } else { Icon(.plus, size: 20, color: .brandPrimary) }
            }
        }
    }

    @MainActor private func load() async {
        state = .loading
        do {
            if let plan = try await services.plan.currentPlan(), plan.id.hasPrefix("plan-gemini-") {
                aiMode = true
                aiCandidates = try await services.plan.addCandidates()
                state = .loaded(([], []))
            } else {
                aiMode = false
                async let p = services.catalog.pavilions(filters: SearchFilters())
                async let e = services.catalog.events()
                state = .loaded(try await (p, e))
            }
        } catch let error as AppError { state = .failed(error) } catch { state = .failed(.unknown) }
    }

    @MainActor private func add(_ id: String) async {
        busyId = id
        defer { busyId = nil }
        do {
            if aiMode {
                let proposal = try await services.plan.proposeReplan(.addedItem(title: id))
                onProposed?(proposal) // visitor reviews and confirms before SQLite changes
                dismiss()
                return
            }
            switch try await services.plan.add(itemId: id) {
            case .added(let position, let time):
                toasts.show("أُضيف للخطة كمحطة \(position) · \(time.arabic12h) · ليس حجزًا مؤكدًا")
                onAdded()
                dismiss()
            case .conflict(let c):
                conflict = c
            }
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }
}
