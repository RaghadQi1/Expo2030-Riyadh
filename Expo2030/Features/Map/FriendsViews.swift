import SwiftUI

// MARK: - 4.1 friends panel

struct FriendsPanel: View {
    @Bindable var model: MapModel
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MapPanelHeader(title: "الأصدقاء ومشاركة الموقع", subtitle: "تتحكمين دائمًا في من يرى موقعك ومتى",
                           buttonIcon: .close, buttonLabel: "إغلاق") { model.panel = .none }

            HStack(spacing: 12) {
                AvatarView(name: myName, image: app.isGuest ? nil : "avatar-sadeem", width: 44, height: 44, radius: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(myName) (أنتِ)").textStyle(.headline)
                    Text(sharingSummary).textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .combine)

            Button { model.sheet = .invite } label: { ButtonLabel(title: "إضافة شخص", icon: .addPerson) }
                .appButton(.primary)

            if model.friends.isEmpty {
                EmptyStateView(icon: .users, title: "لا أصدقاء بعد",
                               message: "أضيفي صديقة برمز QR أو رابط دعوة، ولن يُشارك موقعك إلا بموافقتك")
            } else {
                Text("أصدقاؤك في المعرض").textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.friends) { friend in
                            Button {
                                if friend.location != nil && friend.sharesWithMe {
                                    model.panel = .friendCard(friend)
                                    if let p = friend.location?.point { model.focus(on: p) }
                                } else {
                                    model.sheet = .shareSettings(friend)
                                }
                            } label: { friendRow(friend) }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 200)
                ForEach(model.friends.filter { isExpired($0) }) { f in
                    StatusBanner(text: "انتهت مشاركة موقعك مع \(f.name) الساعة \(ArabicDigits.time(f.myShareEndsAt!))", tone: .neutral, icon: .clock)
                }
                HStack(spacing: 6) {
                    Icon(.link, size: 14, color: .textTertiary)
                    Text("أضيفي صديقة برمز QR أو رابط دعوة، ولن يُشارك موقعك إلا بموافقتك")
                        .textStyle(.caption).foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private var myName: String { app.displayName ?? "سديم الحربي" }

    private var sharingSummary: String {
        let sharing = model.friends.filter { $0.myShare != .none }
        guard let first = sharing.first else { return "موقعك غير مُشارك مع أحد الآن" }
        return "تشاركين موقعك مع \(first.name)\(sharing.count > 1 ? " و\(ArabicDigits.format(sharing.count - 1)) غيرها" : "")"
    }

    private func isExpired(_ f: Friend) -> Bool {
        guard case .live = f.myShare, let end = f.myShareEndsAt else { return false }
        return end <= model.now
    }

    private func friendRow(_ f: Friend) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: f.name, image: f.avatar, width: 44, height: 44, radius: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(f.name).textStyle(.headline).foregroundStyle(Color.textPrimary)
                if f.sharesWithMe && f.location != nil {
                    LivePill(text: f.location!.isStale ? "آخر تحديث قبل \(ArabicDigits.format(f.location!.updatedMinutesAgo)) د" : "مباشر",
                             active: !f.location!.isStale)
                } else if f.myShare != .none {
                    LivePill(text: "تشاركين موقعك معها")
                } else {
                    LivePill(text: "لا مشاركة بينكما", active: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Icon(.chevronLeft, size: 16, color: .textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 5.7 / 5.8 friend card

struct FriendCardPanel: View {
    @Bindable var model: MapModel
    let friend: Friend
    @Environment(AppServices.self) private var services
    @Environment(ToastCenter.self) private var toast
    @State private var routing = false

    var body: some View {
        let loc = friend.location
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: friend.name, image: friend.avatar, width: 56, height: 56, radius: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(friend.name).textStyle(.title2)
                        LivePill(active: !(loc?.isStale ?? true))
                    }
                    HStack(spacing: 4) {
                        Icon(.clock, size: 13, color: .textSecondary)
                        Text(updatedText(loc)).textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button { model.sheet = .shareSettings(friend) } label: { Label("إعدادات المشاركة", systemImage: "gearshape") }
                    Button { hide() } label: { Label("إخفاء \(friend.name) من الخريطة", systemImage: "eye.slash") }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Color.textSecondary)
                        .frame(width: 40, height: 40).background(Color.bgSurface2, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("خيارات")
            }
            if let loc {
                HStack(spacing: 8) {
                    StatChip(icon: .walk, text: ArabicDigits.minutes(loc.walkMinutes) + " مشيًا")
                    StatChip(icon: .route, text: "\(ArabicDigits.format(loc.distanceMeters)) م بينكما")
                    StatChip(icon: .map, text: loc.areaText)
                    Spacer(minLength: 0)
                }
                if loc.isStale {
                    StatusBanner(text: "الموقع لم يتحدث منذ \(ArabicDigits.format(loc.updatedMinutesAgo)) دقيقة، قد لا تكون \(friend.name) في هذا المكان الآن", tone: .warning)
                }
            }
            HStack(spacing: 10) {
                Button("الوصول إليها") {
                    Task {
                        routing = true
                        defer { routing = false }
                        do { try await model.startNavigation(to: .friend(friend)) }
                        catch { toast.show("تعذّر حساب الطريق الآن", icon: .warning, iconColor: .statusError) }
                    }
                }
                .appButton(.primary, isLoading: routing)
                Button("نقطة التقاء") {
                    model.activeFriendId = friend.id
                    Task { await model.openMeetingPicker() }
                }
                .appButton(.mint)
            }
        }
    }

    private func updatedText(_ loc: FriendLocation?) -> String {
        guard let loc else { return "الموقع غير متاح" }
        if loc.updatedMinutesAgo == 0 { return "آخر تحديث: الآن" }
        return "آخر تحديث: قبل \(ArabicDigits.format(loc.updatedMinutesAgo)) دقيقة (\(loc.updatedAtText))"
    }

    private func hide() {
        Task {
            guard let updated = try? await services.friends.setVisibleOnMap(false, friendId: friend.id) else { return }
            model.upsert(updated)
            model.panel = .none
            toast.show("أُخفيت \(friend.name) من الخريطة · العرض فقط، مشاركتكما مستمرة", icon: .eye, iconColor: .textSecondary,
                       actionTitle: "إظهار \(friend.name)") {
                Task {
                    if let shown = try? await services.friends.setVisibleOnMap(true, friendId: friend.id) { model.upsert(shown) }
                }
            }
        }
    }
}

// MARK: - 4.2 / 4.3 invite card

struct InviteSheet: View {
    @Bindable var model: MapModel
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @Environment(AppState.self) private var app
    @State private var link: Loadable<InviteLink> = .idle
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetGrabber()
                MapPanelHeader(title: "دعوة للتواصل", subtitle: "شاركي الرمز أو الرابط مع صديقتك",
                               buttonIcon: .close, buttonLabel: "إغلاق") { dismiss() }
                switch link {
                case .idle, .loading:
                    LoadingStateView()
                case .failed(let e):
                    ErrorStateView(error: e) { Task { await load() } }
                case .loaded(let invite):
                    content(invite)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ invite: InviteLink) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                AvatarView(name: invite.ownerName, image: app.isGuest ? nil : "avatar-sadeem", width: 40, height: 40, radius: 20)
                VStack(alignment: .leading, spacing: 0) {
                    Text(invite.ownerName).textStyle(.headline)
                    Text("رمزك الشخصي للتواصل").textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            QRCodeImage(text: "https://\(invite.url)", size: 190)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(invite.url).textStyle(.enBody).foregroundStyle(Color.textPrimary)
                .environment(\.layoutDirection, .leftToRight)
                .textSelection(.enabled)
            Text(invite.validityText).textStyle(.caption).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

        HStack(spacing: 10) {
            Button {
                UIPasteboard.general.string = "https://\(invite.url)"
                copied = true
                toast.show("تم نسخ الرابط")
            } label: {
                ButtonLabel(title: copied ? "تم النسخ" : "نسخ الرابط", icon: copied ? .check : .link)
            }
            .appButton(.mint)
            ShareLink(item: URL(string: "https://\(invite.url)")!,
                      message: Text("\(invite.ownerName.components(separatedBy: " ").first ?? "") تدعوكِ للتواصل في المعرض")) {
                ButtonLabel(title: "مشاركة الرابط", icon: .share)
            }
            .appButton(.primary)
        }
        Button {
            dismiss()
            model.sheet = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                model.sheet = .scanFriend
            }
        } label: {
            ButtonLabel(title: "مسح رمز صديقة", icon: .qr)
        }
        .appButton(.text, height: 44)
        if model.isMock {
            Text("لن يصل الرابط قبل ربط الخادم.").textStyle(.caption).foregroundStyle(Color.statusWarning)
                .frame(maxWidth: .infinity)
        }
    }

    private func load() async {
        link = .loading
        do { link = .loaded(try await services.friends.inviteLink()) }
        catch let e as AppError { link = .failed(e) } catch { link = .failed(.unknown) }
    }
}

// MARK: - 4.5 – 4.7 scan a friend's code

struct ScanFriendSheet: View {
    @Bindable var model: MapModel
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var camera = CameraPermission()
    @State private var explained = false
    @State private var resolving = false

    var body: some View {
        Group {
            if camera.status == .granted || camera.status == .unavailable || explained && camera.status != .denied {
                if camera.status == .notDetermined {
                    LoadingStateView(title: "بانتظار إذن الكاميرا…")
                        .task { await camera.request() }
                } else {
                    scanner
                }
            } else if camera.status == .denied {
                PermissionExplainer(icon: .camera, title: "الكاميرا غير مسموحة",
                                    message: "فعّلي إذن الكاميرا من الإعدادات لمسح رمز صديقتك، أو اطلبي منها رابط الدعوة.",
                                    primary: "فتح الإعدادات", secondary: "إغلاق",
                                    onPrimary: { LocationPermissionModel.openSettings() }, onSecondary: { dismiss() })
            } else {
                PermissionExplainer(icon: .camera, title: "نحتاج الكاميرا لمسح رمز صديقتك",
                                    message: "نستخدم الكاميرا فقط أثناء فتح الماسح لقراءة رمز الدعوة، ولا نحفظ أي صور. عرض رمزك الشخصي لا يحتاج الكاميرا.",
                                    primary: "متابعة", secondary: "ليس الآن",
                                    onPrimary: { explained = true }, onSecondary: { dismiss() })
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var scanner: some View {
        ZStack(alignment: .top) {
            QRViewfinder(cameraAvailable: camera.status == .granted, hint: "وجّهي الكاميرا نحو رمز صديقتك") { code in
                resolve(code)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Icon(.close, size: 18, color: .white).frame(width: 44, height: 44)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("إغلاق")
            }
            .padding(16)
            VStack {
                Spacer()
                if resolving { ProgressView().tint(.white).padding(.bottom, 12) }
                if model.isMock {
                    Button("مسح رمز ذكرى") { resolve("thikra-demo") }
                        .appButton(.mint, height: 44, fullWidth: false)
                        .padding(.bottom, 40)
                }
            }
        }
    }

    private func resolve(_ code: String) {
        guard !resolving else { return }
        resolving = true
        Task {
            defer { resolving = false }
            do {
                let invite = try await services.friends.resolveInvite(code: code)
                dismiss()
                try? await Task.sleep(for: .milliseconds(400))
                model.sheet = .incomingInvite(invite)
            } catch {
                toast.show("لم نتعرف على هذا الرمز", icon: .warning, iconColor: .statusError)
            }
        }
    }
}

// MARK: - 4.8 incoming invitation

struct IncomingInviteSheet: View {
    @Bindable var model: MapModel
    let invite: IncomingInvite
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            SheetGrabber()
            AvatarView(name: invite.from.name, image: invite.from.avatar, width: 72, height: 72, radius: 36)
            Text("\(invite.from.name) تدعوكِ للتواصل ومشاركة الموقع").textStyle(.title3).multilineTextAlignment(.center)
            Text("بعد القبول تظهران في قائمة أصدقاء بعضكما. مشاركة موقعك خطوة منفصلة تختارينها بنفسك.")
                .textStyle(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Icon(.lock, size: 14, color: .brandPrimary)
                Text("لن يُشارك موقعك تلقائيًا").textStyle(.caption).foregroundStyle(Color.brandPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.brandMint, in: Capsule())
            Spacer(minLength: 0)
            Button("قبول الدعوة") {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        let friend = try await services.friends.acceptInvite(invite)
                        model.upsert(friend)
                        dismiss()
                        try? await Task.sleep(for: .milliseconds(400))
                        model.sheet = .shareMode(friend)
                    } catch {
                        toast.show("تعذّر قبول الدعوة الآن", icon: .warning, iconColor: .statusError)
                    }
                }
            }
            .appButton(.primary, isLoading: busy)
            Button("رفض") {
                Task {
                    try? await services.friends.declineInvite(invite)
                    dismiss()
                    toast.show("رفضتِ دعوة \(invite.from.name)، لن تُعلَم بالتفاصيل", icon: .info, iconColor: .textSecondary)
                }
            }
            .appButton(.mint)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - 5.1 – 5.5 sharing mode

struct ShareModeSheet: View {
    @Bindable var model: MapModel
    let friend: Friend
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @Environment(AppState.self) private var app

    private enum Choice: Hashable { case none, staticOnce, live }
    @State private var choice: Choice = .none
    @State private var liveMinutes: Int? = 60      // nil = حتى نهاية زيارتي
    @State private var saving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Icon(.check, size: 18, color: .statusSuccess)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("أصبحتِ متصلة ب\(friend.name)").textStyle(.headline).foregroundStyle(Color.statusSuccess)
                            Text("لم يُشارك موقعك بعد").textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: -10) {
                            AvatarView(name: friend.name, image: friend.avatar, width: 34, height: 34, radius: 17)
                            AvatarView(name: app.displayName ?? "سديم", image: app.isGuest ? nil : "avatar-sadeem", width: 34, height: 34, radius: 17)
                        }
                    }
                    .padding(14)
                    .background(Color.statusSuccessBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text("كيف تودّين مشاركة موقعك مع \(friend.name)؟").textStyle(.title2)

                    option(.none, icon: .eye, title: "لا أشارك الآن", subtitle: "يمكنك البدء لاحقًا من صفحة \(friend.name)")
                    option(.staticOnce, icon: .map, title: "موقع ثابت لمرة واحدة", subtitle: "إرسال موقعك الحالي دون تحديثه") {
                        Text("سيُرسل موقعك الحالي (\(model.location?.areaTitle ?? "قرب منطقة المطاعم")) الساعة \(ArabicDigits.time(model.now.adding(minutes: -2)))، ولن يتحدث بعدها")
                            .textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                    option(.live, icon: .navigate, title: "موقع مباشر لمدة محدودة", subtitle: "تحديث موقعك أثناء تحركك") {
                        VStack(alignment: .leading, spacing: 8) {
                            FlowLayout(spacing: 6, lineSpacing: 6) {
                                ForEach([15, 30, 60, 120] as [Int], id: \.self) { m in
                                    SelectableChip(title: durationTitle(m), isSelected: liveMinutes == m) { liveMinutes = m }
                                }
                                SelectableChip(title: "حتى نهاية زيارتي", isSelected: liveMinutes == nil) { liveMinutes = nil }
                            }
                            Text(liveMinutes.map { "تنتهي المشاركة تلقائيًا الساعة \(ArabicDigits.time(model.now.adding(minutes: $0 - 2)))" }
                                 ?? "تستمر حتى تضغطين «إنهاء الزيارة» في التطبيق")
                                .textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }

                    HStack(spacing: 6) {
                        Icon(.lock, size: 14, color: .textTertiary)
                        Text("يمكنك الإيقاف في أي وقت، و\(friend.name) لا ترى إلا ما تختارينه")
                            .textStyle(.caption).foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button("متابعة") { Task { await save() } }.appButton(.primary, isLoading: saving)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تخطي") { finish() }.foregroundStyle(Color.textSecondary)
                }
            }
            .appNavigationChrome()
        }
    }

    private func durationTitle(_ m: Int) -> String {
        switch m {
        case 60: "ساعة"
        case 120: "ساعتان"
        default: "\(ArabicDigits.format(m)) د"
        }
    }

    private func option(_ value: Choice, icon: AppIcon, title: String, subtitle: String) -> some View {
        option(value, icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }

    @ViewBuilder
    private func option<Detail: View>(_ value: Choice, icon: AppIcon, title: String, subtitle: String,
                                      @ViewBuilder detail: () -> Detail) -> some View {
        let selected = choice == value
        Button { choice = value } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Icon(icon, size: 20, color: value == .live ? .locationBlue : .textSecondary)
                        .frame(width: 40, height: 40)
                        .background(value == .live ? Color.locationBlueBg : Color.bgSurface2,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                        Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RadioDot(isOn: selected)
                }
                if selected { detail() }
            }
            .padding(14)
            .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? Color.brandPrimary : Color.borderDefault, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func save() async {
        let mode: LocationShareMode = switch choice {
        case .none: .none
        case .staticOnce: .staticOnce
        case .live: liveMinutes.map { LocationShareMode.live(minutes: $0) } ?? .untilEndOfVisit
        }
        saving = true
        defer { saving = false }
        do {
            let updated = try await services.friends.setShareMode(mode, with: friend.id)
            model.upsert(updated)
            switch mode {
            case .staticOnce:
                toast.show("أُرسل موقعك الثابت إلى \(friend.name) · أُرسل الساعة \(ArabicDigits.time(model.now.adding(minutes: -2)))")
            case .live, .untilEndOfVisit:
                toast.show("بدأت مشاركة موقعك مع \(friend.name)")
            case .none:
                break
            }
            finish()
        } catch {
            toast.show((error as? AppError)?.message ?? "تعذّر حفظ اختيارك", icon: .warning, iconColor: .statusError)
        }
    }

    private func finish() {
        dismiss()
        if model.permissions.notificationsStatus == .notDetermined {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                model.sheet = .notificationsExplainer
            }
        }
    }
}

// MARK: - 5.11 – 5.18 sharing settings

struct ShareSettingsSheet: View {
    @Bindable var model: MapModel
    let friendId: String
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toast
    @State private var showDuration = false
    @State private var showBackgroundExplainer = false
    @State private var confirmStop = false
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            if let friend = model.friend(friendId) {
                content(friend)
            } else {
                EmptyStateView(icon: .users, title: "لم تعد هذه الصديقة في قائمتك")
            }
        }
    }

    private func content(_ friend: Friend) -> some View {
        let sharing = friend.myShare != .none
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    AvatarView(name: friend.name, image: friend.avatar, width: 60, height: 60, radius: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(friend.name).textStyle(.title2)
                        Text(friend.connectedSince).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }

                Text("موقعي").textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
                SettingsGroup {
                    SettingsRow(icon: .navigate, title: "مشاركة موقعي",
                                subtitle: sharing ? "مفعّلة، \(shareModeText(friend.myShare))" : "متوقفة، \(friend.name) لا ترى موقعك",
                                showsDivider: sharing) {
                        if sharing { LivePill() } else {
                            Button("بدء") { model.sheet = nil; Task { @MainActor in try? await Task.sleep(for: .milliseconds(400)); model.sheet = .shareMode(friend) } }
                                .textStyle(.subheadStrong).foregroundStyle(Color.brandPrimary)
                        }
                    }
                    if sharing {
                        SettingsRow(icon: .clock, title: "مدة المشاركة", subtitle: durationText(friend)) {
                            Button("تعديل") { showDuration = true }.textStyle(.subheadStrong).foregroundStyle(Color.brandPrimary)
                        }
                        SettingsRow(icon: .lock, title: "الاستمرار عند قفل الشاشة",
                                    subtitle: friend.shareInBackground ? "مفعّل، إذن الموقع «دائمًا»" : "يتطلب إذن الموقع «دائمًا» من iOS",
                                    showsDivider: false) {
                            Toggle("", isOn: Binding(get: { friend.shareInBackground }, set: { on in
                                if on { showBackgroundExplainer = true } else { Task { await setBackground(false, friend) } }
                            }))
                            .labelsHidden().tint(.brandPrimary)
                        }
                    }
                }

                Text(friend.name).textStyle(.subheadStrong).foregroundStyle(Color.textSecondary)
                SettingsGroup {
                    SettingsRow(icon: .share, title: "\(friend.name) تشارك موقعها معي", subtitle: "قرار منفصل تتحكم فيه \(friend.name)") {
                        LivePill(text: friend.sharesWithMe ? "مباشر" : "لا تشارك", active: friend.sharesWithMe)
                    }
                    SettingsRow(icon: .eye, title: "إظهار \(friend.name) على الخريطة", subtitle: "الإخفاء يغيّر العرض فقط", showsDivider: false) {
                        Toggle("", isOn: Binding(get: { friend.isVisibleOnMap }, set: { on in
                            Task {
                                if let f = try? await services.friends.setVisibleOnMap(on, friendId: friend.id) { model.upsert(f) }
                            }
                        }))
                        .labelsHidden().tint(.brandPrimary)
                    }
                }

                SettingsGroup {
                    if sharing {
                        Button { confirmStop = true } label: {
                            SettingsRow(icon: .close, iconTint: .statusError, iconBackground: .statusErrorBg,
                                        title: "إيقاف مشاركة موقعي", titleColor: .statusError) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    }
                    Button { confirmRemove = true } label: {
                        SettingsRow(icon: .trash, iconTint: .statusError, iconBackground: .statusErrorBg,
                                    title: "إزالة صديقة", titleColor: .statusError,
                                    subtitle: "ينهي الاتصال والمشاركة بين الطرفين", showsDivider: false) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(Color.bgCanvas)
        .appNavigationChrome(title: "إعدادات المشاركة")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) { Icon(.chevronRight, size: 18); Text("رجوع") }
                }
                .foregroundStyle(Color.brandPrimary)
            }
        }
        .sheet(isPresented: $showDuration) {
            ShareDurationSheet(model: model, friend: friend).presentationDetents([.medium])
        }
        .sheet(isPresented: $showBackgroundExplainer) {
            PermissionExplainer(icon: .lock, title: "لتستمر المشاركة والشاشة مقفلة",
                                message: "يحتاج التطبيق إذن الموقع «دائمًا» حتى تواصل \(friend.name) رؤية موقعك المباشر عند قفل الشاشة. يتوقف ذلك تلقائيًا عند انتهاء مدة المشاركة.",
                                footnote: "إن رفضتِ سابقًا: الإعدادات ← دليل المعرض ← الموقع ← دائمًا",
                                primary: "متابعة", secondary: "ليس الآن",
                                onPrimary: {
                                    showBackgroundExplainer = false
                                    model.permissions.requestAlways()
                                    Task { await setBackground(true, friend) }
                                },
                                onSecondary: { showBackgroundExplainer = false })
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("إيقاف مشاركة موقعك مع \(friend.name)؟", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("إيقاف المشاركة مع \(friend.name)", role: .destructive) {
                Task {
                    if let f = try? await services.friends.stopSharing(with: friend.id) {
                        model.upsert(f)
                        toast.show("أوقفتِ مشاركة موقعك مع \(friend.name)")
                    }
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لن ترى \(friend.name) موقعك بعد الآن، وتبقى صديقتك ويمكنكما المشاركة لاحقًا. مشاركة \(friend.name) معكِ لا تتأثر.")
        }
        .confirmationDialog("إزالة \(friend.name) من أصدقائك؟", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("إزالة صديقة", role: .destructive) {
                Task {
                    do {
                        try await services.friends.removeFriend(friend.id)
                        model.friends.removeAll { $0.id == friend.id }
                        if case .friendCard(let f) = model.panel, f.id == friend.id { model.panel = .friends }
                        dismiss()
                        toast.show("أُزيلت \(friend.name) من أصدقائك")
                    } catch {
                        toast.show("تعذّرت الإزالة الآن", icon: .warning, iconColor: .statusError)
                    }
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("سينتهي الاتصال وتتوقف مشاركة الموقع بين الطرفين، وتحتاجان دعوة جديدة للتواصل مرة أخرى.")
        }
    }

    private func shareModeText(_ mode: LocationShareMode) -> String {
        switch mode {
        case .staticOnce: "موقع ثابت"
        case .live, .untilEndOfVisit: "موقع مباشر"
        case .none: ""
        }
    }

    private func durationText(_ f: Friend) -> String {
        switch f.myShare {
        case .untilEndOfVisit: return "حتى نهاية زيارتك"
        case .staticOnce: return "أُرسل مرة واحدة"
        default:
            guard let end = f.myShareEndsAt else { return "" }
            let left = max(0, end.minutes - model.now.minutes)
            return "باقي \(ArabicDigits.format(left)) دقيقة، تنتهي \(ArabicDigits.time(end))"
        }
    }

    private func setBackground(_ on: Bool, _ friend: Friend) async {
        guard let f = try? await services.friends.setBackgroundSharing(on, with: friend.id) else { return }
        model.upsert(f)
        if on, let end = f.myShareEndsAt {
            toast.show("ستستمر المشاركة عند قفل الشاشة حتى \(ArabicDigits.time(end))")
        }
    }
}

/// 5.12 «مدة مشاركة موقعك مع ذكرى».
struct ShareDurationSheet: View {
    @Bindable var model: MapModel
    let friend: Friend
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var extra = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetGrabber()
            Text("مدة مشاركة موقعك مع \(friend.name)").textStyle(.title3)
            HStack(spacing: 8) {
                ForEach([15, 30, 60, 120], id: \.self) { m in
                    SelectableChip(title: m == 60 ? "+ ساعة" : (m == 120 ? "+ ساعتان" : "+ \(ArabicDigits.format(m)) د"),
                                   isSelected: extra == m) { extra = m }
                }
            }
            if let end = friend.myShareEndsAt {
                StatusBanner(text: "تنتهي المشاركة الساعة \(ArabicDigits.time(end.adding(minutes: extra))) بدل \(ArabicDigits.time(end))", tone: .info, icon: .clock)
            }
            Spacer(minLength: 0)
            Button("حفظ") {
                Task {
                    let current = max(0, (friend.myShareEndsAt?.minutes ?? model.now.minutes) - model.now.minutes)
                    if let f = try? await services.friends.setShareMode(.live(minutes: current + extra + 2), with: friend.id) {
                        model.upsert(f)
                    }
                    dismiss()
                }
            }
            .appButton(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}
