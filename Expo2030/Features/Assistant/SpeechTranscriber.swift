import AVFoundation
import Speech
import SwiftUI

/// On-device dictation for the assistant composer (12.05 – 12.07). Speech is converted to text that the
/// visitor reviews before sending; the recording itself is never sent anywhere by the app.
@MainActor
@Observable
final class SpeechTranscriber {
    enum Permission { case unknown, granted, denied, unavailable }

    var permission: Permission = .unknown
    var isRecording = false
    var transcript = ""

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ar-SA"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func refreshPermission() {
        let mic = AVAudioApplication.shared.recordPermission
        let speech = SFSpeechRecognizer.authorizationStatus()
        if mic == .denied || speech == .denied || speech == .restricted {
            permission = .denied
        } else if mic == .granted && speech == .authorized {
            permission = recognizer?.isAvailable == true ? .granted : .unavailable
        } else {
            permission = .unknown
        }
    }

    /// Shows the system prompts (microphone, then speech recognition).
    func requestPermission() async {
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else { permission = .denied; return }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: permission = recognizer?.isAvailable == true ? .granted : .unavailable
        default: permission = .denied
        }
    }

    func start() throws {
        guard permission == .granted, let recognizer, recognizer.isAvailable else { return }
        stop()
        transcript = ""
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self.stop() }
            }
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
