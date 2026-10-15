import SwiftUI

/// Every screen of the account flows (sections 2, 3, 4, 5 of the Figma file).
enum AuthRoute: Hashable {
    case emailSignIn                                   // 06.02 – 06.05
    case createAccount                                 // 06.07
    case forgotPassword(prefill: String)               // 06.11
    case forgotPasswordSent(email: String)             // 06.12
    case resetPassword(email: String)                  // 06.13
    case resetPasswordSuccess                          // 06.14
    case appleHiddenEmail(Session)                     // 06.18
    case completeProfile(User)                         // 06.19
    case accountConflict(email: String, provider: AuthProvider, attempted: AuthProvider) // 06.20
    case mergeSuccess(GuestDataSummary)                // 06.24
    case guestSignUpCancelled                          // 06.26
}

/// Shared router for the auth NavigationStack.
@Observable
final class AuthRouter {
    var path: [AuthRoute] = []

    func push(_ route: AuthRoute) { path.append(route) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
    func replaceTop(with route: AuthRoute) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
}

/// Root of the account flow. Presented as the app phase `.welcome`, or modally from the main app
/// (guest banner, Account tab) with `isModal = true`.
struct AuthFlowView: View {
    var isModal = false
    var startAt: AuthRoute? = nil

    @Environment(AppState.self) private var app
    @State private var router = AuthRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            WelcomeView(isModal: isModal)
                .navigationDestination(for: AuthRoute.self) { route in
                    destination(for: route)
                }
        }
        .environment(router)
        .tint(.textPrimary)
        .onAppear {
            if let startAt, router.path.isEmpty { router.push(startAt) }
        }
        .onChange(of: app.needsGuestMerge) { _, needsMerge in
            guard needsMerge else { return }
            Task { await mergeGuestData() }
        }
    }

    @Environment(AppServices.self) private var services

    @MainActor
    private func mergeGuestData() async {
        app.needsGuestMerge = false
        if !services.environment.isMock {
            // Guest demo records are not actual uploaded objects. Never claim they were merged.
            app.isAuthPresented = false
            return
        }
        let local = await services.journey.guestDataSummary()
        let merged = (try? await services.auth.mergeGuestData(local)) ?? local
        router.push(.mergeSuccess(merged))
    }

    @ViewBuilder
    private func destination(for route: AuthRoute) -> some View {
        switch route {
        case .emailSignIn: EmailSignInView()
        case .createAccount: CreateAccountView()
        case .forgotPassword(let prefill): ForgotPasswordView(email: prefill)
        case .forgotPasswordSent(let email): ForgotPasswordSentView(email: email)
        case .resetPassword(let email): ResetPasswordView(email: email)
        case .resetPasswordSuccess: ResetPasswordSuccessView()
        case .appleHiddenEmail(let session): AppleHiddenEmailView(session: session)
        case .completeProfile(let user): CompleteProfileView(user: user)
        case .accountConflict(let email, let provider, let attempted):
            AccountConflictView(email: email, existingProvider: provider, attemptedProvider: attempted)
        case .mergeSuccess(let summary): MergeSuccessView(summary: summary)
        case .guestSignUpCancelled: GuestSignUpCancelledView()
        }
    }
}

/// Common layout for the centred status screens (verify / reset / conflict): 88pt illustration,
/// title, body, then actions — all centred, 24pt side margins.
struct CenteredStatusLayout<Actions: View>: View {
    let icon: AppIcon
    var iconTint: Color = .brandPrimary
    var iconBackground: Color = .brandMint
    let title: String
    var titleStyle: AppTextStyle = .title1
    let message: String
    var detail: String? = nil
    var detailIsLTR = false
    var topPadding: CGFloat = 86
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                IllustrationBadge(icon: icon, tint: iconTint, background: iconBackground)
                Text(title)
                    .textStyle(titleStyle)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .textStyle(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .font(detailIsLTR ? AppTextStyle.enHeadline.font : AppTextStyle.footnote.font)
                        .foregroundStyle(detailIsLTR ? Color.textPrimary : Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                Spacer().frame(height: 8)
                actions()
            }
            .padding(.horizontal, 24)
            .padding(.top, topPadding)
            .padding(.bottom, 40)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.bgCanvas.ignoresSafeArea())
    }
}

/// Text link used under status-screen buttons (AR/Callout: Medium 12 / 23, text/link).
struct InlineLinkButton: View {
    let title: String
    var color: Color = .textLink
    let action: () -> Void
    var body: some View {
        Button(title, action: action)
            .font(AppFont.arabic(12, .medium, relativeTo: .caption))
            .foregroundStyle(color)
            .frame(minHeight: 23)
            .buttonStyle(.plain)
    }
}
