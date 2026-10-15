import Foundation

/// Calls the proposed auth endpoints (API_CONTRACT.md §1). Social providers need their native SDKs
/// (Sign in with Apple via AuthenticationServices; Google/Facebook SDKs are NOT bundled) — the
/// provider token is then exchanged at `POST /auth/social`.
final class LiveAuthService: AuthService {
    private let api: APIClient
    private let tokens: TokenStore

    init(api: APIClient, tokens: TokenStore) {
        self.api = api
        self.tokens = tokens
    }

    private struct SessionDTO: Decodable {
        var user: User
        var accessToken: String
        var refreshToken: String?
    }

    private func store(_ dto: SessionDTO) -> Session {
        tokens.accessToken = dto.accessToken
        tokens.refreshToken = dto.refreshToken
        return Session(user: dto.user, accessToken: dto.accessToken, refreshToken: dto.refreshToken)
    }

    /// Validates a Keychain session against the server after reopening the app.
    func restoreSession() async -> Session? {
        guard let token = tokens.accessToken else { return nil }
        do {
            let user: User = try await api.send(.get, "me")
            return Session(user: user, accessToken: token, refreshToken: nil)
        } catch AppError.unauthorized {
            tokens.accessToken = nil
            return nil
        } catch {
            // Do not erase a valid session merely because the server is temporarily offline.
            return nil
        }
    }

    func signIn(email: String, password: String) async throws -> Session {
        struct Body: Encodable { var email: String; var password: String }
        do {
            let dto: SessionDTO = try await api.send(.post, "auth/login", body: Body(email: email, password: password))
            return store(dto)
        } catch AppError.unauthorized {
            throw AppError.invalidCredentials
        }
    }

    /// Registers and signs in immediately; the backend returns a session (no email code).
    func signUp(_ request: SignUpRequest) async throws -> Session {
        let dto: SessionDTO = try await api.send(.post, "auth/register", body: request)
        return store(dto)
    }

    func requestPasswordReset(email: String) async throws {
        struct Body: Encodable { var email: String }
        let _: APIClient.Empty = try await api.send(.post, "auth/password/forgot", body: Body(email: email))
    }

    func resetPassword(token: String, newPassword: String) async throws {
        struct Body: Encodable { var token: String; var newPassword: String }
        let _: APIClient.Empty = try await api.send(.post, "auth/password/reset", body: Body(token: token, newPassword: newPassword))
    }

    func socialSignIn(_ provider: AuthProvider) async throws -> SocialSignInResult {
        // TODO(backend + SDK): obtain the provider identity token natively, then:
        // POST /auth/social { provider, id_token } → 200 session | 202 needs_profile | 409 existing_account
        throw AppError.server("تسجيل الدخول عبر \(provider.displayName) غير مهيأ في هذه النسخة.")
    }

    func completeProfile(displayName: String) async throws -> Session {
        struct Body: Encodable { var displayName: String }
        let dto: SessionDTO = try await api.send(.patch, "me", body: Body(displayName: displayName))
        return store(dto)
    }

    func mergeGuestData(_ summary: GuestDataSummary) async throws -> GuestDataSummary {
        try await api.send(.post, "me/merge-guest-data", body: summary)
    }

    func signOut() async {
        if tokens.accessToken != nil {
            let _: APIClient.Empty? = try? await api.send(.post, "auth/logout")
        }
        tokens.accessToken = nil
        tokens.refreshToken = nil
    }
}
