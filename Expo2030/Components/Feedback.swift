import SwiftUI

// MARK: - Banner (Figma "Banner" 1:3092)

enum BannerTone {
    case info, warning, success, error, neutral

    var background: Color {
        switch self {
        case .info: .statusInfoBg
        case .warning: .statusWarningBg
        case .success: .statusSuccessBg
        case .error: .statusErrorBg
        case .neutral: .bgSurface2
        }
    }

    var foreground: Color {
        switch self {
        case .info: .statusInfo
        case .warning: .statusWarning
        case .success: .statusSuccess
        case .error: .statusError
        case .neutral: .textSecondary
        }
    }

    var defaultIcon: AppIcon {
        switch self {
        case .info, .neutral: .info
        case .warning, .error: .warning
        case .success: .check
        }
    }
}

/// Persistent status banner: AR/Footnote text, 20pt icon on the right (RTL leading), radius 14.
struct StatusBanner: View {
    let text: String
    var tone: BannerTone = .info
    var icon: AppIcon? = nil
    /// Inline underlined link appended to the text (e.g. «لإنشاء حسابك اضغط هنا»).
    var linkTitle: String? = nil
    var onLink: (() -> Void)? = nil
    /// Pill action on the left edge (e.g. «إعادة المحاولة», «إيقاف»).
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Icon(icon ?? tone.defaultIcon, size: 20, color: tone.foreground)
            Group {
                if let linkTitle {
                    (Text(text + " ") + Text(linkTitle).underline())
                } else {
                    Text(text)
                }
            }
            .textStyle(.footnote)
            .foregroundStyle(tone.foreground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            if let actionTitle {
                Button(actionTitle) { onAction?() }
                    .textStyle(.caption)
                    .foregroundStyle(tone.foreground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.textPrimary.opacity(0.07), in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onLink?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onLink != nil ? .isButton : [])
    }
}

// MARK: - Toast (Figma "Toast")

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var icon: AppIcon? = .check
    var iconColor: Color = .statusSuccess
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

/// White capsule-ish toast with Shadow/Floating (#0A1F17 10%, y 12, blur 32).
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            if let icon = toast.icon {
                Icon(icon, size: 20, color: toast.iconColor)
            }
            Text(toast.text)
                .textStyle(.subhead)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
            if let title = toast.actionTitle {
                Button(title) { toast.action?() }
                    .textStyle(.subheadStrong)
                    .foregroundStyle(Color.textLink)
                    .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .background(Color.bgSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .shadowTint.opacity(0.10), radius: 16, x: 0, y: 12)
        .accessibilityElement(children: .combine)
    }
}

/// App-wide toast presenter. Views call `toastCenter.show(...)`.
@Observable
final class ToastCenter {
    var current: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ text: String, icon: AppIcon? = .check, iconColor: Color = .statusSuccess,
              actionTitle: String? = nil, action: (() -> Void)? = nil, duration: Double = 3) {
        dismissTask?.cancel()
        current = ToastMessage(text: text, icon: icon, iconColor: iconColor, actionTitle: actionTitle, action: action)
        UIAccessibility.post(notification: .announcement, argument: text)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self?.current = nil }
        }
    }

    func dismiss() { current = nil }
}

struct ToastHost: ViewModifier {
    @Environment(ToastCenter.self) private var toastCenter
    var topPadding: CGFloat = 8

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toastCenter.current {
                ToastView(toast: toast)
                    .padding(.top, topPadding)
                    .padding(.horizontal, Spacing.screen)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { toastCenter.dismiss() }
                    .zIndex(100)
            }
        }
        .animation(.spring(duration: 0.35), value: toastCenter.current)
    }
}

extension View {
    func toastHost(topPadding: CGFloat = 8) -> some View { modifier(ToastHost(topPadding: topPadding)) }
}

// MARK: - Loading / empty / error states

/// Generic loadable state used by view models so every screen can show loading, error and empty states.
enum Loadable<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct LoadingStateView: View {
    var title: String = "جارٍ التحميل…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.brandPrimary).controlSize(.large)
            Text(title).textStyle(.footnote).foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            IllustrationBadge(icon: error.isOffline ? .refresh : .warning,
                              tint: error.isOffline ? .statusWarning : .statusError,
                              background: error.isOffline ? .statusWarningBg : Color.statusError.opacity(0.1),
                              size: 72, iconSize: 32)
            Text(error.title).textStyle(.headline).foregroundStyle(Color.textPrimary)
            Text(error.message)
                .textStyle(.footnote).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("إعادة المحاولة", action: retry)
                    .appButton(.mint, height: 44, fullWidth: false)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: AppIcon
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            IllustrationBadge(icon: icon, size: 72, iconSize: 32)
            Text(title).textStyle(.headline).foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message).textStyle(.footnote).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).appButton(.primary, fullWidth: false)
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Small label shown while the app runs on mock services, so demo actions are never presented
/// as real operations. Disappears automatically when `AppEnvironment.mode == .live`.
struct DemoModeBadge: View {
    var body: some View {
        EmptyView()
    }
}
