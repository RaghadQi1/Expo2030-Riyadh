import PhotosUI
import SwiftUI

/// 13.03 structured note, autosaved. Notes are saved on the device first (`JourneyService.saveNote`), so they
/// survive going offline (17.04) and sync later.
struct NoteEditorView: View {
    @State var note: VisitNote
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var lastSaved: Date?
    @State private var saveError = false
    @State private var history: [VisitNote] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showLinkAlert = false
    @State private var linkText = ""
    @State private var confirmDelete = false

    init(note: VisitNote) {
        _note = State(initialValue: note)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                autosaveStatus
                Text(note.placeName).textStyle(.caption).foregroundStyle(Color.brandPrimary)
                TextField("عنوان (اختياري)", text: $note.title, axis: .vertical)
                    .font(AppFont.arabic(22, .bold))
                    .foregroundStyle(Color.textPrimary)

                prompt("ما أعجبني", text: $note.liked, placeholder: "اكتب ما أعجبك…")
                prompt("ما تعلمته", text: $note.learned, placeholder: "اكتب ما تعلمته…")
                prompt("فكرة ألهمتني", text: $note.idea, placeholder: "اكتب فكرة…")
                prompt("سؤال للمتابعة", text: $note.followUpQuestion, placeholder: "اكتب سؤالًا تريد متابعته…")
                prompt("كتابة حرة", text: $note.freeText, placeholder: "اكتب ما تريد…")

                if !note.attachments.isEmpty { attachmentsGrid }

                HStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        chip("صورة", icon: .image)
                    }
                    Button { voiceNotAvailable() } label: { chip("ملاحظة صوتية", icon: .mic) }
                    Button { showLinkAlert = true } label: { chip("رابط", icon: .link) }
                    Spacer()
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "ملاحظة")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { if await save() { dismiss() } } } label: { Icon(.check, size: 22, color: .brandPrimary) }
                    .accessibilityLabel("تم")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { confirmDelete = true } label: { Icon(.trash, size: 22, color: .statusError) }
                    .accessibilityLabel("حذف الملاحظة")
                Spacer()
                Button { undo() } label: { Icon(.undo, size: 22, color: history.isEmpty ? .textTertiary : .textPrimary) }
                    .disabled(history.isEmpty)
                    .accessibilityLabel("تراجع")
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) { Icon(.image, size: 22, color: .textPrimary) }
                    .accessibilityLabel("إضافة صورة")
                Spacer()
                Button { voiceNotAvailable() } label: { Icon(.mic, size: 22, color: .textPrimary) }
                    .accessibilityLabel("ملاحظة صوتية")
                Spacer()
                Button { showLinkAlert = true } label: { Icon(.link, size: 22, color: .textPrimary) }
                    .accessibilityLabel("إضافة رابط")
            }
        }
        .hidesMainChrome()
        .task(id: note) {
            // Autosave 0.8 s after the last change.
            guard !note.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await save()
        }
        .onChange(of: note) { old, _ in
            if history.last != old { history.append(old) }
            if history.count > 30 { history.removeFirst() }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await attachPhoto(item) }
        }
        .alert("إضافة رابط", isPresented: $showLinkAlert) {
            TextField("https://", text: $linkText)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("إضافة") {
                let url = linkText.trimmingCharacters(in: .whitespaces)
                if !url.isEmpty { note.attachments.append(NoteAttachment(id: UUID().uuidString, kind: .link, value: url)) }
                linkText = ""
            }
            Button("إلغاء", role: .cancel) { linkText = "" }
        }
        .confirmationDialog("حذف هذه الملاحظة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف", role: .destructive) {
                Task {
                    do {
                        try await services.journey.deleteNote(id: note.id)
                        app.journeyRevision += 1
                        dismiss()
                        toasts.show("حُذفت الملاحظة", icon: .trash, iconColor: .textSecondary)
                    } catch {
                        toasts.show("تعذّر حذف الملاحظة من الخادم", icon: .warning, iconColor: .statusError)
                    }
                }
            }
            Button("إلغاء", role: .cancel) {}
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var autosaveStatus: some View {
        if saveError {
            HStack(spacing: 4) {
                Icon(.warning, size: 13, color: .statusError)
                Text("تعذّر الحفظ، سنحاول مجددًا").textStyle(.caption).foregroundStyle(Color.statusError)
            }
        } else if let lastSaved {
            HStack(spacing: 4) {
                Icon(note.isPendingSync ? .refresh : .check, size: 13, color: note.isPendingSync ? .statusWarning : .statusSuccess)
                Text(note.isPendingSync ? "محفوظ على جهازك · بانتظار المزامنة"
                                        : "محفوظ تلقائيًا · \(Self.timeFormatter.string(from: lastSaved))")
                    .textStyle(.caption)
                    .foregroundStyle(note.isPendingSync ? Color.statusWarning : Color.statusSuccess)
            }
        }
    }

    private func prompt(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).textStyle(.caption).foregroundStyle(Color.textSecondary)
            TextField(placeholder, text: text, axis: .vertical)
                .textStyle(.body)
                .lineLimit(1...8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSurface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(_ title: String, icon: AppIcon) -> some View {
        HStack(spacing: 6) {
            Text(title).textStyle(.caption)
            Icon(icon, size: 14)
        }
        .foregroundStyle(Color.brandPrimary)
        .padding(.horizontal, 12).frame(height: 34)
        .background(Color.brandMint, in: Capsule())
    }

    private var attachmentsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            let photos = note.attachments.filter { $0.kind == .photo }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { a in
                            AttachmentImage(value: a.value)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .topLeading) { removeButton(a) }
                        }
                    }
                }
            }
            ForEach(note.attachments.filter { $0.kind != .photo }) { a in
                HStack(spacing: 8) {
                    Icon(a.kind == .voice ? .volume : .link, size: 16, color: .brandPrimary)
                    Text(a.kind == .voice ? "\(a.kind.title) · \(a.value)" : a.value)
                        .textStyle(.footnote).foregroundStyle(Color.textPrimary).lineLimit(1)
                        .environment(\.layoutDirection, a.kind == .link ? .leftToRight : .rightToLeft)
                    Spacer()
                    removeButton(a)
                }
                .padding(10)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func removeButton(_ a: NoteAttachment) -> some View {
        Button { note.attachments.removeAll { $0.id == a.id } } label: {
            Icon(.close, size: 12, color: .white).frame(width: 22, height: 22)
                .background(Color.black.opacity(0.55), in: Circle())
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("إزالة المرفق")
    }

    // MARK: Actions

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_SA@numbers=latn")
        f.dateFormat = "h:mm a"
        return f
    }()

    @discardableResult private func save() async -> Bool {
        do {
            let saved = try await services.journey.saveNote(note)
            note.isPendingSync = saved.isPendingSync
            lastSaved = Date()
            saveError = false
            app.journeyRevision += 1
            return true
        } catch {
            saveError = true
            return false
        }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        note = previous
        _ = history.popLast() // the onChange above pushed the state we just left
    }

    /// Photos are copied into the app's Documents folder; uploading them is part of the notes API.
    private func attachPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            toasts.show("تعذّر إرفاق الصورة", icon: .warning, iconColor: .statusError)
            return
        }
        do {
            let url = try LocalAttachmentStore.save(data, ext: "jpg")
            note.attachments.append(NoteAttachment(id: UUID().uuidString, kind: .photo, value: url.lastPathComponent))
        } catch {
            toasts.show("تعذّر حفظ الصورة على الجهاز", icon: .warning, iconColor: .statusError)
        }
    }

    private func voiceNotAvailable() {
        toasts.show("الملاحظات الصوتية غير مفعّلة في هذه النسخة بعد", icon: .info, iconColor: .statusInfo)
    }
}

/// Files the visitor attaches (note photos, CV) are kept in Application Support until the backend stores them.
enum LocalAttachmentStore {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func save(_ data: Data, ext: String) throws -> URL {
        let url = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: url, options: .completeFileProtection)
        return url
    }

    static func url(for name: String) -> URL { folder.appendingPathComponent(name) }
}

/// Attachment photo: a bundled asset (demo data) or a file saved by `LocalAttachmentStore`.
struct AttachmentImage: View {
    let value: String
    var body: some View {
        if let image = UIImage(named: value) ?? UIImage(contentsOfFile: LocalAttachmentStore.url(for: value).path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.bgSurface2.overlay(Icon(.image, size: 22, color: .textTertiary))
        }
    }
}
