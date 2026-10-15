import SwiftUI

// MARK: - View-layer icons for the personalization models

extension VisitGoal {
    var icon: AppIcon {
        switch self {
        case .explore: .compass
        case .learn: .star
        case .handsOn: .sparkles
        case .family: .users
        case .networking: .briefcase
        }
    }
}

extension ExpoAxis {
    var icon: AppIcon {
        switch self {
        case .tech: .sparkles
        case .earth: .droplet
        case .human: .user
        case .culture: .star
        case .coop: .users
        }
    }

    var color: Color {
        switch self {
        case .tech: .axisTech
        case .earth: .axisEarth
        case .human: .axisHuman
        case .culture: .axisCulture
        case .coop: .axisCoop
        }
    }
}

extension TimeBudget {
    var icon: AppIcon { self == .custom ? .note : .clock }
}

extension ComfortPreference {
    var icon: AppIcon {
        switch self {
        case .lessWalking: .walk
        case .regularBreaks: .coffee
        case .stepFree: .accessible
        case .quietPlaces: .volume
        }
    }
}

// MARK: - Flow

/// 07.01 – 07.06 personalization, 07.07 generating, 07.08 cancel alert and 09.01 plan comparison.
/// Shown as the `.personalization` phase after sign-up, or as a full-screen cover from «خطتي».
struct PersonalizationFlowView: View {
    /// When presented from inside the app; nil = app phase (finishes into the main tabs).
    var onClose: (() -> Void)? = nil

    enum Step: Int, CaseIterable {
        case goal = 1, interests, time, comfort, priority, review
        var label: String {
            switch self {
            case .goal: "الهدف"
            case .interests: "الاهتمامات"
            case .time: "الوقت"
            case .comfort: "الراحة"
            case .priority: "الأولوية"
            case .review: "المراجعة"
            }
        }
    }

    enum Stage: Equatable { case questions, generating, compare([PlanOption]) }

    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts

    @State private var step: Step = .goal
    @State private var stage: Stage = .questions
    @State private var prefs = PlanPreferences()
    @State private var expandedAxis: ExpoAxis?
    @State private var candidates: [PriorityCandidate] = []
    @State private var prioritySearch = ""
    @State private var generationStage: PlanGenerationStage = .readingPreferences
    @State private var generationTask: Task<Void, Never>?
    @State private var showCancelAlert = false
    @State private var generationError: AppError?
    @State private var cameFromReview = false

    var body: some View {
        Group {
            switch stage {
            case .questions:
                questions
            case .generating:
                generating
            case .compare(let options):
                NavigationStack {
                    PlanCompareView(options: options) { chosen in
                        await adopt(chosen)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { stage = .questions; step = .review } label: {
                                Icon(.chevronRight, size: 24, color: .textPrimary)
                            }
                            .accessibilityLabel("رجوع")
                        }
                    }
                }
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .alert("إيقاف تكوين الخطة؟", isPresented: $showCancelAlert) {
            Button("متابعة التكوين", role: .cancel) {}
            Button("إيقاف", role: .destructive) { cancelGeneration() }
        } message: {
            Text("اختياراتك محفوظة، ويمكنك المتابعة لاحقًا من «خطتي».")
        }
        .task { candidates = (try? await services.catalog.priorityCandidates()) ?? [] }
    }

    // MARK: Questions (07.01 – 07.06)

    private var questions: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).textStyle(.title1).foregroundStyle(Color.textPrimary)
                    Text(subtitle).textStyle(.subhead).foregroundStyle(Color.textSecondary)
                    stepContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            bottomCTA
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: back) {
                    Icon(.chevronRight, size: 24, color: .textPrimary).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("رجوع")
                Spacer()
                Text("\(step.rawValue) من 6 · \(step.label)").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                Spacer()
                Button("تخطي") { skipAll() }
                    .font(AppFont.arabic(12, .medium))
                    .foregroundStyle(Color.textLink)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("يتخطى التخصيص ويفتح الرئيسية")
            }
            HStack(spacing: 4) {
                ForEach(Step.allCases, id: \.self) { s in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(s.rawValue <= step.rawValue ? Color.brandPrimary : Color.borderDefault)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("الخطوة \(step.rawValue) من 6")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(Color.bgCanvasTranslucent)
    }

    private var title: String {
        switch step {
        case .goal: "وش هدف زيارتك اليوم؟"
        case .interests: "وش يهمك؟"
        case .time: "كم وقتك اليوم؟"
        case .comfort: "وش يريحك أثناء الزيارة؟"
        case .priority: "تجربة ما تبغى تفوتك؟"
        case .review: "راجع اختياراتك"
        }
    }

    private var subtitle: String {
        switch step {
        case .goal: "اختر هدفًا أو هدفين، وتقدر تغيّرها لاحقًا."
        case .interests: "المحاور الخمسة لإكسبو. افتح أي محور لاختيارات أدق."
        case .time: "للمدد الجاهزة نبدأ الساعة 3:00 م. لتحديد وقت البداية والنهاية اختر مدة مخصصة."
        case .comfort: "اختياري. نراعيها قدر الإمكان حسب البيانات المتاحة."
        case .priority: "نعرض الفعاليات التي تناسب وقتك، ونتجنب أي تعارض في المواعيد. تقدر تتخطى هذه الخطوة."
        case .review: "اضغط على أي بند لتعديله."
        }
    }

    @ViewBuilder private var stepContent: some View {
        switch step {
        case .goal:
            ForEach(VisitGoal.allCases) { goal in
                OptionCard(title: goal.title, subtitle: goal.subtitle, icon: goal.icon,
                           isSelected: prefs.goals.contains(goal)) {
                    toggle(goal, in: &prefs.goals, max: 2)
                }
            }
        case .interests:
            ForEach(ExpoAxis.allCases) { axis in
                VStack(alignment: .leading, spacing: 10) {
                    OptionCard(title: SubInterests.optionTitle(axis), subtitle: nil, icon: axis.icon,
                               iconBackground: axis.color, iconColor: .white,
                               isSelected: prefs.axes.contains(axis)) {
                        toggle(axis, in: &prefs.axes)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedAxis = prefs.axes.contains(axis) ? axis : nil
                        }
                    }
                    if expandedAxis == axis || (prefs.axes.contains(axis) && !prefs.subInterests.isDisjoint(with: SubInterests.of(axis))) {
                        FlowLayout(spacing: 8) {
                            ForEach(SubInterests.of(axis), id: \.self) { sub in
                                SelectableChip(title: sub, isSelected: prefs.subInterests.contains(sub)) {
                                    toggle(sub, in: &prefs.subInterests)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                    }
                }
            }
        case .time:
            ForEach(TimeBudget.allCases) { budget in
                OptionCard(title: budget.title, subtitle: budget.subtitle, icon: budget.icon,
                           isSelected: prefs.time == budget, isRadio: true) {
                    prefs.time = budget
                    // If the visit window changes later, the backend safely skips old
                    // conflicting pins and explains the omission in the plan preview.
                    if budget == .custom, prefs.customStart == nil {
                        prefs.customStart = TimeOfDay(15, 30)
                        prefs.customEnd = TimeOfDay(17, 30)
                    }
                }
            }
            if prefs.time == .custom {
                CustomTimeRange(start: Binding(get: { prefs.customStart ?? TimeOfDay(15, 30) }, set: { prefs.customStart = $0 }),
                                end: Binding(get: { prefs.customEnd ?? TimeOfDay(17, 30) }, set: { prefs.customEnd = $0 }))
            }
        case .comfort:
            ForEach(ComfortPreference.allCases) { item in
                OptionCard(title: item.title, subtitle: item.subtitle, icon: item.icon,
                           isSelected: prefs.comfort.contains(item)) {
                    toggle(item, in: &prefs.comfort)
                }
            }
        case .priority:
            VStack(alignment: .leading, spacing: 6) {
                Text("ابحث عن فعالية أو جناح").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Icon(.search, size: 20, color: .textTertiary)
                    TextField("مثال: روبوت", text: $prioritySearch)
                        .textStyle(.body)
                        .submitLabel(.search)
                }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(Color.borderDefault))
            }
            let filtered = candidates.filter { c in
                let matchingSearch = prioritySearch.isEmpty || c.title.contains(prioritySearch) || c.subtitle.contains(prioritySearch)
                guard let visitWindow, let start = c.startMinutes, let end = c.endMinutes else { return matchingSearch }
                return matchingSearch && start >= visitWindow.lowerBound && end <= visitWindow.upperBound
            }
            if filtered.isEmpty {
                EmptyStateView(icon: .search, title: "ما فيه فعاليات مناسبة لهذا الوقت", message: "تقدرين تتخطين هذه الخطوة؛ Gemini يقدر يقترح بوثات مفتوحة بدلًا منها.")
            }
            ForEach(filtered) { c in
                OptionCard(title: c.title, subtitle: c.subtitle, icon: .star, iconBackground: .axisCoop, iconColor: .white,
                           isSelected: prefs.mustNotMiss.contains(c.id)) {
                    toggle(c.id, in: &prefs.mustNotMiss)
                }
            }
        case .review:
            reviewList
            Text("لا تحتاج ملفًا مهنيًا لبدء الزيارة — تقدر تنشئه لاحقًا من «حسابي».")
                .font(AppFont.arabic(11, .regular))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 4)
        }
    }

    /// Ready-made budgets start at 3 PM in the simulated event timetable.
    /// Priority cards must use exactly the same window as the Python planner.
    private var visitWindow: ClosedRange<Int>? {
        guard let budget = prefs.time else { return nil }
        let start = budget == .custom ? (prefs.customStart?.minutes ?? 930) : 900
        let end: Int
        switch budget {
        case .oneHour: end = start + 60
        case .twoHours: end = start + 120
        case .halfDay: end = start + 240
        case .custom: end = prefs.customEnd?.minutes ?? (start + 120)
        }
        return start...max(start, end)
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            reviewRow(.goal, icon: .star, value: prefs.goals.isEmpty ? "لم تختر بعد" : VisitGoal.allCases.filter(prefs.goals.contains).map(\.title).joined(separator: "، "))
            Divider().padding(.horizontal, 16)
            reviewRow(.interests, icon: .sparkles, value: interestsSummary)
            Divider().padding(.horizontal, 16)
            reviewRow(.time, icon: .clock, value: timeSummary)
            Divider().padding(.horizontal, 16)
            reviewRow(.comfort, icon: .coffee, value: prefs.comfort.isEmpty ? "بدون تفضيلات" : ComfortPreference.allCases.filter(prefs.comfort.contains).map(\.title).joined(separator: "، "))
            Divider().padding(.horizontal, 16)
            reviewRow(.priority, icon: .star, value: priorityTitle)
        }
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func reviewRow(_ target: Step, icon: AppIcon, value: String) -> some View {
        Button {
            cameFromReview = true
            withAnimation { step = target }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Icon(icon, size: 20, color: .brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.label).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    Text(value).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("تعديل").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    Icon(.chevronLeft, size: 16, color: .textSecondary)
                }
                .padding(.top, 8)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("تعديل \(target.label)")
    }

    private var interestsSummary: String {
        if prefs.axes.isEmpty { return "لم تختر بعد" }
        var parts = ExpoAxis.allCases.filter(prefs.axes.contains).map(\.title)
        if !prefs.subInterests.isEmpty { parts.append("(\(prefs.subInterests.sorted().joined(separator: "، ")))") }
        return parts.joined(separator: "، ")
    }

    private var timeSummary: String {
        guard let t = prefs.time else { return "لم تختر بعد" }
        if t == .custom, let s = prefs.customStart, let e = prefs.customEnd { return "\(s.arabic12h) – \(e.arabic12h)" }
        return "\(t.title) · \(t.subtitle)"
    }

    private var priorityTitle: String {
        let titles = candidates.filter { prefs.mustNotMiss.contains($0.id) }.map(\.title)
        return titles.isEmpty ? "بدون أولوية" : titles.joined(separator: "، ")
    }

    private var canContinue: Bool {
        switch step {
        case .goal: !prefs.goals.isEmpty
        case .interests: !prefs.axes.isEmpty
        case .time: prefs.time != nil
        case .comfort, .priority, .review: true
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            Button(step == .review ? "كوّن خطتي" : (cameFromReview ? "حفظ والعودة للمراجعة" : "التالي")) { next() }
                .buttonStyle(PersonalizationCTAStyle(enabled: canContinue))
                .disabled(!canContinue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.bgCanvasTranslucent.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Generating (07.07)

    private var generating: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)
            GenerationRing(progress: Double(generationStage.rawValue + 1) / Double(PlanGenerationStage.allCases.count))
            Text("نكوّن خطتك…").textStyle(.title2).foregroundStyle(Color.textPrimary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(PlanGenerationStage.allCases, id: \.self) { s in
                    HStack(spacing: 8) {
                        Icon(s.rawValue < generationStage.rawValue ? .check : (s == generationStage ? .refresh : .clock),
                             size: 16,
                             color: s.rawValue < generationStage.rawValue ? .statusSuccess : (s == generationStage ? .brandPrimary : .textTertiary))
                        Text(s.title).textStyle(.footnote)
                            .foregroundStyle(s.rawValue <= generationStage.rawValue ? Color.textPrimary : Color.textTertiary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)
            if let generationError {
                StatusBanner(text: generationError.message, tone: .error, actionTitle: "إعادة المحاولة") { startGeneration() }
                    .padding(.horizontal, 24)
            }
            Text("عادةً يستغرق أقل من 10 ثوانٍ. الترشيحات ليست حجزًا للدخول.")
                .textStyle(.caption).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("إلغاء") { showCancelAlert = true }
                .font(AppFont.arabic(16, .semibold))
                .foregroundStyle(Color.textLink)
                .frame(minHeight: 44)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Actions

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>, max: Int? = nil) {
        if set.contains(value) {
            set.remove(value)
        } else {
            if let max, set.count >= max {
                toasts.show("تقدر تختار هدفين كحد أقصى", icon: .info, iconColor: .statusInfo)
                return
            }
            set.insert(value)
        }
    }

    private func back() {
        if step == .goal {
            if let onClose { onClose() } else { app.finishPersonalization(openPlan: false) }
            return
        }
        withAnimation { step = Step(rawValue: step.rawValue - 1) ?? .goal }
    }

    private func next() {
        if step == .review {
            startGeneration()
            return
        }
        if cameFromReview {
            cameFromReview = false
            withAnimation { step = .review }
            return
        }
        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .review }
    }

    private func skipAll() {
        if let onClose { onClose() } else { app.finishPersonalization(openPlan: false) }
    }

    private func startGeneration() {
        generationError = nil
        generationStage = .readingPreferences
        stage = .generating
        generationTask?.cancel()
        generationTask = Task { @MainActor in
            do {
                let options = try await services.plan.generatePlan(prefs) { s in
                    withAnimation(.easeInOut(duration: 0.3)) { generationStage = s }
                }
                stage = .compare(options)
            } catch is CancellationError {
                // cancelled by the user (07.08)
            } catch let error as AppError {
                generationError = error
            } catch {
                generationError = .unknown
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        stage = .questions
        step = .review
        toasts.show("أوقفنا تكوين الخطة. اختياراتك محفوظة.", icon: .info, iconColor: .statusInfo)
    }

    @MainActor
    private func adopt(_ option: PlanOption) async {
        do {
            _ = try await services.plan.adopt(option)
            app.planRevision += 1
            toasts.show("اعتمدنا «\(option.name)» كخطتك. الترشيحات ليست حجزًا.")
            if let onClose { onClose() } else { app.finishPersonalization(openPlan: true) }
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
        } catch {
            toasts.show("تعذّر حفظ الخطة في قاعدة البيانات. حاولي الاعتماد مرة أخرى.", icon: .warning, iconColor: .statusError)
        }
    }
}

// MARK: - Pieces

/// Personalization option card (Figma «Option/…»): white, 1-pt border, radius 18, 44-pt icon tile on the
/// right, checkbox (or radio) on the left. Selected = mint fill + 2-pt brand border + filled check.
struct OptionCard: View {
    let title: String
    let subtitle: String?
    let icon: AppIcon
    var iconBackground: Color = .brandMint
    var iconColor: Color = .brandPrimary
    var isSelected: Bool
    var isRadio = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Icon(icon, size: 22, color: iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                SelectionIndicator(isSelected: isSelected, isRadio: isRadio)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.brandMint.opacity(0.6) : Color.bgSurface,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color.brandPrimary : Color.borderDefault, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

struct SelectionIndicator: View {
    var isSelected: Bool
    var isRadio = false
    var body: some View {
        ZStack {
            if isRadio {
                Circle().strokeBorder(isSelected ? Color.brandPrimary : Color.borderStrong, lineWidth: 1.5)
                if isSelected { Circle().fill(Color.brandPrimary).padding(5) }
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.brandPrimary : Color.bgSurface)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.brandPrimary : Color.borderStrong, lineWidth: 1.5)
                if isSelected { Icon(.check, size: 16, color: .white) }
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Disabled «التالي» in Figma is #DCE3DE with #6E7D76 text (not the generic 0.38 opacity).
struct PersonalizationCTAStyle: ButtonStyle {
    var enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.arabic(16, .semibold))
            .foregroundStyle(enabled ? Color.brandOnPrimary : Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(enabled ? (configuration.isPressed ? Color.brandPrimaryPressed : Color.brandPrimary) : Color.borderDefault,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

private struct CustomTimeRange: View {
    @Binding var start: TimeOfDay
    @Binding var end: TimeOfDay

    var body: some View {
        HStack(spacing: 12) {
            picker("البداية", time: $start)
            picker("النهاية", time: $end)
        }
        .padding(16)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        if end <= start {
            StatusBanner(text: "وقت النهاية يجب أن يكون بعد البداية.", tone: .error)
        }
    }

    private func picker(_ label: String, time: Binding<TimeOfDay>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).textStyle(.footnote).foregroundStyle(Color.textSecondary)
            DatePicker(label, selection: Binding(
                get: { Calendar.current.date(bySettingHour: time.wrappedValue.hour, minute: time.wrappedValue.minute, second: 0, of: Date()) ?? Date() },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    time.wrappedValue = TimeOfDay(c.hour ?? 0, c.minute ?? 0)
                }), displayedComponents: .hourAndMinute)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 07.07 progress ring: mint track, brand arc, sparkles in the centre.
struct GenerationRing: View {
    var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.brandMint, lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: progress)
            Icon(.sparkles, size: 40, color: .brandPrimary)
        }
        .frame(width: 120, height: 120)
        .accessibilityElement()
        .accessibilityLabel("نكوّن خطتك")
        .accessibilityValue("\(Int(progress * 100)) بالمئة")
    }
}
