import SwiftUI
import UniformTypeIdentifiers

// MARK: - 14.01 empty / profile home

struct ProfessionalProfileView: View {
    @Binding var path: NavigationPath
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @State private var profile: Loadable<ProfessionalProfile?> = .idle

    var body: some View {
        Group {
            switch profile {
            case .idle, .loading: LoadingStateView()
            case .failed(let e): ErrorStateView(error: e) { Task { await load() } }
            case .loaded(let p):
                if let p, !p.isEmpty { filled(p) } else { empty }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "ملفي المهني")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task(id: app.journeyRevision) { await load() }
    }

    private var empty: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 40)
            IllustrationBadge(icon: .briefcase, size: 80, iconSize: 36)
            Text("ملفك المهني (اختياري)").textStyle(.title2)
            Text("أنشئ بطاقة مختصرة تشاركها برمز QR مع الجهات التي تقابلها. أنت تختار ما يظهر ومتى يتوقف الرابط.")
                .textStyle(.subhead).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            Button("أنشئ ملفي المهني") { path.append(AccountRoute.editProfile) }.appButton(.primary)
            Text("مشاركة الملف ليست طلب توظيف، ولا نعرض «راجعت الجهة ملفك» دون بيانات فعلية.")
                .textStyle(.caption).foregroundStyle(Color.textTertiary).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func filled(_ p: ProfessionalProfile) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ProfileCard(profile: p, fields: Set(ProfileField.allCases))
                Button { path.append(AccountRoute.shareProfile) } label: { ButtonLabel(title: "مشاركة الملف", icon: .qr) }
                    .appButton(.primary)
                HStack(spacing: 10) {
                    Button("تعديل") { path.append(AccountRoute.editProfile) }.appButton(.mint)
                    Button("معاينة ما يراه المستلم") { path.append(AccountRoute.recipientPreview) }.appButton(.tertiary)
                }
            }
            .padding(Spacing.screen)
        }
    }

    @MainActor private func load() async {
        if profile.value == nil { profile = .loading }
        do { profile = .loaded(try await services.profile.profile()) }
        catch let e as AppError { profile = .failed(e) } catch { profile = .failed(.unknown) }
    }
}

/// Profile summary card, also used for the recipient page preview (14.06). Only `fields` are shown.
struct ProfileCard: View {
    let profile: ProfessionalProfile
    let fields: Set<ProfileField>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(name: profile.displayName, image: profile.photo, width: 52, height: 52, radius: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName).textStyle(.title2)
                    if fields.contains(.jobTitle), !profile.jobTitle.isEmpty {
                        Text(profile.jobTitle).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer()
            }
            if fields.contains(.bio), !profile.bio.isEmpty {
                Text(profile.bio).textStyle(.subhead).foregroundStyle(Color.textPrimary)
            }
            if fields.contains(.education), !profile.education.isEmpty {
                block("التعليم") { Text(profile.education).textStyle(.footnote) }
            }
            if fields.contains(.experiences), !profile.experiences.isEmpty {
                block("الخبرات") {
                    ForEach(profile.experiences) { x in
                        Text("• \(x.title) · \(x.subtitle)").textStyle(.footnote)
                    }
                }
            }
            if fields.contains(.skills), !profile.skills.isEmpty {
                block("المهارات") {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(profile.skills, id: \.self) { s in
                            Tag(text: s, foreground: .brandPrimary, background: .brandMint)
                        }
                    }
                }
            }
            if fields.contains(.contact), !profile.contactGoal.isEmpty {
                Text("هدف التواصل: \(profile.contactGoal)").textStyle(.caption).foregroundStyle(Color.textSecondary)
            }
            if fields.contains(.links), !profile.linkedIn.isEmpty || !profile.website.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !profile.linkedIn.isEmpty { Text(profile.linkedIn) }
                    if !profile.website.isEmpty { Text(profile.website) }
                }
                .textStyle(.enCaption).foregroundStyle(Color.textLink)
                .environment(\.layoutDirection, .leftToRight)
            }
            if fields.contains(.cv), let cv = profile.cv {
                HStack(spacing: 8) {
                    Icon(.file, size: 18, color: .brandPrimary)
                    Text(cv.fileName).textStyle(.enCaption)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground(radius: 22)
    }

    private func block<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).textStyle(.subheadStrong)
            content()
        }
    }
}

// MARK: - 14.02 edit

struct ProfileEditView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ProfessionalProfile(displayName: "")
    @State private var loaded = false
    @State private var saving = false
    @State private var uploadingCV = false
    @State private var newSkill = ""
    @State private var showExperience = false
    @State private var showCVPicker = false
    @State private var showPreview = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AvatarView(name: draft.displayName, image: draft.photo, width: 56, height: 56, radius: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.displayName).textStyle(.headline)
                        Text("الصورة من حسابك").textStyle(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                field("المسمى", text: $draft.jobTitle, placeholder: "مثل: مهندسة بيانات")
                field("نبذة", text: $draft.bio, placeholder: "سطران عن عملك واهتمامك", multiline: true)
                field("التخصص والتعليم", text: $draft.education, placeholder: "التخصص · الجهة")

                sectionTitle("الخبرات / المهارات")
                ForEach(draft.experiences) { x in
                    HStack(spacing: 12) {
                        Icon(.briefcase, size: 18, color: .brandPrimary)
                            .frame(width: 36, height: 36)
                            .background(Color.brandMint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.title).textStyle(.bodyStrong)
                            Text(x.subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button { draft.experiences.removeAll { $0.id == x.id } } label: { Icon(.trash, size: 16, color: .textTertiary) }
                            .accessibilityLabel("حذف الخبرة")
                    }
                    .padding(12)
                    .cardBackground(radius: 16)
                }
                Button { showExperience = true } label: {
                    HStack(spacing: 6) { Text("أضف خبرة أو مشروعًا"); Icon(.plus, size: 16) }
                        .textStyle(.subheadStrong).foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                .buttonStyle(.plain)

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(draft.skills, id: \.self) { s in
                        Button { draft.skills.removeAll { $0 == s } } label: {
                            Tag(text: s, foreground: .brandPrimary, background: .brandMint, icon: .close)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("حذف مهارة \(s)")
                    }
                }
                HStack(spacing: 8) {
                    TextField("أضف مهارة", text: $newSkill).textStyle(.body)
                        .onSubmit(addSkill)
                    Button("إضافة", action: addSkill).textStyle(.subheadStrong).foregroundStyle(Color.brandPrimary)
                        .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.borderDefault))

                sectionTitle("ما الذي تبحث عنه ؟")
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(LookingFor.allCases) { item in
                        SelectableChip(title: item.title, isSelected: draft.lookingFor.contains(item)) {
                            if draft.lookingFor.contains(item) { draft.lookingFor.remove(item) } else { draft.lookingFor.insert(item) }
                        }
                    }
                }

                sectionTitle("روابط")
                field("LinkedIn", text: $draft.linkedIn, placeholder: "linkedin.com/in/…", latin: true)
                field("الموقع / الأعمال", text: $draft.website, placeholder: "example.com", latin: true)

                sectionTitle("التواصل")
                field("وسيلة التواصل المفضلة", text: $draft.preferredContact, placeholder: "البريد: name@example.com")
                field("هدف التواصل", text: $draft.contactGoal, placeholder: "شراكات بحثية · فرص تدريب…")

                sectionTitle("السيرة الذاتية (CV)")
                if let cv = draft.cv {
                    HStack(spacing: 10) {
                        Icon(.file, size: 20, color: .brandPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cv.fileName).textStyle(.enBody)
                            Text(cv.details).textStyle(.caption).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("استبدال") { showCVPicker = true }.textStyle(.caption).foregroundStyle(Color.brandPrimary)
                        Button("حذف") { draft.cv = nil }.textStyle(.caption).foregroundStyle(Color.statusError)
                    }
                    .padding(12)
                    .cardBackground(radius: 16)
                } else {
                    Button { showCVPicker = true } label: { ButtonLabel(title: "رفع ملف PDF", icon: .file) }
                        .appButton(.mint, height: 44)
                }
                Text(services.environment.isMock ?
                     "يُحفظ الملف على الجهاز في الوضع المحلي." :
                     "يُحفظ PDF في قاعدة البيانات لحسابك، ولا يظهر للمشارَكين تلقائيًا.")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                HStack(spacing: 10) {
                    Button("حفظ") { Task { await save() } }.appButton(.primary, isLoading: saving || uploadingCV)
                        .disabled(uploadingCV)
                    Button("معاينة") { showPreview = true }.appButton(.mint).frame(width: 120)
                }
            }
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "تعديل الملف")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .sheet(isPresented: $showExperience) {
            ExperienceSheet { draft.experiences.append($0) }.presentationDetents([.medium])
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                ScrollView { ProfileCard(profile: draft, fields: Set(ProfileField.allCases)).padding() }
                    .background(Color.bgCanvas)
                    .appNavigationChrome(title: "معاينة")
            }
        }
        .fileImporter(isPresented: $showCVPicker, allowedContentTypes: [.pdf]) { result in
            if case .success(let url) = result { importCV(url) }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let p = try? await services.profile.profile() { draft = p }
            if draft.displayName.isEmpty { draft.displayName = app.displayName ?? "زائر" }
            if draft.photo == nil { draft.photo = app.session.user?.avatarAsset }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).textStyle(.headline).padding(.top, 6)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, multiline: Bool = false, latin: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).textStyle(.caption).foregroundStyle(Color.textSecondary)
            TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
                .textStyle(latin ? .enBody : .body)
                .lineLimit(multiline ? 2...5 : 1...1)
                .textInputAutocapitalization(latin ? .never : .sentences)
                .keyboardType(latin ? .URL : .default)
                .environment(\.layoutDirection, latin ? .leftToRight : .rightToLeft)
        }
        .padding(12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.borderDefault))
    }

    private func addSkill() {
        let s = newSkill.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !draft.skills.contains(s) else { return }
        draft.skills.append(s)
        newSkill = ""
    }

    private func importCV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              (try? LocalAttachmentStore.save(data, ext: "pdf")) != nil else {
            toasts.show("تعذّر قراءة الملف", icon: .warning, iconColor: .statusError)
            return
        }
        let fileName = url.lastPathComponent
        uploadingCV = true
        Task { @MainActor in
            defer { uploadingCV = false }
            if !services.environment.isMock,
               let accountService = services.profile as? AccountProfileService,
               accountService.tokens.accessToken != nil {
                do {
                    try await accountService.live.uploadCV(data, fileName: fileName)
                } catch {
                    toasts.show("تعذّر رفع السيرة للخادم؛ لم يُحدّث الملف المهني", icon: .warning, iconColor: .statusError)
                    return
                }
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ar_SA@numbers=latn")
            formatter.dateFormat = "h:mm a"
            draft.cv = CVFile(fileName: fileName, details: "PDF · \(size) · رُفع \(formatter.string(from: Date()))")
        }
    }

    @MainActor private func save() async {
        saving = true
        defer { saving = false }
        do {
            _ = try await services.profile.save(draft)
            if draft.cv == nil, !services.environment.isMock,
               let accountService = services.profile as? AccountProfileService,
               accountService.tokens.accessToken != nil {
                try await accountService.live.removeCV()
            }
            app.journeyRevision += 1
            toasts.show("حُفظ ملفك المهني")
            dismiss()
        } catch {
            toasts.show((error as? AppError)?.message ?? "تعذّر الحفظ", icon: .warning, iconColor: .statusError)
        }
    }
}

private struct ExperienceSheet: View {
    var onAdd: (Experience) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var subtitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            Text("أضف خبرة أو مشروعًا").textStyle(.title3)
            AppTextField(label: "المسمى أو اسم المشروع", text: $title, placeholder: "مثل: محللة بيانات")
            AppTextField(label: "الجهة والفترة", text: $subtitle, placeholder: "الجهة · 2022 – الآن")
            Spacer(minLength: 0)
            Button("إضافة") {
                onAdd(Experience(id: UUID().uuidString, title: title, subtitle: subtitle))
                dismiss()
            }
            .appButton(.primary)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - 14.04 / 14.05 / 14.09 share

struct ShareProfileView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @Environment(ToastCenter.self) private var toasts

    @State private var profile: ProfessionalProfile?
    @State private var link: ProfileShareLink?
    @State private var loading = true
    @State private var fields: Set<ProfileField> = [.jobTitle, .bio, .experiences, .skills, .links, .contact]
    @State private var validity: LinkValidity = .oneDay
    @State private var creating = false
    @State private var confirmDisable = false
    @State private var copied = false

    var body: some View {
        Group {
            if loading {
                LoadingStateView()
            } else if profile == nil || profile?.isEmpty == true {
                VStack(spacing: 14) {
                    EmptyStateView(icon: .briefcase, title: "لا يوجد ملف مهني بعد",
                                   message: "أنشئ بطاقة مختصرة أولًا، ثم اختر ما تشاركه.")
                    NavigationLink("أنشئ ملفي المهني") { ProfileEditView() }
                        .appButton(.primary)
                        .padding(.horizontal, 24)
                }
            } else if let link, link.isActive, let profile {
                active(link, profile)
            } else {
                chooser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: link?.isActive == true ? "رمز ملفي المهني" : "مشاركة الملف")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task(id: app.journeyRevision) { await load() }
        .confirmationDialog("تعطيل الرابط ورمز QR؟", isPresented: $confirmDisable, titleVisibility: .visible) {
            Button("تعطيل", role: .destructive) {
                Task {
                    do {
                        try await services.profile.disableShareLink()
                        link?.isActive = false
                        toasts.show("عُطّل الرابط ورمز QR")
                    } catch {
                        toasts.show("تعذّر التعطيل الآن", icon: .warning, iconColor: .statusError)
                    }
                }
            }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("لن يتمكن أحد من فتح الرابط بعد الآن. من نزّل سيرتك أو حفظ معلوماتك سابقًا يحتفظ بنسخته.")
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("ماذا تشارك؟").textStyle(.title2)
                Text("تظهر الحقول المختارة فقط للمستلم. ملاحظاتك ورحلتك لا تُشارك أبدًا.")
                    .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                VStack(spacing: 0) {
                    ForEach(ProfileField.allCases) { f in
                        let available = isAvailable(f)
                        Toggle(isOn: Binding(get: { fields.contains(f) && available },
                                             set: { on in if on { fields.insert(f) } else { fields.remove(f) } })) {
                            Text(title(for: f)).textStyle(.body)
                                .foregroundStyle(available ? Color.textPrimary : Color.textTertiary)
                        }
                        .tint(.brandPrimary)
                        .disabled(!available)
                        .padding(.horizontal, 14).frame(minHeight: 52)
                        Divider().padding(.leading, 14)
                    }
                }
                .cardBackground(radius: 18)

                Text("صلاحية الرابط").textStyle(.headline)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(LinkValidity.allCases) { v in
                        SelectableChip(title: v.title, isSelected: validity == v) { validity = v }
                    }
                }
                Button("إنشاء الرابط وQR") { Task { await create() } }
                    .appButton(.primary, isLoading: creating)
                    .disabled(fields.filter(isAvailable).isEmpty)
            }
            .padding(Spacing.screen)
        }
    }

    private func active(_ link: ProfileShareLink, _ profile: ProfessionalProfile) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Text("ملفي المهني — ليس دعوة موقع").textStyle(.caption)
                        Icon(.briefcase, size: 14)
                    }
                    .foregroundStyle(Color.white.opacity(0.85))
                    HStack(spacing: 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(profile.displayName).textStyle(.headline)
                            Text(profile.jobTitle).textStyle(.caption).opacity(0.8)
                        }
                        AvatarView(name: profile.displayName, image: profile.photo, width: 40, height: 40, radius: 20)
                    }
                    .foregroundStyle(.white)
                    QRCodeImage(text: "https://\(link.url)", size: 180)
                        .padding(14)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Text(link.validUntilText).textStyle(.caption).foregroundStyle(Color.white.opacity(0.85))
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

                Text(link.url).textStyle(.enCaption).foregroundStyle(Color.textSecondary)
                    .environment(\.layoutDirection, .leftToRight)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    ShareLink(item: URL(string: "https://\(link.url)")!) { Text("مشاركة") }
                        .appButton(.primary)
                    Button(copied ? "تم النسخ" : "نسخ الرابط") {
                        UIPasteboard.general.string = "https://\(link.url)"
                        copied = true
                        toasts.show("تم نسخ الرابط")
                    }
                    .appButton(.mint)
                }
                Button("تعطيل الرابط") { confirmDisable = true }
                    .appButton(.destructiveOutline)
                Text("التعطيل يمنع الوصول اللاحق فقط، ولا يسحب نسخة سبق تنزيلها.")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
                NavigationLink("معاينة ما يراه المستلم") { RecipientPreviewView() }
                    .appButton(.text, height: 44)
                if services.environment.isMock {
                    Text("الصفحة العامة تحتاج إلى اتصال بالخادم.")
                        .textStyle(.caption).foregroundStyle(Color.statusWarning)
                }
            }
            .padding(Spacing.screen)
        }
    }

    private func title(for f: ProfileField) -> String {
        switch f {
        case .jobTitle: "الاسم والمسمى"
        case .experiences: "الخبرات (\(profile?.experiences.count ?? 0))"
        case .links: "روابط LinkedIn والموقع"
        case .contact: "البريد للتواصل"
        case .cv: "السيرة الذاتية (PDF)"
        case .education: "التعليم"
        default: f.title
        }
    }

    private func isAvailable(_ f: ProfileField) -> Bool {
        guard let p = profile else { return false }
        switch f {
        case .jobTitle: return true
        case .bio: return !p.bio.isEmpty
        case .education: return !p.education.isEmpty
        case .experiences: return !p.experiences.isEmpty
        case .skills: return !p.skills.isEmpty
        case .links: return !p.linkedIn.isEmpty || !p.website.isEmpty
        case .contact: return !p.preferredContact.isEmpty
        case .cv: return p.cv != nil
        }
    }

    @MainActor private func load() async {
        loading = profile == nil
        profile = try? await services.profile.profile()
        link = try? await services.profile.currentShareLink()
        loading = false
    }

    @MainActor private func create() async {
        creating = true
        defer { creating = false }
        do {
            link = try await services.profile.createShareLink(fields: fields.filter(isAvailable), validity: validity)
            toasts.show("أُنشئ الرابط ورمز QR")
        } catch {
            toasts.show((error as? AppError)?.message ?? "تعذّر إنشاء الرابط", icon: .warning, iconColor: .statusError)
        }
    }
}

// MARK: - 14.06 / 14.08 recipient page preview

/// In-app preview of the public web page the recipient opens (no app needed). The real page is served by the
/// backend at the share URL; this view only shows what it will contain.
struct RecipientPreviewView: View {
    @Environment(AppServices.self) private var services
    @State private var profile: ProfessionalProfile?
    @State private var link: ProfileShareLink?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Icon(.lock, size: 12, color: .textSecondary)
                    Text(link?.url ?? "expo-riyadh.example/p/…").textStyle(.enCaption).foregroundStyle(Color.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.bgSurface2, in: Capsule())
                .environment(\.layoutDirection, .leftToRight)

                StatusBanner(text: "معاينة: هذه صفحة ويب يفتحها المستلم دون تطبيق، وتُقدَّم من الخادم.", tone: .info)

                if let link, !link.isActive {
                    VStack(spacing: 12) {
                        IllustrationBadge(icon: .lock, tint: .textSecondary, background: .bgSurface2, size: 64, iconSize: 28)
                        Text("هذا الرابط لم يعد متاحًا").textStyle(.title3)
                        Text("عطّل صاحب الملف هذا الرابط أو انتهت صلاحيته. اطلب منه رابطًا جديدًا إن احتجت.")
                            .textStyle(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else if let profile {
                    Image("logo-expo-riyadh").resizable().scaledToFit().frame(height: 36)
                    ProfileCard(profile: profile, fields: link?.fields ?? Set(ProfileField.allCases))
                    HStack(spacing: 10) {
                        Text("تواصل بالبريد").appButtonLabelStyle(primary: true)
                        Text("LinkedIn").appButtonLabelStyle(primary: false)
                    }
                    .accessibilityHint("أزرار الصفحة العامة، غير فعّالة في المعاينة")
                    Text("شاركه \(profile.displayName) معك عبر إكسبو الرياض · \(link?.validUntilText.components(separatedBy: " · ").first ?? "") · هذه المشاركة ليست طلب توظيف.")
                        .textStyle(.caption).foregroundStyle(Color.textTertiary).multilineTextAlignment(.center)
                    Text("لا تحتاج تطبيقًا لعرض هذه الصفحة.").textStyle(.caption).foregroundStyle(Color.textTertiary)
                } else {
                    LoadingStateView()
                }
            }
            .padding(Spacing.screen)
        }
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "ما يراه المستلم")
        .toolbar(.visible, for: .navigationBar)
        .hidesMainChrome()
        .task {
            profile = try? await services.profile.profile()
            link = try? await services.profile.currentShareLink()
        }
    }
}

private extension Text {
    func appButtonLabelStyle(primary: Bool) -> some View {
        self.textStyle(.button)
            .foregroundStyle(primary ? Color.white : Color.brandPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(primary ? Color.brandPrimary : Color.brandMint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
