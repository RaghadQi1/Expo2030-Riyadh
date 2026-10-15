import SwiftUI
import Combine

/// 06.11 Forgot Password — Enter email.
struct ForgotPasswordView: View {
    @State var email: String
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("استعادة كلمة المرور")
                    .textStyle(.title1)
                    .foregroundStyle(Color.textPrimary)
                Text("أدخل بريد حسابك وسنرسل رابط إعادة التعيين إن كان مسجلًا لدينا.")
                    .textStyle(.body)
                    .foregroundStyle(Color.textSecondary)
                AppTextField(label: "البريد الإلكتروني", text: $email, kind: .email,
                             placeholder: "name@example.com", icon: .mail, error: error, submitLabel: .send)
                    .onChange(of: email) { error = nil }
                Button("إرسال الرابط") { Task { await send() } }
                    .appButton(.primary, isLoading: isLoading)
                    .disabled(isLoading)
                StatusBanner(text: "سجّلت بـ Apple أو Google أو Facebook؟ لا توجد كلمة مرور محلية — استخدم زر المزود نفسه.",
                             tone: .info)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome()
    }

    @MainActor
    private func send() async {
        guard Validators.isValidEmail(email) else {
            error = "أدخل بريدًا إلكترونيًا صحيحًا، مثل name@example.com"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await services.auth.requestPasswordReset(email: email)
            router.push(.forgotPasswordSent(email: email))
        } catch {
            self.error = (error as? AppError)?.message ?? "استعادة كلمة المرور غير متاحة حتى إعداد خدمة البريد."
        }
    }
}

/// 06.12 Forgot Password — Generic confirmation (does not reveal account existence).
struct ForgotPasswordSentView: View {
    let email: String
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router
    @State private var secondsUntilResend = 58

    var body: some View {
        CenteredStatusLayout(icon: .mail, title: "تحقق من بريدك",
                             message: "إذا كان هناك حساب مرتبط بهذا البريد، فستصلك رسالة تحتوي رابط إعادة التعيين خلال دقائق. الرابط صالح لمدة 30 دقيقة.",
                             topPadding: 106) {
            Button("العودة لتسجيل الدخول") {
                router.popToRoot()
                router.push(.emailSignIn)
            }
            .appButton(.primary)

            if secondsUntilResend > 0 {
                Text("لم تصلك رسالة؟ أعد الإرسال بعد \(secondsUntilResend) ثانية")
                    .textStyle(.footnote)
                    .foregroundStyle(Color.textTertiary)
            } else {
                Button("لم تصلك رسالة؟ أعد الإرسال") {
                    Task {
                        try? await services.auth.requestPasswordReset(email: email)
                        secondsUntilResend = 60
                    }
                }
                .textStyle(.footnote)
                .foregroundStyle(Color.textLink)
                .buttonStyle(.plain)
            }

            if services.environment.isMock {
                VStack(spacing: 8) {
                    DemoModeBadge()
                    Button("محاكاة فتح رابط إعادة التعيين") { router.push(.resetPassword(email: email)) }
                        .appButton(.tertiary, height: 40)
                }
                .padding(.top, 12)
            }
        }
        .appNavigationChrome()
        .onAppear { secondsUntilResend = 58 }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if secondsUntilResend > 0 { secondsUntilResend -= 1 }
        }
    }
}

/// 06.13 Reset Password — New password (button disabled until both match & are strong).
struct ResetPasswordView: View {
    let email: String
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var isLoading = false
    @State private var errorBanner: String?

    private var isStrong: Bool { Validators.isStrongPassword(newPassword, email: email) }
    private var mismatch: Bool { !confirm.isEmpty && confirm != newPassword }

    private var strengthHelper: String? {
        guard !newPassword.isEmpty else { return "8 أحرف على الأقل، حرف كبير وصغير ورقم" }
        return isStrong ? "قوية ✓ · \(newPassword.count) حرفًا" : "ضعيفة · أضف حروفًا كبيرة وصغيرة ورقمًا"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("كلمة مرور جديدة")
                    .textStyle(.title1)
                    .foregroundStyle(Color.textPrimary)
                (Text("للحساب ") + Text(email).font(AppTextStyle.enCaption.font))
                    .textStyle(.footnote)
                    .foregroundStyle(Color.textSecondary)
                if let errorBanner { StatusBanner(text: errorBanner, tone: .error) }
                AppTextField(label: "كلمة المرور الجديدة", text: $newPassword, kind: .newPassword, helper: strengthHelper)
                AppTextField(label: "تأكيد كلمة المرور", text: $confirm, kind: .newPassword,
                             error: mismatch ? "كلمتا المرور غير متطابقتين" : nil, submitLabel: .done)
                Button("حفظ كلمة المرور") { Task { await save() } }
                    .appButton(.primary, isLoading: isLoading)
                    .disabled(!isStrong || confirm != newPassword || isLoading)
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
            try await services.auth.resetPassword(token: "from-universal-link", newPassword: newPassword)
            router.push(.resetPasswordSuccess)
        } catch let error as AppError {
            errorBanner = error.message
        } catch {
            errorBanner = AppError.unknown.message
        }
    }
}

/// 06.14 Reset Password — Success.
struct ResetPasswordSuccessView: View {
    @Environment(AuthRouter.self) private var router

    var body: some View {
        CenteredStatusLayout(icon: .lock, iconTint: .statusSuccess, iconBackground: .statusSuccessBg,
                             title: "تم تحديث كلمة المرور",
                             message: "سجّلنا خروجك من الأجهزة الأخرى لحماية حسابك.",
                             topPadding: 146) {
            Button("تسجيل الدخول") {
                router.popToRoot()
                router.push(.emailSignIn)
            }
            .appButton(.primary)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
