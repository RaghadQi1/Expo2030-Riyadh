import SwiftUI

/// Main app shell: five tabs with the Figma floating glass tab bar (361×64, radius 32, 16-pt margins)
/// and the assistant button pinned bottom-left, 12 pt above the tab bar.
struct MainTabView: View {
    @Environment(AppState.self) private var app
    @Environment(AppServices.self) private var services
    @Environment(ConnectivityMonitor.self) private var connectivity
    @Environment(ToastCenter.self) private var toasts
    @State private var keyboardVisible = false

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            TabView(selection: $app.selectedTab) {
                DiscoverTab().toolbar(.hidden, for: .tabBar).tag(MainTab.discover)
                PlanTab().toolbar(.hidden, for: .tabBar).tag(MainTab.plan)
                MapTab().toolbar(.hidden, for: .tabBar).tag(MainTab.map)
                JourneyTab().toolbar(.hidden, for: .tabBar).tag(MainTab.journey)
                AccountTab().toolbar(.hidden, for: .tabBar).tag(MainTab.account)
            }

            if !app.isChromeHidden && !keyboardVisible {
                VStack(alignment: .trailing, spacing: 12) {
                    AssistantFAB { app.isAssistantPresented = true }
                        .padding(.leading, 0)
                    FloatingTabBar(selection: $app.selectedTab)
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.isChromeHidden)
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .sheet(isPresented: $app.isAssistantPresented) {
            AssistantSheet(context: app.selectedTab.assistantContext)
        }
        .fullScreenCover(isPresented: $app.isAuthPresented) {
            AuthFlowView(isModal: true)
        }
        .onChange(of: connectivity.isOffline) { wasOffline, isOffline in
            // 17.06: connection is back → flush the offline queue.
            guard wasOffline, !isOffline, services.sync.pendingChanges > 0 else { return }
            Task { @MainActor in
                if let count = try? await services.sync.syncNow(), count > 0 {
                    app.journeyRevision += 1
                    toasts.show("عاد الاتصال · تمت مزامنة \(count) \(count == 1 ? "ملاحظة" : "ملاحظات")")
                }
            }
        }
    }
}

extension MainTab {
    var assistantContext: AssistantContext {
        switch self {
        case .discover: .general
        case .plan: .plan
        case .map: .map
        case .journey: .journey
        case .account: .general
        }
    }
}

/// Figma «Tab Bar» (1:1045): glass/tint-strong capsule, 68×52 items, selected item on brand/mint.
struct FloatingTabBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Icon(tab.icon, size: 22, color: isSelected ? .brandPrimary : .textSecondary)
                        Text(tab.title)
                            .textStyle(.caption2)
                            .foregroundStyle(isSelected ? Color.brandPrimary : Color.textSecondary)
                    }
                    .frame(width: 68, height: 52)
                    .background(isSelected ? Color.brandMint : .clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(tab.title)، تبويب، \(tab.rawValue + 1) من 5")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .frame(maxWidth: 361)
        .glassBackground(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .glassShadow()
    }
}

/// Figma «Assistant FAB» (1:1013): 48-pt brand capsule with the sparkles icon. Never auto-opens or pulses.
struct AssistantFAB: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(.sparkles, size: 24, color: .white)
                .frame(width: 48, height: 48)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.glassStroke, lineWidth: 1))
                .glassShadow()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("مساعد إكسبو")
        .accessibilityHint("يفتح المساعد مع سياق الشاشة الحالية")
    }
}

/// Hides the floating tab bar and assistant button while a pushed detail screen is visible.
struct HidesMainChrome: ViewModifier {
    @Environment(AppState.self) private var app
    func body(content: Content) -> some View {
        content
            .onAppear { app.chromeHideRequests += 1 }
            .onDisappear { app.chromeHideRequests = max(0, app.chromeHideRequests - 1) }
    }
}

extension View {
    func hidesMainChrome() -> some View { modifier(HidesMainChrome()) }

    /// Bottom padding so scroll content clears the floating tab bar + FAB.
    func tabBarSafeArea() -> some View { safeAreaPadding(.bottom, 84) }
}
