import SwiftUI

/// Figma "Navigation Bar" (1:2858): 52pt, bg/canvas-translucent, back chevron on the RIGHT (RTL),
/// centered AR/Headline title, trailing actions on the left.
/// Used for screens presented outside a NavigationStack (full-screen covers / sheets).
/// Inside a NavigationStack prefer the system bar + `.appNavigationChrome()`.
struct AppNavBar<Trailing: View>: View {
    var title: String = ""
    var showsBack = true
    var backIcon: AppIcon = .chevronRight
    var onBack: () -> Void = {}
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(title)
                .textStyle(.headline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: 240)
            HStack {
                if showsBack {
                    Button(action: onBack) {
                        Icon(backIcon, size: 24, color: .textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("رجوع")
                }
                Spacer()
                trailing()
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 52)
        .background(Color.bgCanvasTranslucent)
    }
}

extension AppNavBar where Trailing == EmptyView {
    init(title: String = "", showsBack: Bool = true, backIcon: AppIcon = .chevronRight, onBack: @escaping () -> Void = {}) {
        self.init(title: title, showsBack: showsBack, backIcon: backIcon, onBack: onBack, trailing: { EmptyView() })
    }
}

extension View {
    /// System navigation bar styled like the Figma Navigation Bar.
    func appNavigationChrome(title: String = "") -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.bgCanvasTranslucent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// Sheet grabber (36×5, border/strong) used at the top of custom bottom sheets.
struct SheetGrabber: View {
    var color: Color = .borderStrong
    var width: CGFloat = 36
    var body: some View {
        Capsule().fill(color).frame(width: width, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .accessibilityHidden(true)
    }
}

/// Section header «المحاور ……… الكل»: AR/Title 3 title + optional link (AR/Footnote, text/link).
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        HStack {
            Text(title)
                .textStyle(.title3)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .textStyle(.footnote)
                    .foregroundStyle(Color.textLink)
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Large screen title (AR/Title 1, Bold 26) used by tab roots («خطتي», «رحلتي», «حسابي»).
struct ScreenTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .textStyle(.title1)
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Circular badge with an icon (e.g. success check, mail, clock on verification screens):
/// 88pt rounded square with brand/mint (or status) fill.
struct IllustrationBadge: View {
    let icon: AppIcon
    var tint: Color = .brandPrimary
    var background: Color = .brandMint
    var size: CGFloat = 88
    var iconSize: CGFloat = 40

    var body: some View {
        Icon(icon, size: iconSize, color: tint)
            .frame(width: size, height: size)
            .background(background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityHidden(true)
    }
}
