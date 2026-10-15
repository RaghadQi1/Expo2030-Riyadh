import AVFoundation
import Speech
import SwiftUI
import UserNotifications

/// «الإعدادات» — language/appearance are fixed by the design (Arabic, light); demo controls live here.
struct SettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var demo = services.demo
        Form {
            Section("اللغة والمظهر") {
                LabeledContent("اللغة", value: "العربية")
                LabeledContent("المظهر", value: "فاتح")
                Text("التصميم الحالي عربي وفاتح فقط. دعم الإنجليزية والوضع الداكن يحتاج تصاميم إضافية.")
                    .textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            Section("الإشعارات") {
                Button("إعدادات الإشعارات في iOS") { LocationPermissionModel.openSettings() }
            }
            Section("البيانات") {
                LabeledContent("التخزين", value: services.environment.isMock ? "بيانات محلية" : "حسابك وملفك ورحلتك في قاعدة البيانات")
                if app.isGuest {
                    Text("تُحفظ خطتك وملاحظاتك على هذا الجهاز فقط. أنشئ حسابًا للمزامنة بين الأجهزة.")
                        .textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
            }

            if services.environment.isMock {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("زمن الاستجابة: \(String(format: "%.1f", demo.latency)) ث").textStyle(.subhead)
                        Slider(value: $demo.latency, in: 0...3, step: 0.1).tint(.brandPrimary)
                    }
                    Toggle("فشل الطلب التالي (حالة خطأ)", isOn: $demo.failNextRequest)
                    Toggle("محاكاة انقطاع الاتصال", isOn: $demo.simulateOffline)
                    Toggle("قوائم فارغة (حالة فارغة)", isOn: $demo.emptyData)
                    Toggle("الصديقة ترفض اقتراح الالتقاء التالي", isOn: $demo.friendDeclinesMeeting)
                    Toggle("تجاوز انعطاف أثناء التوجيه (إعادة الحساب)", isOn: $demo.simulateMissedTurn)
                    Button("إعادة عرض شاشات التعريف") {
                        app.hasCompletedOnboarding = false
                        app.phase = .intro
                    }
                } header: {
                    Text("خيارات الاختبار")
                } footer: {
                    Text("عند استخدام الوضع المحلي، لا تُرسل العمليات إلى الخادم.")
                }
                .tint(.brandPrimary)
            }

            Section("حول التطبيق") {
                LabeledContent("الإصدار", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                LabeledContent("مصدر البيانات", value: services.environment.isMock ? "بيانات محلية" : "الخادم")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "الإعدادات")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
    }
}

/// «الأذونات» — current iOS permission states with a shortcut to Settings.
struct PermissionsView: View {
    @State private var location = LocationPermissionModel()
    @State private var camera = CameraPermission()
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                row("الموقع", icon: .navigate, state: locationText, why: "لعرض مكانك على خريطة المعرض وتوجيهك.")
                row("الإشعارات", icon: .bell, state: text(notifications), why: "لدعوات الأصدقاء ونقطة الالتقاء وانتهاء المشاركة.")
                row("الكاميرا", icon: .camera, state: cameraText, why: "لمسح رموز الأجنحة والأصدقاء فقط.")
                row("الميكروفون", icon: .mic, state: micText, why: "لتحويل سؤالك الصوتي إلى نص تراجعه قبل الإرسال.")
            } footer: {
                Text("نطلب كل إذن عند الحاجة إليه فقط، مع شرح قبل نافذة النظام.")
            }
            Section {
                Button("فتح إعدادات التطبيق") { LocationPermissionModel.openSettings() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "الأذونات")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private func row(_ title: String, icon: AppIcon, state: String, why: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(icon, size: 18, color: .brandPrimary)
                .frame(width: 34, height: 34)
                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).textStyle(.bodyStrong)
                Text(why).textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(state).textStyle(.caption).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var locationText: String {
        switch location.status {
        case .allowed: location.isApproximate ? "مسموح · تقريبي" : (location.hasAlwaysPermission ? "دائمًا" : "أثناء الاستخدام")
        case .denied: "غير مسموح"
        case .servicesOff: "خدمات الموقع متوقفة"
        case .notDetermined: "لم يُطلب بعد"
        }
    }

    private var cameraText: String {
        switch camera.status {
        case .granted: "مسموح"
        case .denied: "غير مسموح"
        case .notDetermined: "لم يُطلب بعد"
        case .unavailable: "غير متوفرة"
        }
    }

    private var micText: String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: SFSpeechRecognizer.authorizationStatus() == .authorized ? "مسموح" : "مسموح · التعرف على الكلام غير مفعّل"
        case .denied: "غير مسموح"
        default: "لم يُطلب بعد"
        }
    }

    private func text(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .authorized, .provisional, .ephemeral: "مسموح"
        case .denied: "غير مسموح"
        default: "لم يُطلب بعد"
        }
    }

    @MainActor private func refresh() async {
        location.refresh()
        camera.refresh()
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

/// «المساعدة والإبلاغ عن مشكلة». The support channel is not defined yet, so nothing is sent from here.
struct HelpView: View {
    private let faqs: [(String, String)] = [
        ("هل الإضافة إلى الخطة حجز مؤكد؟", "لا. الحجز يتم لدى الجهة المنظمة، ويمكنك تعليم الفعالية كـ«حجز مؤكد» بعد العودة."),
        ("من يرى موقعي؟", "لا أحد إلا من تختارين مشاركته معه، وللمدة التي تحددينها. يمكنك الإيقاف في أي وقت."),
        ("هل يثبت مسح رمز الجناح حضوري؟", "لا. المسح وحده لا يُعد إثبات حضور، و«أكد زيارتي» اختياري ويُحفظ في رحلتك فقط."),
        ("ماذا يحدث لبياناتي دون اتصال؟", "تتطلب بيانات الحساب والملاحظات المحفوظة في الخادم اتصالًا؛ لم تُفعّل بعد مزامنة تلقائية عند عودة الاتصال."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(faqs, id: \.0) { q in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.0).textStyle(.headline)
                        Text(q.1).textStyle(.subhead).foregroundStyle(Color.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground(radius: 18)
                }
                StatusBanner(text: "قناة الإبلاغ عن المشكلات (بريد أو نموذج) لم تُحدَّد بعد، وستُربط مع الخادم.", tone: .info)
            }
            .padding(Spacing.screen)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "المساعدة")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
    }
}
