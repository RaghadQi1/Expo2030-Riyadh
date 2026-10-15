import Foundation

enum AuthProvider: String, Codable, Hashable {
    case email, apple, google, facebook

    var displayName: String {
        switch self {
        case .email: "البريد الإلكتروني"
        case .apple: "Apple"
        case .google: "Google"
        case .facebook: "Facebook"
        }
    }
}

struct User: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var email: String
    var avatarAsset: String?
    var provider: AuthProvider
    var isEmailVerified: Bool
    /// Apple "Hide My Email" relay address (06.18).
    var usesPrivateRelayEmail: Bool = false
}

struct Session: Codable, Hashable {
    var user: User?
    var accessToken: String?
    var refreshToken: String?

    var isGuest: Bool { user == nil }
    static let guest = Session(user: nil, accessToken: nil, refreshToken: nil)
}

/// Result of a social sign-in attempt (06.18 – 06.20 + cancel / failure toasts).
enum SocialSignInResult: Hashable {
    case signedIn(Session)
    /// Provider did not return a display name → «أكمل بياناتك» (06.19).
    case needsProfileCompletion(partial: User)
    /// An account already exists with this email using another method (06.20).
    case existingAccount(email: String, existingProvider: AuthProvider)
    case cancelled
}

struct SignUpRequest: Codable, Hashable {
    var name: String
    var email: String
    var password: String
    var acceptedTerms: Bool
    var marketingOptIn: Bool
}

/// What a guest created before signing up (06.24 merge success).
struct GuestDataSummary: Codable, Hashable {
    var hasPlan: Bool
    var hasPreferences: Bool
    var notesCount: Int
    var photosCount: Int
    var savedPavilionsCount: Int
}

enum PasswordRule: CaseIterable {
    case minLength, mixedCase, digit, notEmail

    var text: String {
        switch self {
        case .minLength: "8 أحرف على الأقل"
        case .mixedCase: "حرف كبير وحرف صغير (A/a)"
        case .digit: "رقم واحد على الأقل"
        case .notEmail: "لا تستخدم بريدك الإلكتروني كجزء منها"
        }
    }

    var isAdvisory: Bool { self == .notEmail }

    func isMet(password: String, email: String) -> Bool {
        switch self {
        case .minLength: password.count >= 8
        case .mixedCase: password.rangeOfCharacter(from: .uppercaseLetters) != nil && password.rangeOfCharacter(from: .lowercaseLetters) != nil
        case .digit: password.rangeOfCharacter(from: .decimalDigits) != nil
        case .notEmail:
            email.split(separator: "@").first.map { !$0.isEmpty && password.lowercased().contains($0.lowercased()) } != true
        }
    }
}

enum Validators {
    static func isValidEmail(_ s: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    static func isStrongPassword(_ p: String, email: String) -> Bool {
        PasswordRule.allCases.filter { !$0.isAdvisory }.allSatisfy { $0.isMet(password: p, email: email) }
    }
}
