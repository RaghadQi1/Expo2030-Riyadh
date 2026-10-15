import Foundation

/// Only user-owned records use the real SQLite-backed API. Map, recommendation,
/// friend positioning and other simulator features remain untouched.
final class AccountProfileService: ProfileService {
    let live: LiveProfileService
    let guest: MockProfileService
    let tokens: TokenStore
    init(live: LiveProfileService, guest: MockProfileService, tokens: TokenStore) {
        self.live = live; self.guest = guest; self.tokens = tokens
    }
    private var active: ProfileService { tokens.accessToken == nil ? guest : live }
    func profile() async throws -> ProfessionalProfile? { try await active.profile() }
    func save(_ profile: ProfessionalProfile) async throws -> ProfessionalProfile { try await active.save(profile) }
    func currentShareLink() async throws -> ProfileShareLink? { try await active.currentShareLink() }
    func createShareLink(fields: Set<ProfileField>, validity: LinkValidity) async throws -> ProfileShareLink {
        try await active.createShareLink(fields: fields, validity: validity)
    }
    func disableShareLink() async throws { try await active.disableShareLink() }
}

final class AccountJourneyService: JourneyService {
    let live: LiveJourneyService
    let guest: MockJourneyService
    let tokens: TokenStore
    private var uploadedPhotos = Set<String>()
    private var uploadOwnerToken: String?
    init(live: LiveJourneyService, guest: MockJourneyService, tokens: TokenStore) {
        self.live = live; self.guest = guest; self.tokens = tokens
    }
    private var active: JourneyService { tokens.accessToken == nil ? guest : live }
    func visits() async throws -> [JourneyVisit] { try await active.visits() }
    func notes() async throws -> [VisitNote] {
        let result = try await active.notes()
        if tokens.accessToken != nil {
            for attachment in result.flatMap(\.attachments) where attachment.kind == .photo {
                let destination = LocalAttachmentStore.url(for: attachment.value)
                if !FileManager.default.fileExists(atPath: destination.path),
                   let bytes = try? await live.downloadPhoto(fileName: attachment.value) {
                    try? bytes.write(to: destination, options: .completeFileProtection)
                }
            }
        }
        return result
    }
    func saved() async throws -> [SavedPlace] { try await active.saved() }
    func followUps() async throws -> [FollowUpItem] { try await active.followUps() }
    func saveNote(_ note: VisitNote) async throws -> VisitNote {
        if let token = tokens.accessToken {
            if uploadOwnerToken != token { uploadedPhotos.removeAll(); uploadOwnerToken = token }
            for attachment in note.attachments where attachment.kind == .photo && !uploadedPhotos.contains(attachment.value) {
                let url = LocalAttachmentStore.url(for: attachment.value)
                if let bytes = try? Data(contentsOf: url) {
                    try await live.uploadPhoto(fileName: attachment.value, data: bytes)
                    uploadedPhotos.insert(attachment.value)
                }
            }
        }
        return try await active.saveNote(note)
    }
    func deleteNote(id: String) async throws { try await active.deleteNote(id: id) }
    func confirmVisit(placeId: String) async throws { try await active.confirmVisit(placeId: placeId) }
    func toggleSaved(placeId: String) async throws -> Bool { try await active.toggleSaved(placeId: placeId) }
    func scan(code: String) async throws -> ScannedPlace {
        // QR's code catalog is still a local prototype; persist a scanned-only record separately.
        let place = try await guest.scan(code: code)
        if tokens.accessToken != nil { try await live.saveScannedVisit(place) }
        return place
    }
    func summary() async throws -> JourneySummary {
        // Existing summary generator is a demo. Saved summary still persists to SQLite.
        try await guest.summary()
    }
    func setFollowUp(id: String, done: Bool) async throws { try await active.setFollowUp(id: id, done: done) }
    func saveSummary(_ summary: JourneySummary) async throws { try await active.saveSummary(summary) }
    func savedSummaries() async throws -> [JourneySummary] { try await active.savedSummaries() }
    func guestDataSummary() async -> GuestDataSummary { await guest.guestDataSummary() }
}

/// Main catalog remains a prototype; priorities must come from the SAME dataset
/// the Gemini planner uses, so the user's selected IDs are actually resolvable.
final class AccountCatalogService: CatalogService {
    let demo: MockCatalogService
    let api: APIClient
    let tokens: TokenStore
    init(demo: MockCatalogService, api: APIClient, tokens: TokenStore) {
        self.demo = demo; self.api = api; self.tokens = tokens
    }
    func discoverFeed(personalized: Bool) async throws -> DiscoverFeed {
        try await demo.discoverFeed(personalized: personalized)
    }
    func pavilions(filters: SearchFilters) async throws -> [Pavilion] {
        try await demo.pavilions(filters: filters)
    }
    func pavilion(id: String) async throws -> Pavilion { try await demo.pavilion(id: id) }
    func events() async throws -> [ExpoEvent] { try await demo.events() }
    func event(id: String) async throws -> ExpoEvent { try await demo.event(id: id) }
    func search(_ query: String) async throws -> [Pavilion] { try await demo.search(query) }
    func priorityCandidates() async throws -> [PriorityCandidate] {
        if tokens.accessToken == nil { return try await demo.priorityCandidates() }
        return try await api.send(.get, "plans/priority-candidates")
    }
}

private struct ReplanIdBody: Encodable { let id: String }

/// Signed-in plans are selected with Gemini from the Flask event catalog.
/// Adopted plan and preferences persist in the authenticated SQLite account.
final class AccountPlanService: PlanService {
    let demo: MockPlanService
    let store: MockStore
    let api: APIClient
    let tokens: TokenStore
    private var hydratedToken: String?
    private var generatedPreferences: PlanPreferences?

    init(demo: MockPlanService, store: MockStore, api: APIClient, tokens: TokenStore) {
        self.demo = demo; self.store = store; self.api = api; self.tokens = tokens
    }

    private func hydrate() async throws {
        guard let token = tokens.accessToken else {
            if hydratedToken != nil { store.plan = nil }
            hydratedToken = nil
            return
        }
        if hydratedToken == token { return }
        store.plan = nil  // Avoid leaking previous signed-in user's plan.
        do {
            store.plan = try await api.send(.get, "plans/current", as: Plan.self)
        } catch AppError.notFound {
            store.plan = nil
        }
        hydratedToken = token
    }

    private func save(_ plan: Plan) async throws -> Plan {
        if tokens.accessToken != nil {
            let _: Plan = try await api.send(.put, "plans/current", body: plan)
        }
        return plan
    }

    func generatePlan(_ preferences: PlanPreferences,
                      progress: @escaping @MainActor (PlanGenerationStage) -> Void) async throws -> [PlanOption] {
        guard tokens.accessToken != nil else {
            return try await demo.generatePlan(preferences, progress: progress)
        }
        await progress(.readingPreferences)
        // No silent local/mock fallback: on API errors the user sees the real failure.
        let options: [PlanOption] = try await api.send(.post, "plans/generate", body: preferences)
        generatedPreferences = preferences
        await progress(.finishing)
        return options
    }
    func currentPlan() async throws -> Plan? {
        try await hydrate()
        return try await demo.currentPlan()
    }
    func adopt(_ option: PlanOption) async throws -> Plan {
        try await hydrate()
        if option.id.hasPrefix("gemini-") {
            let start = generatedPreferences?.time == .custom
                ? (generatedPreferences?.customStart?.minutes ?? 900) : 900
            let end: Int
            switch generatedPreferences?.time {
            case .oneHour: end = start + 60
            case .halfDay: end = start + 240
            case .custom: end = generatedPreferences?.customEnd?.minutes ?? (start + 120)
            default: end = start + 120
            }
            let window = "\(TimeOfDay(minutes: start).arabic12h)–\(TimeOfDay(minutes: end).arabic12h)"
            let plan = Plan(id: "plan-\(option.id)", name: option.name,
                            summary: "\(window) · مواعيد إكسبو",
                            steps: option.steps, endsAt: TimeOfDay(minutes: end))
            // Do not show a locally adopted plan until the SQLite-backed PUT succeeds.
            let persisted = try await save(plan)
            store.plan = persisted
            return persisted
        }
        return try await save(try await demo.adopt(option))
    }
    func addCandidates() async throws -> [PriorityCandidate] {
        try await hydrate()
        guard store.plan?.id.hasPrefix("plan-gemini-") == true else { return [] }
        return try await api.send(.get, "plans/add-candidates")
    }
    func add(itemId: String) async throws -> AddToPlanResult {
        try await hydrate()
        try rejectPrototypeChangesToGeminiPlan()
        let result = try await demo.add(itemId: itemId)
        if let plan = store.plan { _ = try await save(plan) }
        return result
    }
    func resolveConflict(_ conflict: PlanConflict, with option: ConflictOption) async throws -> Plan {
        try await hydrate()
        try rejectPrototypeChangesToGeminiPlan()
        return try await save(try await demo.resolveConflict(conflict, with: option))
    }
    func proposeReplan(_ reason: ReplanReason) async throws -> ReplanProposal {
        try await hydrate()
        if store.plan?.id.hasPrefix("plan-gemini-") == true {
            // Swift's Codable enum is sent directly; no untrusted free-form prompt.
            return try await api.send(.post, "plans/current/replan", body: reason)
        }
        return try await demo.proposeReplan(reason)
    }
    func apply(_ proposal: ReplanProposal) async throws -> Plan {
        try await hydrate()
        if store.plan?.id.hasPrefix("plan-gemini-") == true {
            let saved: Plan = try await api.send(.post, "plans/current/replan/apply",
                                                 body: ReplanIdBody(id: proposal.id.uuidString.lowercased()))
            store.plan = saved  // only after SQLite confirms success
            return saved
        }
        return try await save(try await demo.apply(proposal))
    }
    func crowdSituation() async throws -> CrowdSituation? {
        try await hydrate()
        // A demo crowd alert must never be shown as a live alert on a Gemini itinerary.
        if store.plan?.id.hasPrefix("plan-gemini-") == true { return nil }
        return try await demo.crowdSituation()
    }
    func swap(to alternative: CrowdAlternative) async throws -> Plan {
        try await hydrate()
        try rejectPrototypeChangesToGeminiPlan()
        return try await save(try await demo.swap(to: alternative))
    }
    func postponeCrowded() async throws -> Plan {
        try await hydrate()
        try rejectPrototypeChangesToGeminiPlan()
        return try await save(try await demo.postponeCrowded())
    }
    func undoLastChange() async throws -> Plan {
        try await hydrate()
        if store.plan?.id.hasPrefix("plan-gemini-") == true {
            let restored: Plan = try await api.send(.post, "plans/current/undo", body: ReplanIdBody(id: "undo"))
            store.plan = restored
            return restored
        }
        return try await save(try await demo.undoLastChange())
    }
    private func rejectPrototypeChangesToGeminiPlan() throws {
        if store.plan?.id.hasPrefix("plan-gemini-") == true {
            throw AppError.server("التعديل التلقائي لهذه الخطة غير متاح بعد؛ أعيدي إنشاء خطة من «تعديل» باستخدام Gemini.")
        }
    }

    func finishVisit() async throws {
        try await hydrate()
        try await demo.finishVisit()
        if tokens.accessToken != nil {
            let _: APIClient.Empty = try await api.send(.delete, "plans/current")
        }
    }
}

/// Preserve all existing indoor/map interactions. Only user-created visit records
/// and booth notes are mirrored to the logged-in user's SQLite journey.
final class AccountMapService: MapService {
    let demo: MockMapService
    let journey: LiveJourneyService
    let store: MockStore
    let api: APIClient
    let tokens: TokenStore
    private var previousOwner: String?
    init(demo: MockMapService, journey: LiveJourneyService, store: MockStore, api: APIClient, tokens: TokenStore) {
        self.demo = demo; self.journey = journey; self.store = store; self.api = api; self.tokens = tokens
    }
    private func separateLocalUsers() {
        let owner = tokens.accessToken
        if owner == previousOwner { return }
        if owner != nil || previousOwner != nil {
            // User A's in-memory mock visit/note data must never appear for user B or a guest.
            store.boothVisits.removeAll()
            store.visits.removeAll()
            store.notes.removeAll()
            store.saved.removeAll()
            store.followUps.removeAll()
            store.summaries.removeAll()
            store.profile = nil
            store.shareLink = nil
        }
        previousOwner = owner
    }
    func booths() async throws -> [Booth] {
        separateLocalUsers()
        if tokens.accessToken != nil, let records = try? await journey.visits() {
            for visit in records where visit.confirmation == .confirmed && MockMap.booth(visit.placeId) != nil {
                store.boothVisits[visit.placeId] = BoothVisit(boothId: visit.placeId,
                                                               arrivedAt: visit.start, confirmed: true)
            }
        }
        return try await demo.booths()
    }
    func landmarks() async throws -> [MapLandmark] { try await demo.landmarks() }
    func crowdHotspots() async throws -> [CrowdHotspot] { try await demo.crowdHotspots() }
    func currentLocation() async throws -> UserLocation { try await demo.currentLocation() }
    func search(_ query: String, filter: MapFilter) async throws -> [SearchResult] { try await demo.search(query, filter: filter) }
    func routes(to booth: Booth) async throws -> [Route] { try await demo.routes(to: booth) }
    func route(to target: NavigationTarget) async throws -> Route { try await demo.route(to: target) }
    func alternatives(for booth: Booth) async throws -> [BoothAlternative] { try await demo.alternatives(for: booth) }
    func confirmVisit(boothId: String) async throws -> BoothVisit {
        separateLocalUsers()
        let result = try await demo.confirmVisit(boothId: boothId)
        if tokens.accessToken != nil,
           let record = store.visits.first(where: { $0.placeId == boothId && $0.confirmation == .confirmed }) {
            let _: JourneyVisit = try await api.send(.put, "journey/visits/\(record.id)", body: record)
        }
        return result
    }
    func saveVisitNote(boothId: String, text: String) async throws -> BoothVisit {
        separateLocalUsers()
        let result = try await demo.saveVisitNote(boothId: boothId, text: text)
        if tokens.accessToken != nil,
           let record = store.notes.first(where: { $0.placeId == boothId }) {
            _ = try await journey.saveNote(record)
        }
        return result
    }
    func nextStop() async throws -> Booth? { try await demo.nextStop() }
}
