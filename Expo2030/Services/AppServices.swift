import Foundation
import Observation

/// Dependency container injected into the SwiftUI environment. Views and view models only ever
/// talk to these protocols, so switching from mock data to the real backend is a one-line change
/// here (see README «الربط بالباك إند»).
@Observable
final class AppServices {
    let environment: AppEnvironment
    let demo: DemoSettings

    let auth: AuthService
    let catalog: CatalogService
    let plan: PlanService
    let map: MapService
    let friends: FriendsService
    let assistant: AssistantService
    let journey: JourneyService
    let profile: ProfileService
    let sync: SyncService

    init(environment: AppEnvironment = .current, demo: DemoSettings = .shared) {
        self.environment = environment
        self.demo = demo

        switch environment.mode {
        case .live:
            let tokens = TokenStore()
            let api = APIClient(baseURL: environment.baseURL!, tokenStore: tokens)
            let guestStore = MockStore()
            // Auth/account, career profile, journey and current plan now persist in SQLite.
            auth = LiveAuthService(api: api, tokens: tokens)
            profile = AccountProfileService(live: LiveProfileService(api: api),
                                            guest: MockProfileService(store: guestStore, settings: demo),
                                            tokens: tokens)
            journey = AccountJourneyService(live: LiveJourneyService(api: api),
                                            guest: MockJourneyService(store: guestStore, settings: demo),
                                            tokens: tokens)
            plan = AccountPlanService(demo: MockPlanService(store: guestStore, settings: demo),
                                      store: guestStore, api: api, tokens: tokens)
            // These systems still use their original prototype data/logic; do not
            // direct them to nonexistent backend endpoints or change the map UI.
            catalog = AccountCatalogService(demo: MockCatalogService(store: guestStore, settings: demo),
                                            api: api, tokens: tokens)
            map = AccountMapService(demo: MockMapService(store: guestStore, settings: demo),
                                    journey: LiveJourneyService(api: api), store: guestStore,
                                    api: api, tokens: tokens)
            friends = MockFriendsService(store: guestStore, settings: demo)
            assistant = MockAssistantService(store: guestStore, settings: demo)
            sync = MockSyncService(settings: demo)
        case .mock:
            let store = MockStore()
            auth = MockAuthService(settings: demo)
            catalog = MockCatalogService(store: store, settings: demo)
            plan = MockPlanService(store: store, settings: demo)
            map = MockMapService(store: store, settings: demo)
            friends = MockFriendsService(store: store, settings: demo)
            assistant = MockAssistantService(store: store, settings: demo)
            journey = MockJourneyService(store: store, settings: demo)
            profile = MockProfileService(store: store, settings: demo)
            sync = MockSyncService(store: store, settings: demo)
        }
    }

    /// Container for SwiftUI previews.
    static let preview = AppServices(environment: AppEnvironment(mode: .mock, baseURL: nil))
}
