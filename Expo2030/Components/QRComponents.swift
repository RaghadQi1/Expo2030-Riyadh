import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Renders a QR code locally with Core Image (no network). Used for the friend invite (4.2) and the
/// professional-profile share link (14.05).
struct QRCodeImage: View {
    let text: String
    var size: CGFloat = 180

    var body: some View {
        Group {
            if let image = Self.make(text) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Icon(.qr, size: size * 0.6, color: .textPrimary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("رمز QR")
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Camera permission state for QR scanning (4.5 / 4.6, 14.10 / 14.11).
@MainActor
@Observable
final class CameraPermission {
    enum Status { case notDetermined, granted, denied, unavailable }
    private(set) var status: Status = .notDetermined

    init() { refresh() }

    func refresh() {
        guard AVCaptureDevice.default(for: .video) != nil else { status = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: status = .granted
        case .notDetermined: status = .notDetermined
        default: status = .denied
        }
    }

    /// Shows the system prompt. Call only after the in-app explainer.
    func request() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        status = granted ? .granted : .denied
        if AVCaptureDevice.default(for: .video) == nil { status = .unavailable }
    }
}

/// Live camera preview that reports the first QR payload it reads. Frames are never stored.
struct QRCameraView: UIViewRepresentable {
    var onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        let session = AVCaptureSession()
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(context.coordinator, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
        }
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.session = session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async { session?.stopRunning() }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var session: AVCaptureSession?
        private let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !delivered,
                  let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            delivered = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode(code)
        }
    }
}

/// Scanner viewfinder: camera (or a dark placeholder when unavailable, e.g. the Simulator) with corner brackets.
struct QRViewfinder: View {
    var cameraAvailable: Bool
    var hint: String
    var onCode: (String) -> Void

    var body: some View {
        ZStack {
            if cameraAvailable {
                QRCameraView(onCode: onCode)
            } else {
                Color.black.opacity(0.88)
            }
            VStack(spacing: 18) {
                ViewfinderFrame().frame(width: 240, height: 240)
                Text(hint)
                    .textStyle(.subhead)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                if !cameraAvailable {
                    Text("الكاميرا غير متاحة على هذا الجهاز")
                        .textStyle(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct ViewfinderFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 36
            Path { p in
                p.move(to: CGPoint(x: 0, y: l)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: l, y: 0))
                p.move(to: CGPoint(x: w - l, y: 0)); p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: l))
                p.move(to: CGPoint(x: w, y: h - l)); p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - l, y: h))
                p.move(to: CGPoint(x: l, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - l))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
