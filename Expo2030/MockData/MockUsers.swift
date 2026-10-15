import Foundation

/// Demo people used across the design (names are from the Figma file).
enum MockUsers {
    static let demoPassword = "Expo2030!"

    static let noura = User(id: "u-noura", name: "نورة القحطاني", email: "noura@example.com",
                            avatarAsset: nil, provider: .email, isEmailVerified: true)

    static let newAccount = User(id: "u-new", name: "نورة القحطاني", email: "noura@gmail.com",
                                 avatarAsset: nil, provider: .email, isEmailVerified: true)

    /// Account shown on «حسابي» (16.01).
    static let sadeem = User(id: "u-sadeem", name: "سديم الحربي", email: "Sadeem@example.com",
                             avatarAsset: "avatar-sadeem", provider: .email, isEmailVerified: true)

    static let sadeemApple = User(id: "u-sadeem-apple", name: "سديم", email: "x7k2p9q4mz@privaterelay.appleid.com",
                                  avatarAsset: "avatar-sadeem", provider: .apple, isEmailVerified: true,
                                  usesPrivateRelayEmail: true)

    static let facebookPartial = User(id: "u-fb", name: "", email: "noura@example.com",
                                      avatarAsset: nil, provider: .facebook, isEmailVerified: true)
}
