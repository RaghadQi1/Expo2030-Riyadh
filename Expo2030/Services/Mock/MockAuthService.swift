import Foundation

/// Demo-only authentication. No credentials leave the device and nothing is really created.
/// Demo accounts (see MockData/MockUsers.swift):
///   • noura@example.com / Expo2030!   → signs in
///   • any other email                 → «البريد أو كلمة المرور غير صحيحة» (06.04)
/// Social buttons: Apple → hidden-email welcome (06.18), Facebook → complete name (06.19),
/// Google → existing-account conflict (06.20).
final class MockAuthService: AuthService {
    private let settings: DemoSettings

    init(settings: DemoSettings = .shared) {
        self.settings = settings
    }

    func signIn(email: String, password: String) async throws -> Session {
        try await MockNetwork.roundTrip(settings, extra: 0.4)
        guard email.lowercased() == MockUsers.noura.email, password == MockUsers.demoPassword else {
            throw AppError.invalidCredentials
        }
        return Session(user: MockUsers.noura, accessToken: "demo-token", refreshToken: nil)
    }

    func signUp(_ request: SignUpRequest) async throws -> Session {
        try await MockNetwork.roundTrip(settings)
        guard request.acceptedTerms else { throw AppError.validation(["terms": "يلزم الموافقة على الشروط"]) }
        var user = MockUsers.newAccount
        user.name = request.name
        user.email = request.email
        user.isEmailVerified = false
        return Session(user: user, accessToken: "demo-token", refreshToken: nil)
    }

    func requestPasswordReset(email: String) async throws {
        try await MockNetwork.roundTrip(settings)
    }

    func resetPassword(token: String, newPassword: String) async throws {
        try await MockNetwork.roundTrip(settings)
    }

    func socialSignIn(_ provider: AuthProvider) async throws -> SocialSignInResult {
        try await MockNetwork.roundTrip(settings)
        switch provider {
        case .apple:
            return .signedIn(Session(user: MockUsers.sadeemApple, accessToken: "demo-token", refreshToken: nil))
        case .facebook:
            return .needsProfileCompletion(partial: MockUsers.facebookPartial)
        case .google:
            return .existingAccount(email: MockUsers.noura.email, existingProvider: .email)
        case .email:
            return .cancelled
        }
    }

    func completeProfile(displayName: String) async throws -> Session {
        try await MockNetwork.roundTrip(settings)
        var user = MockUsers.facebookPartial
        user.name = displayName
        return Session(user: user, accessToken: "demo-token", refreshToken: nil)
    }

    func mergeGuestData(_ summary: GuestDataSummary) async throws -> GuestDataSummary {
        try await MockNetwork.roundTrip(settings, extra: 0.6)
        return summary
    }

    func signOut() async {}
}
