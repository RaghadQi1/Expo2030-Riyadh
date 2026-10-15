import SwiftUI

/// Onboarding / 01 Discover, 02 AI Plan, 03 Share Location.
struct OnboardingView: View {
    var onFinish: () -> Void

    struct Page: Identifiable {
        let id: Int
        let hero: String
        let heroHeight: CGFloat
        let title: String
        let body: String
        let primary: String
    }

    private let pages: [Page] = [
        Page(id: 0, hero: "onboarding-hero-discover", heroHeight: 600,
             title: "إكسبو على اهتماماتك",
             body: "اكتشف الأجنحة والفعاليات، واختر ما يناسبك.", primary: "التالي"),
        Page(id: 1, hero: "onboarding-hero-ai-plan", heroHeight: 680,
             title: "جولتك بذكاء",
             body: "دع الذكاء الاصطناعي يرتّب وجهاتك في خريطة تناسبك.", primary: "التالي"),
        Page(id: 2, hero: "onboarding-hero-share-location", heroHeight: 623,
             title: "شارك موقعك بسهولة",
             body: "أنشئ رمز QR لموقعك، وخلّ الوصول إليك أسهل.", primary: "ابدأ رحلتك"),
    ]

    @State private var index = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.bgCanvas.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(pages) { page in
                    Image(page.hero)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: page.heroHeight, alignment: .top)
                        .clipped()
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .tag(page.id)
                        .accessibilityHidden(true)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if index < pages.count - 1 {
                        Button("تخطّي", action: onFinish)
                            .textStyle(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(Color.bgSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.borderDefault, lineWidth: 1))
                            .shadow(color: Color(red: 13 / 255, green: 38 / 255, blue: 26 / 255).opacity(0.08), radius: 2, y: 2)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 10)
                .environment(\.layoutDirection, .leftToRight) // «تخطّي» sits top-left in the design

                Spacer()

                content(for: pages[index])
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: index)
    }

    private func content(for page: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingStepIndicator(current: page.id, total: pages.count)
            Spacer().frame(height: 16)
            Text(page.title)
                .textStyle(.largeTitle)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(height: 8)
            Text(page.body)
                .textStyle(.body)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            Spacer().frame(height: 24)
            HStack(spacing: 12) {
                Button(page.primary) {
                    if index < pages.count - 1 { index += 1 } else { onFinish() }
                }
                .appButton(.primary)

                if index > 0 {
                    Button {
                        index -= 1
                    } label: {
                        Icon(.chevronRight, size: 24, color: .brandPrimary)
                            .frame(width: 52, height: 52)
                            .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("رجوع")
                }
            }
        }
    }
}

/// «Onboarding/Step Indicator»: counter + three dots, first step on the right, current = elongated green.
struct OnboardingStepIndicator: View {
    let current: Int
    let total: Int

    private let arabicDigits = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]

    var body: some View {
        HStack(spacing: 12) {
            Text("\(arabicDigits[current + 1]) من \(arabicDigits[total])")
                .textStyle(.caption)
                .foregroundStyle(Color.brandPrimary)
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i == current ? Color.brandPrimary : Color.borderStrong)
                        .frame(width: i == current ? 22 : 6, height: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الخطوة \(current + 1) من \(total)")
    }
}
