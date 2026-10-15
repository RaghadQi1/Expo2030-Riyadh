import SwiftUI

/// 13.07 AI draft summary. It is a draft: nothing is saved until «حفظ الملخص», and original notes never change.
struct JourneySummaryView: View {
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toasts
    @State private var summary: Loadable<JourneySummary> = .idle
    @State private var saving = false
    @State private var savedOnce = false

    var body: some View {
        Group {
            switch summary {
            case .idle, .loading:
                LoadingStateView(title: "مساعد إكسبو يكتب مسودة ملخصك…")
                    .frame(maxHeight: .infinity)
            case .failed(let e):
                ErrorStateView(error: e) { Task { await load() } }
                    .frame(maxHeight: .infinity)
            case .loaded(let s):
                content(s)
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "ملخص الرحلة")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task { if summary.value == nil { await load() } }
    }

    private func content(_ s: JourneySummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(s.title).textStyle(.caption).foregroundStyle(Color.white.opacity(0.8))
                    Text(s.subtitle).textStyle(.title2).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        heroChip(s.priority)
                        heroChip(s.distance)
                        heroChip(s.duration)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [Color.brandPrimary, Color.brandPrimaryPressed], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                HStack(spacing: 6) {
                    Icon(.sparkles, size: 14, color: .textSecondary)
                    Text("مسودة من مساعد إكسبو · راجعها قبل الحفظ").textStyle(.caption).foregroundStyle(Color.textSecondary)
                }

                section("ما تعلمته", s.learned)
                section("ما أثار اهتمامي", s.interesting)
                section("خطواتي القادمة", s.nextSteps)

                Text("لن نضيف مهارات إلى سيرتك أو ملفك المهني تلقائيًا. ملاحظاتك الأصلية محفوظة كما هي.")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.screen)
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    Button(savedOnce ? "حُفظ الملخص" : "حفظ الملخص") { Task { await save(s) } }
                        .appButton(.primary, isLoading: saving)
                        .disabled(savedOnce)
                    ShareLink(item: shareText(s)) { Text("مشاركة") }
                        .appButton(.mint)
                        .frame(width: 130)
                }
            }
        }
    }

    private func heroChip(_ text: String) -> some View {
        Text(text).textStyle(.caption).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.white.opacity(0.16), in: Capsule())
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).textStyle(.headline).foregroundStyle(Color.brandPrimary)
            ForEach(items, id: \.self) { item in
                Text("• \(item)").textStyle(.subhead).foregroundStyle(Color.textPrimary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: 20)
    }

    private func shareText(_ s: JourneySummary) -> String {
        ([s.title, s.subtitle, "", "ما تعلمته:"] + s.learned.map { "• \($0)" }
         + ["", "ما أثار اهتمامي:"] + s.interesting.map { "• \($0)" }
         + ["", "خطواتي القادمة:"] + s.nextSteps.map { "• \($0)" }).joined(separator: "\n")
    }

    @MainActor private func load() async {
        summary = .loading
        do { summary = .loaded(try await services.journey.summary()) }
        catch let e as AppError { summary = .failed(e) } catch { summary = .failed(.unknown) }
    }

    @MainActor private func save(_ s: JourneySummary) async {
        saving = true
        defer { saving = false }
        do {
            try await services.journey.saveSummary(s)
            savedOnce = true
            toasts.show("حُفظ الملخص في «حسابي ← ملخصات رحلاتي»")
        } catch {
            toasts.show((error as? AppError)?.message ?? "تعذّر حفظ الملخص", icon: .warning, iconColor: .statusError)
        }
    }
}
