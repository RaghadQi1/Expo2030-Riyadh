import SwiftUI

/// 06.02 Filled (keyboard, AutoFill) · 06.03 Field errors · 06.04 Wrong credentials · 06.05 Loading.
struct EmailSignInView: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router

    @State private var email = ""
    @State private var password = ""
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var banner: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("تسجيل الدخول بالبريد")
                    .textStyle(.title1)
                    .foregroundStyle(Color.textPrimary)

                if let banner {
                    StatusBanner(text: banner, tone: .error)
                        .transition(.opacity)
                }

                AppTextField(label: "البريد الإلكتروني", text: $email, kind: .email,
                             placeholder: "name@example.com", icon: .mail, error: emailError)
                    .onChange(of: email) { emailError = nil; banner = nil }
                AppTextField(label: "كلمة المرور", text: $password, kind: .password,
                             error: passwordError, submitLabel: .go, onSubmit: { Task { await submit() } })
                    .onChange(of: password) { passwordError = nil; banner = nil }

                HStack {
                    Button("نسيت كلمة المرور؟") { router.push(.forgotPassword(prefill: email)) }
                        .textStyle(.footnote)
                        .foregroundStyle(Color.textLink)
                        .buttonStyle(.plain)
                    Spacer()
                    Text("الملء التلقائي لكلمة المرور متاح")
                        .textStyle(.caption)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer().frame(height: 8)

                Button("الدخول") { Task { await submit() } }
                    .appButton(.primary, isLoading: isLoading)
                    .disabled(isLoading)

                HStack(spacing: 4) {
                    Text("ليس لديك حساب؟").foregroundStyle(Color.textSecondary)
                    Button("أنشئ حسابًا") { router.push(.createAccount) }
                        .foregroundStyle(Color.textLink)
                        .buttonStyle(.plain)
                }
                .textStyle(.footnote)
                .frame(maxWidth: .infinity)

                if services.environment.isMock {
                    Text("حساب للاختبار: \(MockUsers.noura.email) · \(MockUsers.demoPassword)")
                        .textStyle(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome()
        .animation(.easeInOut(duration: 0.2), value: banner)
    }

    @MainActor
    private func submit() async {
        banner = nil
        emailError = Validators.isValidEmail(email) ? nil : "أدخل بريدًا إلكترونيًا صحيحًا، مثل name@example.com"
        passwordError = password.isEmpty ? "أدخل كلمة المرور" : nil
        guard emailError == nil, passwordError == nil else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await services.auth.signIn(email: email, password: password)
            app.signedIn(session, startPersonalization: true)
        } catch AppError.invalidCredentials {
            banner = "البريد أو كلمة المرور غير صحيحة. تحقق منهما وحاول مرة أخرى."
        } catch let error as AppError {
            banner = error.message
        } catch {
            banner = AppError.unknown.message
        }
    }
}
