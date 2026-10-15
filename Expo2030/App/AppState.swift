import SwiftUI

/// Top-level app flow (05.01 → 05.04 → onboarding → welcome → main tabs).
enum AppPhase: Equatable {
    case intro
    case onboarding
    case welcome
    case personalization
    case main
}

enum MainTab: Int, CaseIterable, Identifiable, Hashable {
    // Order RTL: الرئيسية ← خطتي ← الخريطة ← رحلتي ← حسابي (first = rightmost).
    case discover, plan, map, journey, account

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .discover: "الرئيسية"
        case .plan: "خطتي"
        case .map: "الخريطة"
        case .journey: "رحلتي"
        case .account: "حسابي"
        }
    }

    var icon: AppIcon {
        switch self {
        case .discover: .home
        case .plan: .plan
        case .map: .map
        case .journey: .journey
        case .account: .user
        }
    }
}

/// Cross-tab request handled by the map tab (assistant «عرض على الخريطة», pavilion «الاتجاهات», …).
enum MapRequest: Equatable {
    case showBooth(String)
    case navigateToBooth(String)
    case meetingPoint
    case friends
    case scanFriend
}

/// An action a guest started before being asked to create an account; resumed after sign-up
/// (06.24 «متابعة دعوة سارة» / «أكملنا الإجراء الذي بدأته قبل التسجيل»).
struct PendingGuestAction: Equatable {
    var title: String
    var resumeTab: MainTab
}

@Observable
final class AppState {
    var phase: AppPhase
    var session: Session = .guest
    var selectedTab: MainTab = .discover
    var pendingGuestAction: PendingGuestAction?
    /// Presents the sign-in flow over the main app (e.g. guest banner «لإنشاء حسابك اضغط هنا»).
    var isAuthPresented = false
    var isAssistantPresented = false
    /// Pending request for the map tab; cleared by the map once handled.
    var mapRequest: MapRequest?
    /// Pushed detail screens hide the floating tab bar + assistant button (Figma shows none there).
    var chromeHideRequests = 0
    var isChromeHidden: Bool { chromeHideRequests > 0 }
    /// The plan changed (adopt / swap / replan) — tabs reload when this changes.
    var planRevision = 0
    /// Journey data changed (notes saved, sync finished) — «رحلتي» reloads when this changes.
    var journeyRevision = 0
    var hasPersonalized: Bool {
        didSet { UserDefaults.standard.set(hasPersonalized, forKey: Keys.personalized) }
    }

    private enum Keys {
        static let onboarded = "hasCompletedOnboarding"
        static let personalized = "hasPersonalized"
    }

    init() {
        let defaults = UserDefaults.standard
        hasPersonalized = defaults.bool(forKey: Keys.personalized)
        phase = .intro
    }

    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.onboarded) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.onboarded) }
    }

    var isGuest: Bool { session.isGuest }
    var displayName: String? { session.user?.name }

    // MARK: Flow transitions

    func finishIntro() {
        withAnimation(.easeInOut(duration: 0.35)) {
            phase = hasCompletedOnboarding ? (isGuest ? .welcome : .main) : .onboarding
        }
    }

    func finishOnboarding() {
        hasCompletedOnboarding = true
        withAnimation(.easeInOut(duration: 0.35)) { phase = .welcome }
    }

    func continueAsGuest() {
        session = .guest
        isAuthPresented = false
        withAnimation(.easeInOut(duration: 0.35)) { phase = .main }
    }

    /// Set when a guest created an account from inside the app; the auth flow then merges the
    /// on-device guest data and shows 06.24 before closing.
    var needsGuestMerge = false

    func signedIn(_ session: Session, startPersonalization: Bool = false) {
        let wasGuestInsideApp = isGuest && phase == .main && isAuthPresented
        self.session = session
        if wasGuestInsideApp {
            needsGuestMerge = true
            return
        }
        isAuthPresented = false
        withAnimation(.easeInOut(duration: 0.35)) {
            // Open the preference/AI plan flow on every explicit sign-in or sign-up.
            phase = startPersonalization ? .personalization : .main
        }
    }

    func startPersonalization() {
        withAnimation(.easeInOut(duration: 0.35)) { phase = .personalization }
    }

    func finishPersonalization(openPlan: Bool) {
        hasPersonalized = true
        selectedTab = openPlan ? .plan : .discover
        withAnimation(.easeInOut(duration: 0.35)) { phase = .main }
    }

    func openMap(_ request: MapRequest) {
        mapRequest = request
        selectedTab = .map
    }

    func signOut() {
        session = .guest
        selectedTab = .discover
        withAnimation(.easeInOut(duration: 0.35)) { phase = .welcome }
    }
}
