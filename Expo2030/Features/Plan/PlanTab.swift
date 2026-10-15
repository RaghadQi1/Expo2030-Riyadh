import SwiftUI

/// Detail screens reachable from several tabs.
enum DetailRoute: Hashable {
    case pavilion(String)
    case event(String)
}

extension View {
    func detailDestinations() -> some View {
        navigationDestination(for: DetailRoute.self) { route in
            switch route {
            case .pavilion(let id): PavilionDetailView(pavilionId: id)
            case .event(let id): EventDetailView(eventId: id)
            }
        }
    }
}

enum PlanRoute: Hashable {
    case replan(ReplanProposal)
    case crowd(CrowdSituation)
    case alternativePreview(CrowdAlternative, CrowdSituation)
}

/// «خطتي» tab — 09.02 timeline with live step, plan actions, replanning (09.05), crowded alternatives
/// (09.07 – 09.09) and undo.
struct PlanTab: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var path = NavigationPath()
    @State private var state: Loadable<Plan?> = .idle
    @State private var crowd: CrowdSituation?
    @State private var showPersonalization = false
    @State private var showFinishConfirm = false
    @State private var showAddStop = false
    @State private var busyAction: String?
    @State private var undoVisible = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Color.bgCanvas.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PlanRoute.self) { route in
                    switch route {
                    case .replan(let proposal):
                        ReplanView(proposal: proposal) { applied in
                            path.removeLast()
                            if applied { app.planRevision += 1 }
                        }
                    case .crowd(let situation):
                        CrowdAlternativesView(situation: situation,
                                              onPreview: { alt in path.append(PlanRoute.alternativePreview(alt, situation)) },
                                              onChoose: { alt in Task { await swap(to: alt) } },
                                              onKeepOriginal: { path.removeLast() },
                                              onPostpone: { Task { await postpone() } })
                    case .alternativePreview(let alt, _):
                        AlternativePreviewView(alternative: alt,
                                               onBack: { path.removeLast() },
                                               onConfirm: { Task { await swap(to: alt) } })
                    }
                }
                .detailDestinations()
        }
        .task(id: app.planRevision) { await load() }
        .fullScreenCover(isPresented: $showPersonalization) {
            PersonalizationFlowView { showPersonalization = false }
        }
        .sheet(isPresented: $showAddStop) {
            AddStopSheet(onAdded: { Task { await load() } }, onProposed: { proposal in
                showAddStop = false
                Task { @MainActor in
                    // Present the review screen after the selection sheet closes.
                    try? await Task.sleep(for: .milliseconds(350))
                    path.append(PlanRoute.replan(proposal))
                }
            })
        }
        .alert("إنهاء زيارتك اليوم؟", isPresented: $showFinishConfirm) {
            Button("متابعة الزيارة", role: .cancel) {}
            Button("إنهاء الزيارة", role: .destructive) { Task { await finishVisit() } }
        } message: {
            Text("نحفظ ما زرته وملاحظاتك في «رحلتي»، ونوقف التنبيهات المرتبطة بالخطة.")
        }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView(title: "نحمّل خطتك…").frame(maxHeight: .infinity)
        case .failed(let error):
            ErrorStateView(error: error) { Task { await load() } }.frame(maxHeight: .infinity)
        case .loaded(nil):
            emptyState
        case .loaded(let plan?):
            planView(plan)
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("خطتي").textStyle(.largeTitle).foregroundStyle(Color.textPrimary)
                EmptyStateView(icon: .plan, title: "ما عندك خطة بعد",
                               message: "أجب عن ست أسئلة قصيرة ونكوّن لك خطة تناسب وقتك واهتماماتك. الترشيحات ليست حجزًا للدخول.",
                               actionTitle: "كوّن خطتي") { showPersonalization = true }
                    .padding(.top, 40)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 8)
        }
        .tabBarSafeArea()
    }

    private func planView(_ plan: Plan) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                summaryCard(plan)
                actions
                if let crowd {
                    StatusBanner(text: "الجناح القادم مزدحم: \(crowd.title) · انتظار ~\(crowd.waitMinutes) د",
                                 tone: .warning, icon: .users, actionTitle: "البدائل") {
                        path.append(PlanRoute.crowd(crowd))
                    }
                }
                VStack(spacing: 12) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        PlanTimelineRow(step: step, isLast: index == plan.steps.count - 1,
                                        onTap: detailAction(for: step))
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 4)
        }
        .refreshable { await load() }
        .tabBarSafeArea()
        .overlay(alignment: .bottom) {
            if let description = plan.lastChangeDescription, undoVisible,
               let until = plan.undoAvailableUntil, until > Date() {
                UndoBar(text: description) { Task { await undo() } }
                    .padding(.horizontal, Spacing.screen)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var header: some View {
        HStack {
            Text("خطتي").textStyle(.largeTitle).foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            ActionPill(title: "تعديل", icon: .note, style: .mint) { showPersonalization = true }
                .accessibilityHint("يعيد أسئلة التخصيص ويكوّن خطة جديدة")
        }
    }

    private func summaryCard(_ plan: Plan) -> some View {
        let experiences = plan.experiences
        let current = (experiences.firstIndex { $0.liveState == .active } ?? 0) + 1
        let walking = estimatedWalkingMinutes(plan)
        let priority = plan.steps.first { $0.isPriority }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                Spacer()
                Text("المحطة \(current) من \(experiences.count) · تنتهي \(plan.endsAt.arabic12h)")
                    .textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
            HStack(spacing: 6) {
                InfoPill(text: "\(walking) د مشي")
                InfoPill(text: "\(experienceMinutes(plan)) د تجارب")
                if let priority { InfoPill(text: "★ ورشة \(priority.time.shortTime)") }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .cardBackground(radius: 20)
        .accessibilityElement(children: .combine)
    }

    private func estimatedWalkingMinutes(_ plan: Plan) -> Int {
        max(0, plan.experiences.count - 1) * 5
    }

    private func experienceMinutes(_ plan: Plan) -> Int {
        // Experience duration = gap to the next step (demo approximation; the API returns it explicitly).
        var total = 0
        for (i, step) in plan.steps.enumerated() {
            guard case .experience = step.kind else { continue }
            let next = i + 1 < plan.steps.count ? plan.steps[i + 1].time : plan.endsAt
            total += max(0, next.minutes - step.time.minutes)
        }
        return total
    }

    private var actions: some View {
        FlowLayout(spacing: 8) {
            ActionPill(title: "تأخرت", icon: .clock) { Task { await replan(.late(minutes: 20), key: "late") } }
            ActionPill(title: "أنهي زيارتي", icon: .flag) { showFinishConfirm = true }
            ActionPill(title: "أضف محطة", icon: .plus) { showAddStop = true }
        }
        .overlay {
            if busyAction != nil {
                ProgressView().tint(.brandPrimary)
                    .padding(8)
                    .background(Color.bgSurface, in: Circle())
                    .accessibilityLabel("جارٍ تجهيز خطة معدّلة")
            }
        }
        .disabled(busyAction != nil)
    }

    private func detailAction(for step: PlanStep) -> (() -> Void)? {
        guard case .experience(let id) = step.kind else { return nil }
        // AI events use backend IDs (E001...) and do not exist in the mock detail catalog.
        // Keep them visible on the timeline instead of navigating to a wrong detail page.
        if id.hasPrefix("E"), id.dropFirst().allSatisfy({ $0.isNumber }) { return nil }
        return {
            if id.hasPrefix("e-") { path.append(DetailRoute.event(id)) } else { path.append(DetailRoute.pavilion(id)) }
        }
    }

    // MARK: Data

    @MainActor
    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let plan = try await services.plan.currentPlan()
            withAnimation { state = .loaded(plan) }
            crowd = plan == nil ? nil : try? await services.plan.crowdSituation()
            if let p = plan, p.undoAvailableUntil.map({ $0 > Date() }) == true {
                withAnimation { undoVisible = true }
                try? await Task.sleep(for: .seconds(8))
                withAnimation { undoVisible = false }
            }
        } catch let error as AppError {
            state = .failed(error)
        } catch {
            state = .failed(.unknown)
        }
    }

    @MainActor
    private func replan(_ reason: ReplanReason, key: String) async {
        busyAction = key
        defer { busyAction = nil }
        do {
            let proposal = try await services.plan.proposeReplan(reason)
            path.append(PlanRoute.replan(proposal))
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }

    @MainActor
    private func swap(to alternative: CrowdAlternative) async {
        do {
            _ = try await services.plan.swap(to: alternative)
            path = NavigationPath()
            app.planRevision += 1
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }

    @MainActor
    private func postpone() async {
        do {
            _ = try await services.plan.postponeCrowded()
            path = NavigationPath()
            app.planRevision += 1
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }

    @MainActor
    private func undo() async {
        do {
            _ = try await services.plan.undoLastChange()
            undoVisible = false
            toasts.show("تراجعنا عن آخر تعديل.", icon: .undo, iconColor: .brandPrimary)
            await load()
        } catch {
            toasts.show("انتهت مهلة التراجع.", icon: .info, iconColor: .statusInfo)
        }
    }

    @MainActor
    private func finishVisit() async {
        do {
            try await services.plan.finishVisit()
            app.planRevision += 1
            toasts.show("انتهت زيارتك. تجد ما زرته وملاحظاتك في «رحلتي».", actionTitle: "رحلتي") {
                app.selectedTab = .journey
            }
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {}
    }
}

/// 09.09 floating undo bar: «حُدّثت خطتك · … » + «تراجع».
struct UndoBar: View {
    let text: String
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Icon(.undo, size: 20, color: .textPrimary)
            Text(text).textStyle(.footnote).foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("تراجع", action: onUndo)
                .font(AppFont.arabic(13, .medium))
                .foregroundStyle(Color.textLink)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(Color.bgSurface, in: Capsule())
        .glassShadow()
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "تراجع", onUndo)
    }
}
