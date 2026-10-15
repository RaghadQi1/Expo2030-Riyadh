import SwiftUI

/// Expo assistant — medium sheet that keeps the current screen's context (12.01), full conversation with
/// interactive cards (12.02), previews before any change (12.03, خريطتي 7.11 / 7.12) and voice input with an
/// in-app explainer before the system prompt (12.05 – 12.07). Answers are suggestions; nothing changes
/// without explicit confirmation.
struct AssistantSheet: View {
    let context: AssistantContext

    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var messages: [AssistantMessage] = []
    @State private var suggestions: [String] = []
    @State private var draft = ""
    @State private var isThinking = false
    @State private var showMicExplainer = false
    @State private var detent: PresentationDetent = .medium
    @State private var preview: AssistantPreview?
    @State private var speech = SpeechTranscriber()
    @FocusState private var composerFocused: Bool

    private var isMap: Bool { context == .map }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if speech.permission == .denied {
                            StatusBanner(text: "الميكروفون غير مسموح. اكتب سؤالك، أو فعّل الإذن من الإعدادات.", tone: .info)
                            Button("فتح الإعدادات") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .textStyle(.footnote)
                            .foregroundStyle(Color.textLink)
                        }
                        if showMicExplainer {
                            micExplainer
                        }
                        ForEach(messages) { message in
                            MessageView(message: message, isMap: isMap, onAction: handle)
                                .id(message.id)
                        }
                        if isThinking {
                            ThinkingRow(text: isMap ? MockAssistant.thinkingText : "أراجع خطتك والبيانات الحالية…")
                                .id("thinking")
                        }
                        if !suggestions.isEmpty && !isThinking {
                            FlowLayout(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { send(s) } label: {
                                        HStack(spacing: 6) {
                                            if isMap { Icon(.sparkles, size: 14, color: .brandPrimary) }
                                            Text(s).textStyle(.footnote).foregroundStyle(Color.textPrimary)
                                        }
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.bgSurface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.borderDefault))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: isThinking) { _, thinking in
                    if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            composer
        }
        .background(Color.bgCanvasTranslucent)
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .environment(\.layoutDirection, .rightToLeft)
        .task { await start() }
        .onChange(of: speech.transcript) { _, text in if !text.isEmpty { draft = text } }
        .sheet(item: $preview) { p in
            PreviewSheetView(preview: p) { confirmed in
                preview = nil
                if confirmed { Task { await confirm(p) } }
            }
            .presentationDetents([.height(p.height)])
            .presentationCornerRadius(28)
        }
    }

    // MARK: Header (Figma «Assistant header»)

    private var header: some View {
        VStack(spacing: 6) {
            Capsule().fill(Color.borderStrong).frame(width: 36, height: 5)
            HStack {
                HStack(spacing: 8) {
                    Icon(.sparkles, size: 20, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("مساعد إكسبو").textStyle(.headline).foregroundStyle(Color.textPrimary)
                        Text(contextSubtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Icon(.close, size: 18, color: .textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.bgSurface2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إغلاق المساعد")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.glassTintStrong)
    }

    private var contextSubtitle: String {
        switch context {
        case .map: "السياق: خريطتي · قرب منطقة المطاعم"
        case .plan: "السياق: خطتي · المحطة 1 من 4"
        case .journey: "السياق: رحلتي"
        case .pavilion: "السياق: تفاصيل الجناح"
        case .general: "السياق: الرئيسية"
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(isMap ? "اسألي عن جناح، زحام، أو نقطة التقاء…" : "اسأل عن جناح، وقت، أو طريق…", text: $draft, axis: .vertical)
                .textStyle(.body)
                .lineLimit(1...4)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button { micTapped() } label: {
                Icon(.mic, size: 20, color: speech.isRecording ? .white : .brandPrimary)
                    .frame(width: 44, height: 44)
                    .background(speech.isRecording ? Color.statusError : Color.brandMint, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(speech.permission == .denied ? 0.4 : 1)
            .accessibilityLabel(speech.isRecording ? "إيقاف التسجيل" : "إدخال صوتي")
            Button { send(draft) } label: {
                Icon(.send, size: 20, color: draft.isEmpty ? .textTertiary : .white)
                    .frame(width: 44, height: 44)
                    .background(draft.isEmpty ? Color.bgSurface2 : Color.brandPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            .accessibilityLabel("إرسال")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.bgSurface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider() }
    }

    private var micExplainer: some View {
        VStack(spacing: 10) {
            Icon(.mic, size: 30, color: .brandPrimary)
                .frame(width: 64, height: 64)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("اسأل بصوتك").textStyle(.title3)
            Text("نحتاج إذن الميكروفون عند الاستخدام فقط. نحوّل كلامك إلى نص تراجعه قبل الإرسال — لا نرسل التسجيل تلقائيًا.")
                .textStyle(.subhead).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            Button("متابعة") {
                showMicExplainer = false
                Task {
                    await speech.requestPermission()
                    if speech.permission == .granted { try? speech.start() }
                    else if speech.permission == .unavailable {
                        toasts.show("التعرّف على الكلام غير متاح لهذه اللغة على جهازك. اكتب سؤالك.", icon: .info, iconColor: .statusInfo)
                    }
                }
            }
            .appButton(.primary)
            Button("أكتب بدلًا من ذلك") {
                showMicExplainer = false
                composerFocused = true
            }
            .appButton(.text)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    @MainActor private func start() async {
        speech.refreshPermission()
        guard messages.isEmpty else { return }
        if let welcome = try? await services.assistant.welcome(context: context, userName: app.displayName) {
            messages = [welcome.message]
            suggestions = welcome.followUps
        }
    }

    private func micTapped() {
        if speech.isRecording { speech.stop(); return }
        switch speech.permission {
        case .unknown: withAnimation { showMicExplainer = true }
        case .granted: try? speech.start()
        case .denied: toasts.show("الميكروفون غير مسموح. اكتب سؤالك أو فعّل الإذن من الإعدادات.", icon: .info, iconColor: .statusInfo)
        case .unavailable: toasts.show("التعرّف على الكلام غير متاح الآن. اكتب سؤالك.", icon: .info, iconColor: .statusInfo)
        }
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        speech.stop()
        draft = ""
        suggestions = []
        messages.append(AssistantMessage(role: .user, text: trimmed))
        isThinking = true
        if messages.count > 2 { detent = .large }
        Task { @MainActor in
            do {
                let reply = try await services.assistant.send(trimmed, context: context)
                messages.append(reply.message)
                suggestions = reply.followUps
                detent = .large
            } catch let error as AppError {
                messages.append(AssistantMessage(role: .assistant, text: "\(error.title). \(error.message)"))
            } catch {}
            isThinking = false
        }
    }

    private func handle(_ action: MessageAction) {
        switch action {
        case .previewPlanChange:
            Task { @MainActor in
                let plan = (try? await services.plan.currentPlan()) ?? MockPlans.plan(from: MockPlans.moreExperiences)
                preview = .plan(MockPlans.shorterWalkProposal(for: plan))
            }
        case .dismissSuggestion:
            messages.append(AssistantMessage(role: .assistant, text: "تمام، خطتك تبقى كما هي."))
        case .showOnMap(let id):
            dismiss()
            app.openMap(.showBooth(id))
        case .directions(let id, let title):
            preview = .destination(currentTitle: "PwC، جناح A7", newTitle: title, boothId: id)
        case .proposeMeeting(let point):
            preview = .meeting(point)
        case .openPavilion(let id):
            dismiss()
            app.selectedTab = .discover
            Task { @MainActor in
                let name = (try? await services.catalog.pavilion(id: id))?.name ?? "الجناح"
                toasts.show("افتح «\(name)» من الرئيسية لعرض التفاصيل.", icon: .info, iconColor: .statusInfo)
            }
        }
    }

    @MainActor private func confirm(_ preview: AssistantPreview) async {
        switch preview {
        case .plan(let proposal):
            do {
                _ = try await services.plan.apply(proposal)
                app.planRevision += 1
                messages.append(AssistantMessage(role: .assistant, text: "طبّقت التعديل على خطتك. تقدر تتراجع خلال 10 دقائق من «خطتي»."))
            } catch {
                toasts.show("تعذّر تطبيق التعديل.", icon: .warning, iconColor: .statusError)
            }
        case .destination(_, _, let boothId):
            dismiss()
            app.openMap(.navigateToBooth(boothId))
        case .meeting(let point):
            if let friend = try? await services.friends.friends().first(where: { $0.sharesWithMe }) {
                _ = try? await services.friends.proposeMeeting(point, with: friend.id)
            }
            dismiss()
            app.openMap(.meetingPoint)
            toasts.show("تم عرض الاقتراح.", icon: .send, iconColor: .brandPrimary)
        }
    }
}

// MARK: - Messages

enum MessageAction {
    case previewPlanChange, dismissSuggestion
    case showOnMap(String)
    case directions(String, String)
    case proposeMeeting(MeetingPoint)
    case openPavilion(String)
}

private struct MessageView: View {
    let message: AssistantMessage
    let isMap: Bool
    var onAction: (MessageAction) -> Void

    var body: some View {
        if message.role == .user {
            // 12.x draws the visitor's bubble on the right; «خريطتي» 7.x draws it on the left.
            HStack {
                if isMap { Spacer(minLength: 40) }
                Text(message.text).textStyle(.body).foregroundStyle(Color.brandOnPrimary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.brandPrimary, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                                              bottomTrailingRadius: isMap ? 20 : 6, topTrailingRadius: 20,
                                                                              style: .continuous))
                if !isMap { Spacer(minLength: 40) }
            }
            .accessibilityLabel("أنت: \(message.text)")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Icon(.sparkles, size: 14, color: .white)
                        .frame(width: 22, height: 22)
                        .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: isMap ? 6 : 11, style: .continuous))
                    Text("مساعد إكسبو").textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                Text(message.text).textStyle(.body).foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.bgSurface, in: UnevenRoundedRectangle(topLeadingRadius: isMap ? 16 : 6, bottomLeadingRadius: isMap ? 16 : 20,
                                                                           bottomTrailingRadius: isMap ? 16 : 20, topTrailingRadius: isMap ? 16 : 20,
                                                                           style: .continuous))
                if let card = message.card { CardView(card: card, onAction: onAction) }
                if let note = message.sourceNote {
                    Text(note).textStyle(.caption).foregroundStyle(Color.textTertiary)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

private struct CardView: View {
    let card: AssistantCard
    var onAction: (MessageAction) -> Void

    var body: some View {
        switch card {
        case .planSuggestion(let title, let chips, let reason):
            VStack(alignment: .leading, spacing: 8) {
                Text(title).textStyle(.headline)
                HStack(spacing: 6) { ForEach(chips, id: \.self) { InfoPill(text: $0) } }
                Text(reason).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Button("معاينة التغيير") { onAction(.previewPlanChange) }.appButton(.primary, height: 44)
                    Button("لا شكرًا") { onAction(.dismissSuggestion) }.appButton(.tertiary, height: 44)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))

        case .alternatives(let items, let primary):
            VStack(spacing: 8) {
                ForEach(items) { item in
                    Button {
                        if item.id.hasPrefix("p") && item.id.contains("-") { onAction(.openPavilion(item.id)) }
                        else { onAction(.showOnMap(item.id)) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).textStyle(primary == nil ? .caption : .bodyStrong).foregroundStyle(Color.textPrimary)
                                Text(item.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            CrowdBadge(level: item.crowd, style: primary == nil ? .standard : .map)
                            Icon(.chevronLeft, size: 16, color: .textTertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if let primary, let first = items.first {
                    HStack(spacing: 8) {
                        Button(primary) { onAction(.directions(first.id, "\(first.title)، \(first.subtitle)")) }
                            .appButton(.primary, height: 44)
                        Button("عرض على الخريطة") { onAction(.showOnMap(first.id)) }.appButton(.tertiary, height: 44)
                    }
                }
            }

        case .place(let result):
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title).textStyle(.headline)
                Text(result.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    InfoPill(text: result.distanceText)
                    InfoPill(text: result.walkText)
                    CrowdBadge(level: result.crowd, style: .map)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(result.reason).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Button("الاتجاهات") {
                        onAction(.directions(result.id, "\(result.title)، \(result.subtitle.components(separatedBy: "، ").dropFirst().first ?? "")، \(result.walkText.replacingOccurrences(of: " مشيًا", with: ""))، \(result.crowd.mapTitle)"))
                    }
                    .appButton(.primary, height: 44)
                    Button("عرض على الخريطة") { onAction(.showOnMap(result.id)) }.appButton(.tertiary, height: 44)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))

        case .meetingPoint(let point, let note):
            VStack(alignment: .leading, spacing: 8) {
                Text(point.name).textStyle(.headline)
                Text(point.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                HStack(spacing: 6) {
                    InfoPill(text: "في المنتصف")
                    InfoPill(text: "ذكرى: \(ArabicDigits.format(point.friendMinutes)) د")
                    InfoPill(text: "أنتِ: \(ArabicDigits.format(point.myMinutes)) د")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(note).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Button("اقتراح نقطة التقاء") { onAction(.proposeMeeting(point)) }.appButton(.primary, height: 44)
                    Button("عرض على الخريطة") { onAction(.showOnMap("meeting")) }.appButton(.tertiary, height: 44)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.borderDefault))
        }
    }
}

private struct ThinkingRow: View {
    let text: String
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(Color.brandPrimary).frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * abs(sin(phase + Double(i) * 0.6)))
                }
            }
            Text(text).textStyle(.footnote).foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi } }
        .accessibilityLabel(text)
    }
}

// MARK: - Preview sheets (12.03, خريطتي 7.11, 7.12)

enum AssistantPreview: Identifiable {
    case plan(ReplanProposal)
    case destination(currentTitle: String, newTitle: String, boothId: String)
    case meeting(MeetingPoint)

    var id: String {
        switch self {
        case .plan: "plan"
        case .destination: "destination"
        case .meeting: "meeting"
        }
    }

    var height: CGFloat {
        switch self {
        case .plan: 420
        case .destination: 360
        case .meeting: 344
        }
    }
}

private struct PreviewSheetView: View {
    let preview: AssistantPreview
    var onFinish: (Bool) -> Void
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch preview {
            case .plan(let proposal):
                Text("معاينة: خطة أقصر مشيًا").textStyle(.title3)
                ForEach(proposal.diff) { DiffRow(item: $0, style: .assistant) }
                Text("الأثر: المشي 18 ← 10 د · نهاية الخطة 5:30 م كما هي").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                actions(confirm: "تطبيق على خطتي", fullWidthCancel: true)
            case .destination(let current, let new, _):
                Text("معاينة: تغيير الوجهة").textStyle(.title3)
                compareRow(tag: "الحالية", title: current, subtitle: "الوجهة الحالية", highlighted: false)
                compareRow(tag: "جديدة", title: new, subtitle: "الوجهة الجديدة", highlighted: true)
                infoLine("لن تتغير وجهتك إلا بعد التأكيد، ويُحفظ PwC في «لاحقًا».")
                actions(confirm: "تأكيد الاستبدال", fullWidthCancel: false)
            case .meeting(let point):
                Text("معاينة: اقتراح نقطة التقاء").textStyle(.title3)
                compareRow(tag: "مقترحة", title: point.name, subtitle: "نقطة الالتقاء", highlighted: true)
                compareRow(tag: "تقديري", title: "أنتِ \(ArabicDigits.format(point.myMinutes)) د، ذكرى \(ArabicDigits.format(point.friendMinutes)) د",
                           subtitle: "وقت الوصول", highlighted: false)
                infoLine("سيصل الاقتراح لذكرى، ولها القبول أو الرفض.")
                actions(confirm: "أرسل الاقتراح لذكرى", fullWidthCancel: false)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func compareRow(tag: String, title: String, subtitle: String, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).textStyle(.bodyStrong).foregroundStyle(Color.textPrimary)
                Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(tag).textStyle(.caption).foregroundStyle(highlighted ? Color.brandPrimary : Color.textSecondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.bgSurface, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(highlighted ? Color.brandMint : Color.bgSurface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoLine(_ text: String) -> some View {
        HStack(spacing: 6) {
            Icon(.info, size: 16, color: .textSecondary)
            Text(text).textStyle(.footnote).foregroundStyle(Color.textSecondary)
        }
    }

    private func actions(confirm: String, fullWidthCancel: Bool) -> some View {
        HStack(spacing: 10) {
            Button(confirm) {
                isApplying = true
                onFinish(true)
            }
            .appButton(.primary, isLoading: isApplying)
            Button("إلغاء") { onFinish(false) }
                .appButton(.tertiary)
                .frame(maxWidth: fullWidthCancel ? .infinity : 120)
        }
    }
}
