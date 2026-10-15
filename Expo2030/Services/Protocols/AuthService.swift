import Foundation

/// Authentication & account lifecycle. Screens: 06.01 – 06.26.
protocol AuthService: AnyObject {
    func signIn(email: String, password: String) async throws -> Session
    /// Creates an account and immediately returns an authenticated session (no email verification).
    func signUp(_ request: SignUpRequest) async throws -> Session
    /// Always succeeds from the user's point of view (06.12 never reveals if the account exists).
    func requestPasswordReset(email: String) async throws
    func resetPassword(token: String, newPassword: String) async throws
    func socialSignIn(_ provider: AuthProvider) async throws -> SocialSignInResult
    func completeProfile(displayName: String) async throws -> Session
    /// Moves on-device guest data into the new account (06.24).
    func mergeGuestData(_ summary: GuestDataSummary) async throws -> GuestDataSummary
    func signOut() async
}
