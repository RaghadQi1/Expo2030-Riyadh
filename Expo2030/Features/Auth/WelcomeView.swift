import SwiftUI

/// 06.01 Welcome — Choose sign-in method, including its three states in the file:
/// default, Google connection failure banner, Apple sign-in cancelled toast.
struct WelcomeView: View {
    var isModal = false

    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(AuthRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var showGuestSheet = false
    @State private var showAppleSimulation = false
    @State private var socialLoading: AuthProvider?
    @State private var failure: (provider: AuthProvider, error: AppError)?
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .top) {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Image("logo-expo-riyadh")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: 190, height: 70.9)
                        .accessibilityLabel("إكسبو 2030 الرياض")
                    Spacer().frame(height: 4)
                    Text("أهلًا بك في إكسبو الرياض")
                        .textStyle(.title1)
                        .foregroundStyle(Color.textLink)
                    Text("سجّل دخولك لمزامنة خطتك وملاحظاتك عبر أجهزتك، أو تابع كضيف.")
                        .textStyle(.subhead)
                        .foregroundStyle(Color.brandOnPrimary)
                    Spacer().frame(height: 4)

                    Button("تسجيل الدخول") { router.push(.emailSignIn) }
                        .appButton(.primary)
                    Button("إنشاء حساب") { router.push(.createAccount) }
                        .appButton(.secondary)
                    Button("المتابعة كضيف") { showGuestSheet = true }
                        .appButton(.text)

                    HStack(spacing: 12) {
                        Rectangle().fill(Color.bgSurface).frame(height: 1)
                        Text("أو").textStyle(.footnote).foregroundStyle(Color.textTertiary)
                        Rectangle().fill(Color.bgSurface).frame(height: 1)
                    }

                    HStack(spacing: 20) {
                        socialButton(.google, asset: "logo-google", label: "تسجيل الدخول عبر Google")
                        socialButton(.apple, asset: "logo-apple", label: "تسجيل الدخول عبر Apple")
                        socialButton(.facebook, asset: "logo-facebook", label: "تسجيل الدخول عبر Facebook")
                    }
                    .frame(maxWidth: .infinity)

                    Text("بالمتابعة، أنت توافق على الشروط وسياسة الخصوصية.")
                        .textStyle(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(width: 247)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 176)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Error banner (06.01 · Google failure) / cancel toast (06.01 · Apple cancelled)
            VStack {
                if let failure {
                    StatusBanner(text: "تعذّر الاتصال بـ \(failure.provider.displayName). تحقق من الإنترنت ثم حاول مجددًا، أو تابع كضيف.",
                                 tone: .error, actionTitle: "إعادة المحاولة") {
                        self.failure = nil
                        Task { await socialSignIn(failure.provider) }
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let toast {
                    ToastView(toast: ToastMessage(text: toast, icon: .undo, iconColor: .textPrimary))
                        .padding(.horizontal, 42)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 50)
            .animation(.spring(duration: 0.35), value: failure?.provider)
            .animation(.spring(duration: 0.35), value: toast)

            if isModal {
                HStack {
                    Spacer()
                    CircleIconButton(icon: .close, size: 36, iconSize: 18, background: .glassTint,
                                     foreground: .textPrimary, shadow: false, accessibilityLabel: "إغلاق") { dismiss() }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .environment(\.layoutDirection, .leftToRight)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showGuestSheet) {
            GuestInfoSheet(
                onConfirm: {
                    showGuestSheet = false
                    if isModal { dismiss() } else { app.continueAsGuest() }
                },
                onCreateAccount: {
                    showGuestSheet = false
                    router.push(.createAccount)
                })
            .presentationDetents([.height(401)])
            .presentationCornerRadius(28)
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showAppleSimulation) {
            SimulatedProviderSheet(provider: .apple) { approved in
                showAppleSimulation = false
                if approved {
                    Task { await socialSignIn(.apple) }
                } else {
                    showToast("ألغيت تسجيل الدخول عبر Apple · لم يتغير شيء")
                }
            }
            .presentationDetents([.height(420)])
            .presentationCornerRadius(28)
        }
    }

    private var background: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: .brandPrimaryPressed, location: 0.264),
                .init(color: Color(hex: 0x72968B), location: 0.649),
                .init(color: .brandMint, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            // «Photo/Plaza Night» placeholder (gradient in the Figma file)
            LinearGradient(stops: [
                .init(color: Color(hex: 0x1A2447), location: 0),
                .init(color: Color(hex: 0x8C614D), location: 0.55),
                .init(color: Color(hex: 0x47382E), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 300)
            LinearGradient(stops: [
                .init(color: .brandPrimaryPressed, location: 0),
                .init(color: .bgCanvas, location: 0.879),
            ], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private func socialButton(_ provider: AuthProvider, asset: String, label: String) -> some View {
        Button {
            failure = nil
            if provider == .apple && services.environment.isMock {
                showAppleSimulation = true
            } else {
                Task { await socialSignIn(provider) }
            }
        } label: {
            ZStack {
                if socialLoading == provider {
                    ProgressView().tint(.brandPrimary)
                } else {
                    Image(asset).resizable().scaledToFit().frame(width: 24, height: 24)
                }
            }
            .frame(width: 64, height: 56)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(socialLoading != nil)
        .accessibilityLabel(label)
    }

    @MainActor
    private func socialSignIn(_ provider: AuthProvider) async {
        socialLoading = provider
        defer { socialLoading = nil }
        do {
            switch try await services.auth.socialSignIn(provider) {
            case .signedIn(let session):
                if session.user?.usesPrivateRelayEmail == true {
                    router.push(.appleHiddenEmail(session))
                } else {
                    app.signedIn(session, startPersonalization: true)
                }
            case .needsProfileCompletion(let partial):
                router.push(.completeProfile(partial))
            case .existingAccount(let email, let existing):
                router.push(.accountConflict(email: email, provider: existing, attempted: provider))
            case .cancelled:
                showToast("ألغيت تسجيل الدخول عبر \(provider.displayName) · لم يتغير شيء")
            }
        } catch let error as AppError {
            failure = (provider, error)
        } catch {
            failure = (provider, .unknown)
        }
    }

    private func showToast(_ text: String) {
        toast = text
        UIAccessibility.post(notification: .announcement, argument: text)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            toast = nil
        }
    }
}

/// Guest info sheet (bottom sheet on Welcome).
struct GuestInfoSheet: View {
    var onConfirm: () -> Void
    var onCreateAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SheetGrabber()
            Text("المتابعة كضيف")
                .textStyle(.title2)
                .foregroundStyle(Color.textPrimary)
            point(.compass, "ابحث وخطّط واستخدم الخريطة واكتب ملاحظات — دون حساب.")
            point(.lock, "تُحفظ خطتك وملاحظاتك على هذا الجهاز فقط.")
            point(.refresh, "المزامنة واستعادة البيانات عبر الأجهزة تحتاج حسابًا.")
            point(.warning, "حذف التطبيق قد يحذف بياناتك المحلية.")
            Spacer().frame(height: 4)
            Button("متابعة كضيف", action: onConfirm).appButton(.primary)
            Button("إنشاء حساب بدلًا من ذلك", action: onCreateAccount).appButton(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.bgSurface)
    }

    private func point(_ icon: AppIcon, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(icon, size: 20, color: .brandPrimary)
            Text(text)
                .textStyle(.subhead)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Demo stand-in for the system «Sign in with Apple» sheet (shown only with mock services —
/// the Figma frame is marked "SYSTEM UI REFERENCE"). Live builds use ASAuthorizationController.
struct SimulatedProviderSheet: View {
    let provider: AuthProvider
    var completion: (Bool) -> Void

    var body: some View {
        VStack(spacing: 16) {
            SheetGrabber()
            DemoModeBadge()
            Image("logo-apple").resizable().scaledToFit().frame(width: 40, height: 40)
            Text("محاكاة تسجيل الدخول عبر \(provider.displayName)")
                .textStyle(.title3)
                .foregroundStyle(Color.textPrimary)
            Text("هذه النافذة لا تُنشئ حسابًا جديدًا.")
                .textStyle(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("متابعة") { completion(true) }.appButton(.primary)
            Button("إلغاء") { completion(false) }.appButton(.tertiary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.bgSurface)
    }
}
