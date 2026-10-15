import SwiftUI

/// Text styles defined in the Figma file (AR/* uses IBM Plex Sans Arabic, EN/* uses IBM Plex Sans).
/// Sizes are the Figma point sizes; every style scales with Dynamic Type through `relativeTo:`.
/// IBM Plex Sans Arabic has a natural line height of 1.5 × size, which already matches the
/// Figma line heights (e.g. 17/26, 19/28), so only multi-line styles add extra spacing.
enum AppTextStyle: CaseIterable {
    case largeTitle      // AR/Large Title   – 32 Bold     / 45
    case title1          // AR/Title 1       – 26 Bold     / 36
    case title2          // AR/Title 2       – 22 SemiBold / 32
    case title3          // AR/Title 3       – 19 SemiBold / 28
    case headline        // AR/Headline      – 17 SemiBold / 26
    case body            // AR/Body          – 16 Regular  / 26
    case bodyStrong      // AR/Body Strong   – 16 Medium   / 26
    case subhead         // AR/Subhead       – 14 Regular  / 22
    case subheadStrong   // AR/Subhead Strong– 14 Medium   / 22
    case footnote        // AR/Footnote      – 13 Regular  / 20
    case caption         // AR/Caption       – 12 Medium   / 17
    case caption2        // AR/Caption 2     – 11 Medium   / 15
    case enHeadline      // EN/Headline      – 17 SemiBold / 22 (times, numbers)
    case enCaption       // EN/Caption       – 12 Medium   / 15
    case enBody          // EN/Body          – 16 Regular  / 22 (emails, URLs, codes)
    case button          // AR/Button        – 16 SemiBold / 22

    var size: CGFloat {
        switch self {
        case .largeTitle: 32
        case .title1: 26
        case .title2: 22
        case .title3: 19
        case .headline, .enHeadline: 17
        case .body, .bodyStrong, .enBody, .button: 16
        case .subhead, .subheadStrong: 14
        case .footnote: 13
        case .caption, .enCaption: 12
        case .caption2: 11
        }
    }

    var weight: AppFont.Weight {
        switch self {
        case .title1, .largeTitle: .bold
        case .title2, .title3, .headline, .enHeadline: .semibold
        case .body, .subhead, .footnote, .enBody: .regular
        case .button: .semibold
        case .bodyStrong, .subheadStrong, .caption, .caption2, .enCaption: .medium
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .largeTitle: 45
        case .title1: 36
        case .title2: 32
        case .title3: 28
        case .headline, .body, .bodyStrong: 26
        case .subhead, .subheadStrong: 22
        case .footnote: 20
        case .caption: 17
        case .caption2, .enCaption: 15
        case .enHeadline, .enBody, .button: 22
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline, .enHeadline: .headline
        case .body, .bodyStrong, .enBody, .button: .body
        case .subhead, .subheadStrong: .subheadline
        case .footnote: .footnote
        case .caption, .enCaption: .caption
        case .caption2: .caption2
        }
    }

    var isLatin: Bool { self == .enHeadline || self == .enCaption || self == .enBody }

    var font: Font {
        isLatin ? AppFont.latin(size, weight, relativeTo: relativeTo)
                : AppFont.arabic(size, weight, relativeTo: relativeTo)
    }

    /// Extra spacing between lines so wrapped text matches the Figma line height.
    var lineSpacing: CGFloat {
        let natural = size * (isLatin ? 1.3 : 1.5)
        return max(0, lineHeight - natural)
    }
}

enum AppFont {
    enum Weight { case regular, medium, semibold, bold }

    static func arabic(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String = switch weight {
        case .regular: "IBMPlexSansArabic-Regular"
        case .medium: "IBMPlexSansArabic-Medium"
        case .semibold: "IBMPlexSansArabic-SemiBold"
        case .bold: "IBMPlexSansArabic-Bold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// IBM Plex Sans (Latin) — static instances generated from the OFL variable font.
    static func latin(_ size: CGFloat, _ weight: Weight, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String = switch weight {
        case .regular: "IBMPlexSansRoman-Regular"
        case .medium: "IBMPlexSansRoman-Medium"
        case .semibold, .bold: "IBMPlexSansRoman-SemiBold"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension View {
    /// Applies one of the Figma text styles (font + line spacing).
    func textStyle(_ style: AppTextStyle) -> some View {
        font(style.font).lineSpacing(style.lineSpacing)
    }
}
