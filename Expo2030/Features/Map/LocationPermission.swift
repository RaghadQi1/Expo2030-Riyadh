import CoreLocation
import SwiftUI
import UserNotifications

/// Real iOS location / notification permission state (4.10 – 4.17).
///
/// Only the *permission* is real. The visitor's position inside the hall comes from `MapService.currentLocation()`
/// (mock data today). Indoor positioning (beacons / UWB / a provider SDK) has to be agreed with the backend
/// developer — see API_CONTRACT.md «الموقع داخل المعرض».
@MainActor
@Observable
final class LocationPermissionModel: NSObject, CLLocationManagerDelegate {
    enum Status: Equatable { case notDetermined, allowed, denied, servicesOff }

    private(set) var status: Status = .notDetermined
    private(set) var isApproximate = false
    private(set) var hasAlwaysPermission = false
    private(set) var notificationsStatus: UNAuthorizationStatus = .notDetermined
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    var canShowLocation: Bool { status == .allowed }

    func refresh() {
        let auth = manager.authorizationStatus
        isApproximate = manager.accuracyAuthorization == .reducedAccuracy
        hasAlwaysPermission = auth == .authorizedAlways
        switch auth {
        case .notDetermined: status = .notDetermined
        case .denied, .restricted: status = .denied
        case .authorizedAlways, .authorizedWhenInUse: status = .allowed
        @unknown default: status = .denied
        }
        Task.detached { [weak self] in
            // `locationServicesEnabled()` must not run on the main thread.
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run {
                guard let self else { return }
                if !enabled { self.status = .servicesOff }
            }
        }
        Task { await refreshNotifications() }
    }

    /// Shows the system prompt (4.11 / 4.12). Call only after the in-app explainer (4.10).
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// «التغيير إلى السماح دائمًا» (5.15). iOS shows its own upgrade prompt.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshNotifications()
    }

    private func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsStatus = settings.authorizationStatus
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

// MARK: - 4.10 Location explainer

struct LocationExplainerSheet: View {
    var onContinue: () -> Void
    var onLater: () -> Void

    var body: some View {
        PermissionExplainer(
            icon: .navigate,
            title: "اسمحي باستخدام موقعك لنرشدك داخل المعرض",
            points: [
                (.map, "نُظهر مكانك واتجاهك على الخريطة المجسمة"),
                (.route, "نوجّهك خطوة بخطوة إلى الأجنحة والخدمات"),
                (.lock, "لا يُشارك موقعك مع أي صديقة إلا بقرارك"),
            ],
            primary: "متابعة", secondary: "ليس الآن",
            onPrimary: onContinue, onSecondary: onLater)
    }
}

// MARK: - 4.16 Notifications explainer

struct NotificationsExplainerSheet: View {
    var onContinue: () -> Void
    var onLater: () -> Void

    var body: some View {
        PermissionExplainer(
            icon: .bell,
            title: "فعّلي التنبيهات حتى لا تفوتك الدعوات",
            points: [
                (.addPerson, "دعوات التواصل من صديقاتك"),
                (.flag, "اقتراحات نقطة الالتقاء والرد عليها"),
                (.clock, "تنبيه قبل انتهاء مشاركة موقعك"),
            ],
            primary: "تفعيل التنبيهات", secondary: "ليس الآن",
            onPrimary: onContinue, onSecondary: onLater)
    }
}

/// Shared layout of the in-app permission explainers (4.5, 4.10, 4.16, 5.13, 12.05, 14.10).
struct PermissionExplainer: View {
    let icon: AppIcon
    let title: String
    var message: String? = nil
    var points: [(AppIcon, String)] = []
    var footnote: String? = nil
    let primary: String
    var secondary: String? = nil
    var onPrimary: () -> Void
    var onSecondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 18) {
            SheetGrabber().padding(.top, 8)
            IllustrationBadge(icon: icon, size: 64, iconSize: 28)
            Text(title).textStyle(.title3).foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message).textStyle(.subhead).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(points.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            Icon(points[i].0, size: 20, color: .brandPrimary)
                                .frame(width: 36, height: 36)
                                .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(points[i].1).textStyle(.subhead).foregroundStyle(Color.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(14)
                .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let footnote {
                Text(footnote).textStyle(.caption).foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button(primary, action: onPrimary).appButton(.primary)
                if let secondary, let onSecondary {
                    Button(secondary, action: onSecondary).appButton(.text, height: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(Color.bgSurface)
    }
}

// MARK: - 4.13 / 4.14 / 4.15 banners

/// «دقة الموقع منخفضة» — precise location is off (4.13).
struct LowAccuracyBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.warning, size: 20, color: .statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text("دقة الموقع منخفضة").font(AppFont.arabic(13, .semibold)).foregroundStyle(Color.statusWarning)
                Text("الموقع الدقيق متوقف، مكانك تقريبي بنطاق ١٥ م والتوجيه غير مفصّل")
                    .textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("تفعيل") { LocationPermissionModel.openSettings() }
                .textStyle(.caption).foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.brandMint, in: Capsule())
        }
        .padding(12)
        .background(Color.statusWarningBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 4.14 permission denied · 4.15 location services off.
struct LocationUnavailableCard: View {
    let status: LocationPermissionModel.Status
    var onAllow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Icon(.navigate, size: 22, color: .statusWarning)
                    .frame(width: 44, height: 44)
                    .background(Color.statusWarningBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(message).textStyle(.footnote).foregroundStyle(Color.textSecondary)
            if status == .servicesOff {
                Text("الإعدادات ← الخصوصية والأمان ← خدمات الموقع")
                    .textStyle(.caption).foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.bgSurface2, in: Capsule())
            }
            Button(status == .notDetermined ? "السماح باستخدام موقعي" : "فتح الإعدادات") {
                if status == .notDetermined { onAllow() } else { LocationPermissionModel.openSettings() }
            }
            .appButton(.mint, height: 44)
        }
    }

    private var title: String {
        switch status {
        case .servicesOff: "خدمات الموقع متوقفة في جهازك"
        case .notDetermined: "اسمحي باستخدام موقعك لنرشدك داخل المعرض"
        default: "لا يمكننا عرض مكانك الآن"
        }
    }

    private var message: String {
        switch status {
        case .servicesOff: "فعّليها لنُظهر مكانك ونرشدك داخل المعرض. يمكنك متابعة الاستكشاف دون تحديد موقعك."
        case .notDetermined: "نُظهر مكانك واتجاهك على الخريطة، ولا يُشارك موقعك مع أحد إلا بقرارك."
        default: "رفضتِ إذن الموقع. ما زال بإمكانك البحث واستكشاف الخريطة، لكن لن نُظهر موقعك أو نوجّهك حتى تفعّلي الإذن من الإعدادات."
        }
    }
}
