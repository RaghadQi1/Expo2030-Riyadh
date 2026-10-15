import SwiftUI

@main
struct Expo2030App: App {
    @State private var app = AppState()
    @State private var services = AppServices()
    @State private var toasts = ToastCenter()
    @State private var connectivity = ConnectivityMonitor()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(services)
                .environment(toasts)
                .environment(connectivity)
                // The whole product is Arabic and drawn right-to-left in Figma.
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .preferredColorScheme(.light)
                .foregroundStyle(Color.textPrimary)
                .tint(.brandPrimary)
        }
    }
}

/// Switches between the top-level phases: intro → onboarding → welcome/sign-in → personalization → main tabs.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var app = app
        ZStack {
            switch app.phase {
            case .intro:
                IntroView { app.finishIntro() }
                    .transition(.opacity)
            case .onboarding:
                OnboardingView { app.finishOnboarding() }
                    .transition(.opacity)
            case .welcome:
                AuthFlowView()
                    .transition(.opacity)
            case .personalization:
                PersonalizationFlowView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .task {
            if let live = services.auth as? LiveAuthService,
               let restored = await live.restoreSession() {
                if app.session.isGuest {
                    if app.phase == .welcome { app.signedIn(restored) }
                    else { app.session = restored }
                }
            }
        }
        .toastHost(topPadding: 8)
        .overlay(alignment: .bottom) {
            if services.environment.isMock && app.phase != .intro {
                DemoModeFootnote()
            }
        }
    }
}

/// Small persistent label in the home-indicator zone so demo operations are never mistaken for real ones.
private struct DemoModeFootnote: View {
    var body: some View {
        GeometryReader { geo in
            let inset = geo.safeAreaInsets.bottom
            DemoModeBadge()
                .scaleEffect(0.85)
                .opacity(0.9)
                .frame(maxWidth: .infinity)
                .position(x: geo.size.width / 2,
                          y: geo.size.height + (inset > 20 ? inset - 22 : -4))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(false)
    }
}
