import SwiftUI

/// Adapter only: the original app's other tabs and services stay unchanged.
/// Map UI is the actual map imported from the second project.
struct MapTab: View {
    @Environment(AppState.self) private var app
    @State private var boot: Result<ExpoStore, Error>
    @State private var presentOriginalMap = false

    init() {
        _boot = State(initialValue: Result { try ExpoStore() })
    }

    var body: some View {
        Group {
            switch boot {
            case .success(let store):
                ExpoHomeView(store: store)
                    .environment(\.layoutDirection, .rightToLeft)
                    .environment(\.locale, Locale(identifier: "ar_SA"))
                    .task(id: app.mapRequest) { forwardMapRequest(to: store) }
            case .failure(let error):
                ContentUnavailableView("تعذر تحميل الخريطة", systemImage: "exclamationmark.triangle",
                                       description: Text(error.localizedDescription))
            }
        }
        .fullScreenCover(isPresented: $presentOriginalMap) {
            NavigationStack {
                LegacyMapTab()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("العودة للخريطة") { presentOriginalMap = false }
                        }
                    }
            }
        }
    }

    /// Keep deep links sent from the existing homepage / plan / assistant.
    /// Old friend / meeting screens are still available in the original map.
    private func forwardMapRequest(to store: ExpoStore) {
        guard let request = app.mapRequest else { return }
        switch request {
        case .showBooth(let id), .navigateToBooth(let id):
            let matched = store.dataset.indoor.spaces.contains { $0.id == id }
            if matched {
                if store.mode != .indoor { store.enterSaudi() }
                store.selectSpace(id)
                if case .navigateToBooth = request { store.showRoute() }
                app.mapRequest = nil
            } else if store.dataset.map.locations.contains(where: { $0.id == id }) {
                if store.mode == .indoor { store.exitSaudi() }
                store.selectLocation(id)
                app.mapRequest = nil
            } else {
                presentOriginalMap = true
            }
        case .meetingPoint, .friends, .scanFriend:
            presentOriginalMap = true
        }
    }
}
