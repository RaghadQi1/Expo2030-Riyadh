import SwiftUI

enum AccountRoute: Hashable {
    case profile
    case editProfile
    case shareProfile
    case recipientPreview
    case summaries
    case settings
    case permissions
    case help
}

/// «حسابي» (16.01).
struct AccountTab: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @State private var path = NavigationPath()
    @State private var profileSubtitle = "اختياري · لم تنشئه بعد"
    @State private var friendsSubtitle = "لا مشاركة الآن"
    @State private var summariesCount = 0
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenTitle(text: "حسابي")
                    profileCard
                    group {
                        row(.briefcase, "ملفي المهني", profileSubtitle) { path.append(AccountRoute.profile) }
                        row(.users, "الأصدقاء ومشاركة الموقع", friendsSubtitle) { app.openMap(.friends) }
                        row(.journey, "ملخصات رحلاتي", summariesCount == 0 ? "لا ملخصات محفوظة" : "\(summariesCount) ملخص",
                            divider: false) { path.append(AccountRoute.summaries) }
                    }
                    group {
                        row(.globe, "الإعدادات", "اللغة، المظهر، الإشعارات، البيانات") { path.append(AccountRoute.settings) }
                        row(.lock, "الأذونات", "الموقع، الإشعارات، الكاميرا، الميكروفون") { path.append(AccountRoute.permissions) }
                        row(.info, "المساعدة والإبلاغ عن مشكلة", nil, divider: false) { path.append(AccountRoute.help) }
                    }
                    if app.isGuest {
                        Button("إنشاء حساب أو تسجيل الدخول") { app.isAuthPresented = true }.appButton(.primary)
                    } else {
                        Button("تسجيل الخروج") { confirmSignOut = true }.appButton(.tertiary)
                    }
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.top, 4)
            }
            .tabBarSafeArea()
            .background(Color.bgCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AccountRoute.self) { route in
                switch route {
                case .profile: ProfessionalProfileView(path: $path)
                case .editProfile: ProfileEditView()
                case .shareProfile: ShareProfileView()
                case .recipientPreview: RecipientPreviewView()
                case .summaries: SavedSummariesView()
                case .settings: SettingsView()
                case .permissions: PermissionsView()
                case .help: HelpView()
                }
            }
        }
        .task(id: "\(app.journeyRevision)-\(app.isGuest)") { await load() }
        .confirmationDialog("تسجيل الخروج؟", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("تسجيل الخروج", role: .destructive) {
                Task {
                    await services.auth.signOut()
                    app.signOut()
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("تبقى بياناتك محفوظة في حسابك، وتعود إليها عند تسجيل الدخول.")
        }
    }

    private var profileCard: some View {
        Button {
            if app.isGuest { app.isAuthPresented = true } else { path.append(AccountRoute.profile) }
        } label: {
            HStack(spacing: 12) {
                AvatarView(name: app.displayName ?? "زائر", image: app.session.user?.avatarAsset, width: 56, height: 56, radius: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName ?? "تصفح كزائر").textStyle(.title3).foregroundStyle(Color.textPrimary)
                    if let user = app.session.user {
                        Text("✓ الحساب محفوظ في قاعدة البيانات · \(user.email)").textStyle(.caption).foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("بياناتك محفوظة على هذا الجهاز فقط · أنشئ حسابًا للمزامنة")
                            .textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevronLeft, size: 16, color: .textTertiary)
            }
            .padding(14)
            .cardBackground(radius: 22)
        }
        .buttonStyle(.plain)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.cardBackground(radius: 22)
    }

    private func row(_ icon: AppIcon, _ title: String, _ subtitle: String?, divider: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(icon: icon, title: title, subtitle: subtitle, showsDivider: divider) {
                Icon(.chevronLeft, size: 16, color: .textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor private func load() async {
        if let link = try? await services.profile.currentShareLink(), link.isActive {
            profileSubtitle = "رابط نشط واحد · \(link.validUntilText.components(separatedBy: " · ").first ?? "")"
        } else if let p = try? await services.profile.profile(), !p.isEmpty {
            profileSubtitle = "جاهز للمشاركة · لا رابط نشط"
        } else {
            profileSubtitle = "اختياري · لم تنشئه بعد"
        }
        let friends = (try? await services.friends.friends()) ?? []
        let sharing = friends.filter { $0.myShare != .none }.count
        friendsSubtitle = sharing == 0 ? (friends.isEmpty ? "لم تضيفي أحدًا بعد" : "لا تشاركين موقعك الآن")
                                       : (sharing == 1 ? "تشاركين مع شخص واحد الآن" : "تشاركين مع \(sharing) أشخاص الآن")
        summariesCount = ((try? await services.journey.savedSummaries()) ?? []).count
    }
}

// MARK: - Saved summaries

struct SavedSummariesView: View {
    @Environment(AppServices.self) private var services
    @State private var items: Loadable<[JourneySummary]> = .idle

    var body: some View {
        Group {
            switch items {
            case .idle, .loading: LoadingStateView()
            case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
            case .loaded(let list) where list.isEmpty:
                EmptyStateView(icon: .journey, title: "لا ملخصات محفوظة",
                               message: "افتحي «رحلتي ← ملخص اليوم»، راجعي المسودة ثم احفظيها.")
            case .loaded(let list):
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(list, id: \.title) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(s.title).textStyle(.caption).foregroundStyle(Color.textSecondary)
                                Text(s.subtitle).textStyle(.headline)
                                Text("\(s.duration) · \(s.distance)").textStyle(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground(radius: 20)
                        }
                    }
                    .padding(Spacing.screen)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "ملخصات رحلاتي")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task { await load() }
    }

    @MainActor private func load() async {
        items = .loading
        do { items = .loaded(try await services.journey.savedSummaries()) }
        catch let e as AppError { items = .failed(e) } catch { items = .failed(.unknown) }
    }
}
