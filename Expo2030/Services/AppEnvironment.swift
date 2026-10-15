import Foundation
import Observation

/// Decides which service implementations the app uses.
///
/// * `.mock` (default) — everything runs on in-memory demo data (`Services/Mock`), with simulated
///   latency. Nothing leaves the device and the UI shows a small «نسخة تجريبية» badge.
/// * `.live` — the `Services/Live` implementations call the backend described in API_CONTRACT.md.
///   Requires `API_BASE_URL` (scheme env var or Info.plist key). Endpoints are proposals that must be
///   agreed with the backend developer.
enum APIMode: String {
    case mock, live
}

struct AppEnvironment {
    var mode: APIMode
    var baseURL: URL?

    static var current: AppEnvironment {
        let env = ProcessInfo.processInfo.environment
        let info = Bundle.main.infoDictionary ?? [:]
        let modeString = env["EXPO_API_MODE"] ?? (info["EXPO_API_MODE"] as? String) ?? "mock"
        let base = env["API_BASE_URL"] ?? (info["API_BASE_URL"] as? String)
        let url = base.flatMap { URL(string: $0) }
        let mode = APIMode(rawValue: modeString) ?? .mock
        // Live mode without a base URL falls back to mock so the app always runs.
        if mode == .live, url == nil { return AppEnvironment(mode: .mock, baseURL: nil) }
        return AppEnvironment(mode: mode, baseURL: url)
    }

    var isMock: Bool { mode == .mock }
}

/// Knobs for exercising loading / error / empty / offline states with mock data.
/// Exposed in «الإعدادات ← وضع العرض التجريبي». Has no effect in live mode.
@Observable
final class DemoSettings {
    static let shared = DemoSettings()

    /// Artificial network latency for mock services.
    var latency: Double = 0.6
    /// Next mock request fails with a server error (resets after one failure).
    var failNextRequest = false
    /// Mock services behave as if the device were offline.
    var simulateOffline = false
    /// Lists come back empty (to preview empty states).
    var emptyData = false
    /// The friend declines the next meeting-point proposal (to preview 6.6).
    var friendDeclinesMeeting = false
    /// Navigation pretends the visitor missed a turn once (to preview 2.10 «جارٍ تحديث المسار»).
    var simulateMissedTurn = false

    func consumeFailure() -> AppError? {
        if simulateOffline { return .offline }
        if failNextRequest {
            failNextRequest = false
            return .server("تعذّر الاتصال بالخادم. حاولي مرة أخرى.")
        }
        return nil
    }
}

/// Helper used by every mock service: waits `latency`, then throws a simulated failure if requested.
enum MockNetwork {
    static func roundTrip(_ settings: DemoSettings = .shared, extra: Double = 0) async throws {
        let delay = settings.latency + extra
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if let error = settings.consumeFailure() { throw error }
    }
}
