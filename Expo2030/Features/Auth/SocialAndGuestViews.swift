import SwiftUI

/// 06.18 Apple Sign-in — Hidden email (Private Relay).
struct AppleHiddenEmailView: View {
    let session: Session
    @Environment(AppState.self) private var app

    var body: some View {
        CenteredStatusLayout(icon: .lock, title: "أهلًا \(session.user?.name ?? "")!",
                             message: "اخترت إخفاء بريدك. سنراسلك عبر العنوان الخاص من Apple، ويمكنك تعطيله متى شئت من إعدادات Apple ID.") {
            VStack(spacing: 14) {
                Text(session.user?.email ?? "")
                    .font(AppFont.latin(13, .regular, relativeTo: .footnote))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, -14)
                Spacer().frame(height: 0)
                Button("متابعة") { app.signedIn(session, startPersonalization: true) }
                    .appButton(.primary)
                Text("لا توجد كلمة مرور لهذا الحساب — تسجيل الدخول يتم دائمًا عبر Apple.")
                    .textStyle(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 06.19 Social Sign-in — Complete missing info.
struct CompleteProfileView: View {
    let user: User
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorBanner: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("أكمل بياناتك")
                    .textStyle(.title1)
                    .foregroundStyle(Color.textPrimary)
                Text("لم يشارك \(user.provider.displayName) اسمك. نحتاج اسمًا لعرضه لأصدقائك عند مشاركة الموقع فقط.")
                    .textStyle(.body)
                    .foregroundStyle(Color.textSecondary)
                if let errorBanner { StatusBanner(text: errorBanner, tone: .error) }
                AppTextField(label: "الاسم الظاهر", text: $displayName, kind: .name,
                             helper: "يمكنك استخدام اسمك الأول فقط", submitLabel: .done)
                AppTextField(label: "البريد الإلكتروني", text: .constant(user.email), kind: .email, icon: .mail,
                             helper: "من \(user.provider.displayName) · لا يمكن تعديله هنا", isDisabled: true)
                    .opacity(0.6)
                Button("حفظ ومتابعة") { Task { await save() } }
                    .appButton(.primary, isLoading: isLoading)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome()
    }

    @MainActor
    private func save() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await services.auth.completeProfile(displayName: displayName)
            app.signedIn(session, startPersonalization: true)
        } catch let error as AppError {
            errorBanner = error.message
        } catch {
            errorBanner = AppError.unknown.message
        }
    }
}

/// 06.20 Social Sign-in — Existing account conflict. Accounts are never merged on email match alone.
struct AccountConflictView: View {
    let email: String
    let existingProvider: AuthProvider
    let attemptedProvider: AuthProvider
    @Environment(AuthRouter.self) private var router

    var body: some View {
        CenteredStatusLayout(icon: .warning, iconTint: .statusWarning, iconBackground: .statusWarningBg,
                             title: "لديك حساب بهذا البريد", titleStyle: .title2,
                             message: "البريد \(email) مرتبط بحساب أنشأته بالبريد وكلمة المرور. للربط بـ \(attemptedProvider.displayName)، سجّل الدخول بالطريقة الأصلية أولًا لتأكيد أنك صاحب الحساب.") {
            Button("الدخول بالبريد") {
                router.popToRoot()
                router.push(.emailSignIn)
            }
            .appButton(.primary)
            Button("استخدام طريقة أخرى") { router.popToRoot() }
                .appButton(.tertiary)
            Text("لا ندمج الحسابات بمجرد تطابق البريد.")
                .textStyle(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .appNavigationChrome()
    }
}

/// 06.24 Guest → Account — Merge success.
struct MergeSuccessView: View {
    let summary: GuestDataSummary
    @Environment(AppState.self) private var app

    private var rows: [String] {
        var r: [String] = []
        if summary.hasPlan { r.append("خطة اليوم") }
        if summary.hasPreferences { r.append("التفضيلات والاهتمامات") }
        if summary.notesCount > 0 || summary.photosCount > 0 {
            r.append("\(summary.notesCount) ملاحظات و\(summary.photosCount) صورة")
        }
        if summary.savedPavilionsCount > 0 { r.append("الأجنحة المحفوظة (\(summary.savedPavilionsCount))") }
        return r
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                IllustrationBadge(icon: .check, tint: .statusSuccess, background: .brandMint)
                Text("كل شيء في حسابك الآن")
                    .textStyle(.title2)
                    .foregroundStyle(Color.textPrimary)
                VStack(spacing: 0) {
                    ForEach(rows, id: \.self) { row in
                        HStack(spacing: 8) {
                            Icon(.check, size: 16, color: .brandPrimary)
                            Text(row).textStyle(.subhead).foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text("تم").textStyle(.caption).foregroundStyle(Color.statusSuccess)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let pending = app.pendingGuestAction {
                    Button(pending.title) {
                        app.selectedTab = pending.resumeTab
                        app.pendingGuestAction = nil
                        app.isAuthPresented = false
                        app.phase = .main
                    }
                    .appButton(.primary)
                    Text("أكملنا الإجراء الذي بدأته قبل التسجيل.")
                        .textStyle(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    Button("متابعة") {
                        app.isAuthPresented = false
                        app.phase = .main
                    }
                    .appButton(.primary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 140)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// 06.26 Guest — Sign-up cancelled, data kept.
struct GuestSignUpCancelledView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        CenteredStatusLayout(icon: .lock, title: "ما زلت في وضع الضيف", titleStyle: .title2,
                             message: "ألغيت إنشاء الحساب. خطتك وملاحظاتك محفوظة على هذا الجهاز كما هي، ولم تبدأ مشاركة الموقع.",
                             topPadding: 140) {
            Button("العودة إلى الرئيسية") {
                app.pendingGuestAction = nil
                app.isAuthPresented = false
                app.selectedTab = .discover
                app.phase = .main
            }
            .appButton(.primary)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
