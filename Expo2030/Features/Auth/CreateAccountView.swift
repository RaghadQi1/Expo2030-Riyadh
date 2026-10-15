import SwiftUI

/// 06.07 Create Account (+ 06.26 when a guest cancels sign-up).
struct CreateAccountView: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var acceptedTerms = false
    @State private var marketing = false
    @State private var isLoading = false
    @State private var emailError: String?
    @State private var errorBanner: String?

    private var rules: [PasswordRequirementsView.Rule] {
        PasswordRule.allCases.map {
            .init(text: $0.text, met: $0.isMet(password: password, email: email), advisory: $0.isAdvisory)
        }
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Validators.isValidEmail(email)
            && Validators.isStrongPassword(password, email: email) && acceptedTerms
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("إنشاء حساب")
                    .textStyle(.title1)
                    .foregroundStyle(Color.textPrimary)

                if let errorBanner {
                    StatusBanner(text: errorBanner, tone: .error)
                }

                AppTextField(label: "الاسم", text: $name, kind: .name)
                AppTextField(label: "البريد الإلكتروني", text: $email, kind: .email,
                             placeholder: "name@example.com", icon: .mail, error: emailError)
                    .onChange(of: email) { emailError = nil }
                AppTextField(label: "كلمة المرور", text: $password, kind: .newPassword,
                             helper: "كلمة مرور قوية مقترحة من iCloud Keychain متاحة")
                PasswordRequirementsView(rules: rules)

                CheckboxRow(title: "أوافق على الشروط وأقرّ بقراءة سياسة الخصوصية (مطلوب)", isOn: $acceptedTerms)
                CheckboxRow(title: "أرغب في تلقي أخبار وعروض إكسبو بالبريد (اختياري)", isOn: $marketing)

                Button("إنشاء الحساب") { Task { await submit() } }
                    .appButton(.primary, isLoading: isLoading)
                    .disabled(!canSubmit || isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome()
        .navigationBarBackButtonHidden(app.isGuest && app.phase == .main)
        .toolbar {
            if app.isGuest && app.phase == .main {
                // A guest who started sign-up from inside the app can cancel → 06.26.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.replaceTop(with: .guestSignUpCancelled)
                    } label: {
                        Icon(.chevronRight, size: 24, color: .textPrimary)
                    }
                    .accessibilityLabel("رجوع")
                }
            }
        }
    }

    @MainActor
    private func submit() async {
        guard Validators.isValidEmail(email) else {
            emailError = "أدخل بريدًا إلكترونيًا صحيحًا، مثل name@example.com"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await services.auth.signUp(SignUpRequest(name: name, email: email, password: password,
                                                                        acceptedTerms: acceptedTerms, marketingOptIn: marketing))
            // Account is ready immediately, with no email code or external mail application.
            app.signedIn(session, startPersonalization: true)
        } catch let error as AppError {
            errorBanner = error.message
        } catch {
            errorBanner = AppError.unknown.message
        }
    }
}
