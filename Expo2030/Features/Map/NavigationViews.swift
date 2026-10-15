import SwiftUI

// MARK: - Instruction card (2.6 – 2.11, 3.11, 5.10, 6.7)

/// Glass card at the top during turn-by-turn guidance, or the rerouting banner (2.10).
struct NavigationTopCard: View {
    @Bindable var model: MapModel

    var body: some View {
        if let nav = model.navigation {
            if nav.isRerouting {
                rerouting
            } else if let step = nav.step {
                instruction(step)
            }
        }
    }

    private func instruction(_ step: NavigationStep) -> some View {
        Button { model.advanceStep() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    turnTile(step.direction)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.distanceText).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                        Text(step.instruction).textStyle(.title2).foregroundStyle(Color.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 6) {
                    Icon(.turnRight, size: 14, color: .brandPrimary)
                    Text(step.thenText).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            }
            .padding(16)
            .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassShadow()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.distanceText) \(step.instruction)، \(step.thenText)")
        .accessibilityHint(model.isMock ? "اضغطي للانتقال إلى الخطوة التالية" : "")
    }

    private func turnTile(_ direction: TurnDirection) -> some View {
        let icon: AppIcon = switch direction {
        case .left: .turnLeft
        case .right: .turnRight
        case .straight: .navigate
        }
        return Icon(icon, size: 34, color: .white)
            .frame(width: 60, height: 60)
            .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var rerouting: some View {
        HStack(spacing: 12) {
            Icon(.refresh, size: 22, color: .statusWarning)
                .frame(width: 44, height: 44)
                .background(Color.statusWarningBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("جارٍ تحديث المسار…").textStyle(.headline).foregroundStyle(Color.statusWarning)
                Text("تجاوزتِ الانعطاف بـ ٣٠ م، نحسب طريقًا جديدًا").textStyle(.footnote).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView().tint(.statusWarning)
        }
        .padding(14)
        .glassBackground(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassShadow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Trip card

struct TripCardPanel: View {
    @Bindable var model: MapModel

    var body: some View {
        MapPanelContainer {
            if let nav = model.navigation {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nav.isRerouting ? "جارٍ الحساب…" : (nav.step?.remainingText ?? ""))
                                .textStyle(.title2).foregroundStyle(Color.brandPrimary)
                            Text(nav.isRerouting ? "نُبقي وجهتك \(nav.target.title) كما هي" : (nav.step?.progressText ?? ""))
                                .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !isMeeting(nav) {
                            Button { model.endNavigation() } label: {
                                HStack(spacing: 4) {
                                    Text("إنهاء").textStyle(.subheadStrong)
                                    Icon(.close, size: 14)
                                }
                                .foregroundStyle(Color.statusError)
                                .padding(.horizontal, 14).frame(height: 40)
                                .background(Color.statusErrorBg, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("إنهاء التوجيه")
                        }
                    }
                    if let step = nav.step, !nav.isRerouting, let alert = step.alert {
                        HStack(spacing: 8) {
                            if step.alertLevel == .unknown {
                                Icon(.users, size: 14, color: .locationBlue)
                            } else {
                                CrowdBadge(level: step.alertLevel, style: .mapCompact)
                            }
                            Text(alert).textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    if nav.isRerouting {
                        landmarkRow(icon: .info, text: "توقفي لحظة أو تابعي المشي، سنحدّث الاتجاه تلقائيًا")
                    } else if let landmark = nav.step?.landmark {
                        landmarkRow(icon: .landmark, text: landmark)
                    }
                    if isMeeting(nav) {
                        Button("إنهاء التوجيه") { model.endNavigation() }.appButton(.mint, height: 44)
                    }
                }
            }
        }
    }

    private func isMeeting(_ nav: NavigationSession) -> Bool {
        if case .meetingPoint = nav.target { return true }
        return false
    }

    private func landmarkRow(icon: AppIcon, text: String) -> some View {
        HStack(spacing: 8) {
            Icon(icon, size: 18, color: .brandPrimary)
            Text(text).textStyle(.footnote).foregroundStyle(Color.textPrimary)
            Spacer()
        }
        .padding(12)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 2.4 compare routes

struct CompareRoutesSheet: View {
    @Bindable var model: MapModel
    let target: NavigationTarget
    let routes: [Route]
    let current: RouteKind
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast

    var body: some View {
        let cur = routes.first { $0.kind == current } ?? routes[0]
        let alt = routes.first { $0.kind != current } ?? routes[0]
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            MapPanelHeader(title: "مقارنة الطريقين", buttonIcon: .close, buttonLabel: "إغلاق") { dismiss() }
            VStack(spacing: 0) {
                row(label: "", current: "الحالي", alternative: "البديل", header: true)
                row(label: "الوقت", current: ArabicDigits.minutes(cur.minutes), alternative: ArabicDigits.minutes(alt.minutes),
                    delta: alt.minutes == cur.minutes ? nil : "\(alt.minutes > cur.minutes ? "+" : "−")\(ArabicDigits.format(abs(alt.minutes - cur.minutes))) د")
                row(label: "المسافة", current: "\(ArabicDigits.format(cur.meters)) م", alternative: "\(ArabicDigits.format(alt.meters)) م")
                HStack {
                    Text("الازدحام").textStyle(.footnote).foregroundStyle(Color.textSecondary).frame(width: 80, alignment: .leading)
                    CrowdBadge(level: cur.crowdOnRoute, style: .mapCompact).frame(maxWidth: .infinity)
                    CrowdBadge(level: alt.crowdOnRoute, style: .mapCompact).frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
                Divider()
                row(label: "الوصول", current: ArabicDigits.time(cur.arrival), alternative: ArabicDigits.time(alt.arrival), divider: false)
            }
            .padding(.horizontal, 12)
            .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            StatusBanner(text: alt.kind == .quietest
                         ? "الطريق البديل أطول قليلًا لكنه يتجنب ازدحام ممر قطار الحرمين"
                         : "الطريق الأسرع أقصر لكنه يمر بممر قطار الحرمين المزدحم", tone: .info)
            Spacer(minLength: 0)
            Button("اعتماد الطريق البديل") {
                model.selectRoute(alt.kind)
                dismiss()
                toast.show(alt.kind == .quietest
                           ? "تم اعتماد الطريق الأقل ازدحامًا، الوصول \(ArabicDigits.time(alt.arrival))"
                           : "تم اعتماد الطريق الأسرع، الوصول \(ArabicDigits.time(alt.arrival))")
            }
            .appButton(.primary)
            Button("الاحتفاظ بالطريق الحالي") { dismiss() }.appButton(.mint)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func row(label: String, current: String, alternative: String, delta: String? = nil, header: Bool = false, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).textStyle(.footnote).foregroundStyle(Color.textSecondary).frame(width: 80, alignment: .leading)
                Text(current).textStyle(header ? .caption : .subheadStrong)
                    .foregroundStyle(header ? Color.textSecondary : Color.textPrimary).frame(maxWidth: .infinity)
                HStack(spacing: 4) {
                    Text(alternative).textStyle(header ? .caption : .subheadStrong)
                        .foregroundStyle(header ? Color.brandPrimary : Color.textPrimary)
                    if let delta {
                        Text(delta).textStyle(.caption2).foregroundStyle(Color.statusWarning)
                            .padding(.horizontal, 6).background(Color.statusWarningBg, in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            if divider { Divider() }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3.7 note sheet

struct BoothNoteSheet: View {
    @Bindable var model: MapModel
    let booth: Booth
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var text = ""
    @State private var saving = false
    @FocusState private var focused: Bool
    private let limit = 200

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Text("ملاحظة عن \(booth.name)").textStyle(.headline)
                HStack {
                    Button("إلغاء") { dismiss() }.textStyle(.body).foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                try await model.saveNote(booth, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                                dismiss()
                                toast.show("تم حفظ الملاحظة")
                            } catch {
                                toast.show((error as? AppError)?.message ?? "تعذّر حفظ الملاحظة", icon: .warning, iconColor: .statusError)
                            }
                        }
                    } label: {
                        if saving { ProgressView() } else { Text("حفظ").textStyle(.button) }
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .padding(.top, 16)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("اكتبي ما تودّين تذكّره عن هذا الجناح…")
                        .textStyle(.body).foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .textStyle(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .onChange(of: text) { _, new in if new.count > limit { text = String(new.prefix(limit)) } }
            }
            .padding(10)
            .frame(minHeight: 140)
            .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack {
                Spacer()
                Text("\(ArabicDigits.format(text.count)) / \(ArabicDigits.format(limit))")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .onAppear {
            text = model.visits[booth.id]?.note ?? ""
            focused = true
        }
    }
}
