import AVFoundation
import CoreImage
import PhotosUI
import SwiftUI

/// Pavilion QR scanner (14.10 explainer · 14.11 system prompt · 14.12 scanning · 14.13 recognized · 14.18 manual code).
struct QRScannerView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraPermission()
    @State private var showExplainer = false
    @State private var scanned: ScannedPlace?
    @State private var pavilion: Pavilion?
    @State private var resolving = false
    @State private var torchOn = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showManual = false
    @State private var noteDraft: VisitNote?
    @State private var scanSession = UUID()

    var body: some View {
        ZStack(alignment: .top) {
            QRViewfinder(cameraAvailable: camera.status == .granted,
                         hint: scanned == nil ? "وجّه الكاميرا إلى رمز الجناح" : "تم التعرف على الرمز ✓") { code in
                Task { await resolve(code) }
            }
            .id(scanSession)

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Icon(.close, size: 18, color: .white).frame(width: 40, height: 40)
                            .background(.white.opacity(0.18), in: Circle())
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("إغلاق الماسح")
                }
                HStack(spacing: 6) {
                    Text("ماسح رموز الأجنحة").textStyle(.caption)
                    Icon(.qr, size: 14)
                }
                .foregroundStyle(Color.brandPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.brandMint, in: Capsule())
                Spacer()
                if scanned == nil { controls }
            }
            .padding(.horizontal, Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 40)

            if resolving {
                ProgressView().tint(.white).controlSize(.large).frame(maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .hidesMainChrome()
        .sheet(isPresented: $showExplainer) {
            PermissionExplainer(icon: .camera, title: "نستخدم الكاميرا لمسح الرمز فقط",
                                message: "لا نحفظ الصور ولا نسجل. بدون الكاميرا تقدر تدخل رمز الجناح يدويًا أو تختار صورة للرمز.",
                                primary: "متابعة", secondary: "إدخال الرمز يدويًا",
                                onPrimary: {
                                    showExplainer = false
                                    Task { await camera.request() }
                                },
                                onSecondary: {
                                    showExplainer = false
                                    showManual = true
                                })
            .presentationDetents([.height(360)])
            .interactiveDismissDisabled()
        }
        .sheet(item: $scanned) { place in
            ScanResultSheet(place: place, pavilion: pavilion, noteDraft: $noteDraft) {
                scanned = nil
                scanSession = UUID()
            }
            .presentationDetents([.height(330)])
        }
        .sheet(isPresented: $showManual) {
            NavigationStack {
                ManualCodeView { code in
                    showManual = false
                    Task { await resolve(code) }
                }
            }
        }
        .sheet(item: $noteDraft) { draft in
            NavigationStack { NoteEditorView(note: draft) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await scanPhoto(item) }
        }
        .onAppear {
            camera.refresh()
            if camera.status == .notDetermined { showExplainer = true }
        }
        .onDisappear { setTorch(false) }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            control(title: "إدخال الرمز", icon: .note) { showManual = true }
            PhotosPicker(selection: $photoItem, matching: .images) {
                controlLabel(title: "من الصور", icon: .image)
            }
            .buttonStyle(.plain)
            if camera.status == .granted {
                control(title: "المصباح", icon: .flashlight, active: torchOn) { setTorch(!torchOn) }
            }
        }
    }

    private func control(title: String, icon: AppIcon, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { controlLabel(title: title, icon: icon, active: active) }.buttonStyle(.plain)
    }

    private func controlLabel(title: String, icon: AppIcon, active: Bool = false) -> some View {
        VStack(spacing: 6) {
            Icon(icon, size: 22, color: active ? .brandPrimary : .white)
                .frame(width: 52, height: 52)
                .background(active ? Color.white : Color.white.opacity(0.18), in: Circle())
            Text(title).textStyle(.caption).foregroundStyle(.white)
        }
    }

    // MARK: Actions

    @MainActor private func resolve(_ code: String) async {
        guard !resolving else { return }
        resolving = true
        defer { resolving = false }
        do {
            let place = try await services.journey.scan(code: code)
            pavilion = try? await services.catalog.pavilion(id: place.placeId)
            scanned = place
            app.journeyRevision += 1
        } catch let error as AppError {
            toasts.show(error.message, icon: .warning, iconColor: .statusError)
            scanSession = UUID()
        } catch {
            toasts.show("لم نتعرف على هذا الرمز", icon: .warning, iconColor: .statusError)
            scanSession = UUID()
        }
    }

    /// «من الصور»: reads a QR code from a photo on the device (Core Image, no upload).
    @MainActor private func scanPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = CIImage(data: data) else { return }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let code = (detector?.features(in: image).first as? CIQRCodeFeature)?.messageString
        if let code { await resolve(code) }
        else { toasts.show("لم نجد رمز QR في الصورة", icon: .warning, iconColor: .statusError) }
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
        torchOn = on && device.torchMode == .on
    }
}

extension ScannedPlace: Identifiable {
    var id: String { placeId }
}

// MARK: - 14.13 result

struct ScanResultSheet: View {
    let place: ScannedPlace
    let pavilion: Pavilion?
    @Binding var noteDraft: VisitNote?
    var onDone: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var app
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var isSaved = false
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetGrabber()
            HStack(spacing: 12) {
                PhotoView(name: place.photo).frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).textStyle(.title3)
                    Text(subtitle).textStyle(.caption).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let live = pavilion?.live {
                HStack(spacing: 8) {
                    CrowdBadge(level: live.crowd)
                    FreshnessLine(status: live)
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                tile(isSaved ? "محفوظ" : "احفظ الجناح", icon: .heart, active: isSaved) {
                    Task {
                        if let s = try? await services.journey.toggleSaved(placeId: place.placeId) {
                            isSaved = s
                            toasts.show(s ? "حُفظ في «رحلتي ← محفوظة»" : "أُزيل من المحفوظات")
                            app.journeyRevision += 1
                        }
                    }
                }
                tile(confirmed ? "تم التأكيد" : "أكد زيارتي", icon: .check, active: confirmed) {
                    guard !confirmed else { return }
                    Task {
                        do {
                            try await services.journey.confirmVisit(placeId: place.placeId)
                            confirmed = true
                            app.journeyRevision += 1
                            toasts.show("تم تأكيد زيارتك")
                        } catch {
                            toasts.show("تعذّر تأكيد الزيارة", icon: .warning, iconColor: .statusError)
                        }
                    }
                }
                tile("أضف ملاحظة", icon: .note) {
                    dismiss()
                    noteDraft = VisitNote(id: UUID().uuidString, placeId: place.placeId, placeName: place.name)
                }
            }
            Text("المسح وحده لا يُعد إثبات حضور. «أكد زيارتي» اختياري ويُحفظ في رحلتك فقط.")
                .textStyle(.caption).foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onDisappear(perform: onDone)
    }

    private var subtitle: String {
        guard let p = pavilion else { return place.subtitle }
        return "\(place.subtitle) · \(p.durationMinutes) د"
    }

    private func tile(_ title: String, icon: AppIcon, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Icon(icon, size: 20, color: active ? .white : .brandPrimary)
                Text(title).textStyle(.caption).foregroundStyle(active ? Color.white : Color.brandPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(active ? Color.brandPrimary : Color.brandMint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 14.18 manual code

struct ManualCodeView: View {
    var onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        code.range(of: #"^[A-Za-z]{2}-?\d{2}$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("أدخل رمز الجناح").textStyle(.title1)
            Text("تجده مكتوبًا تحت رمز QR عند مدخل كل جناح (حرفان ورقمان).")
                .textStyle(.subhead).foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("رمز الجناح").textStyle(.footnote).foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Icon(.flag, size: 18, color: .textSecondary)
                    TextField("CA-09", text: $code)
                        .textStyle(.enBody)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { if isValid { onSubmit(code) } }
                }
                .environment(\.layoutDirection, .leftToRight)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Color.brandPrimary : Color.borderDefault, lineWidth: focused ? 2 : 1))
                Text("لوحة مفاتيح: أحرف لاتينية وأرقام · بلا تصحيح تلقائي")
                    .textStyle(.caption).foregroundStyle(Color.textTertiary)
            }
            Button("بحث") { onSubmit(code) }
                .appButton(.primary)
                .disabled(!isValid)
            Spacer()
        }
        .padding(20)
        .background(Color.bgCanvas.ignoresSafeArea())
        .appNavigationChrome(title: "إدخال يدوي")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Icon(.chevronRight, size: 22, color: .textPrimary) }
                    .accessibilityLabel("رجوع")
            }
        }
        .onAppear { focused = true }
    }
}
