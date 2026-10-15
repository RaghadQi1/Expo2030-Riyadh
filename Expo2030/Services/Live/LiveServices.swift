import Foundation

// Live implementations. Every path, payload and response here is a PROPOSAL documented in API_CONTRACT.md
// and must be agreed with the backend developer before use. Nothing here has been tested against a server.

private struct IdBody: Encodable { var id: String }
private struct TextBody: Encodable { var text: String }

final class LiveCatalogService: CatalogService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func discoverFeed(personalized: Bool) async throws -> DiscoverFeed {
        try await api.send(.get, "discover", query: ["personalized": personalized ? "true" : "false"])
    }
    func pavilions(filters: SearchFilters) async throws -> [Pavilion] {
        var q: [String: String] = [:]
        if !filters.axes.isEmpty { q["axes"] = filters.axes.map(\.rawValue).sorted().joined(separator: ",") }
        if let d = filters.maxDistanceMeters { q["max_distance"] = String(d) }
        if filters.lowCrowdOnly { q["crowd"] = "low" }
        if filters.openNow { q["open_now"] = "true" }
        return try await api.send(.get, "pavilions", query: q)
    }
    func pavilion(id: String) async throws -> Pavilion { try await api.send(.get, "pavilions/\(id)") }
    func events() async throws -> [ExpoEvent] { try await api.send(.get, "events") }
    func event(id: String) async throws -> ExpoEvent { try await api.send(.get, "events/\(id)") }
    func search(_ query: String) async throws -> [Pavilion] { try await api.send(.get, "search", query: ["q": query]) }
    func priorityCandidates() async throws -> [PriorityCandidate] { try await api.send(.get, "plans/priority-candidates") }
}

final class LivePlanService: PlanService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func generatePlan(_ preferences: PlanPreferences,
                      progress: @escaping @MainActor (PlanGenerationStage) -> Void) async throws -> [PlanOption] {
        // The proposed API is synchronous (< 10 s). Stages are shown client-side while waiting.
        await progress(.readingPreferences)
        let options: [PlanOption] = try await api.send(.post, "plans/generate", body: preferences)
        await progress(.finishing)
        return options
    }
    func currentPlan() async throws -> Plan? {
        do { return try await api.send(.get, "plans/current", as: Plan.self) } catch AppError.notFound { return nil }
    }
    func addCandidates() async throws -> [PriorityCandidate] {
        try await api.send(.get, "plans/add-candidates")
    }
    func adopt(_ option: PlanOption) async throws -> Plan { try await api.send(.post, "plans/adopt", body: IdBody(id: option.id)) }
    func add(itemId: String) async throws -> AddToPlanResult { try await api.send(.post, "plans/current/items", body: IdBody(id: itemId)) }
    func resolveConflict(_ conflict: PlanConflict, with option: ConflictOption) async throws -> Plan {
        try await api.send(.post, "plans/current/conflicts/resolve", body: IdBody(id: option.id))
    }
    func proposeReplan(_ reason: ReplanReason) async throws -> ReplanProposal {
        try await api.send(.post, "plans/current/replan", body: reason)
    }
    func apply(_ proposal: ReplanProposal) async throws -> Plan {
        try await api.send(.post, "plans/current/replan/apply", body: IdBody(id: proposal.id.uuidString))
    }
    func crowdSituation() async throws -> CrowdSituation? {
        do { return try await api.send(.get, "plans/current/crowd-alerts", as: CrowdSituation.self) } catch AppError.notFound { return nil }
    }
    func swap(to alternative: CrowdAlternative) async throws -> Plan {
        try await api.send(.post, "plans/current/swap", body: IdBody(id: alternative.id))
    }
    func postponeCrowded() async throws -> Plan { try await api.send(.post, "plans/current/postpone-crowded") }
    func undoLastChange() async throws -> Plan { try await api.send(.post, "plans/current/undo") }
    func finishVisit() async throws { let _: APIClient.Empty = try await api.send(.post, "plans/current/finish") }
}

final class LiveMapService: MapService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func booths() async throws -> [Booth] { try await api.send(.get, "map/booths") }
    func landmarks() async throws -> [MapLandmark] { try await api.send(.get, "map/landmarks") }
    func crowdHotspots() async throws -> [CrowdHotspot] { try await api.send(.get, "map/crowd") }
    /// Indoor positioning is device-side (beacons / UWB / provider SDK) — see API_CONTRACT.md §Map.
    func currentLocation() async throws -> UserLocation { try await api.send(.get, "map/me") }
    func search(_ query: String, filter: MapFilter) async throws -> [SearchResult] {
        var q = ["q": query, "category": filter.category.rawValue]
        if !filter.crowd.isEmpty { q["crowd"] = filter.crowd.map(\.rawValue).sorted().joined(separator: ",") }
        if let d = filter.maxDistance { q["max_distance"] = String(d) }
        return try await api.send(.get, "map/search", query: q)
    }
    func routes(to booth: Booth) async throws -> [Route] { try await api.send(.get, "map/routes", query: ["to": booth.id]) }
    func route(to target: NavigationTarget) async throws -> Route {
        let p = target.point
        return try await api.send(.get, "map/route", query: ["x": String(p.x), "y": String(p.y)])
    }
    func alternatives(for booth: Booth) async throws -> [BoothAlternative] { try await api.send(.get, "map/booths/\(booth.id)/alternatives") }
    func confirmVisit(boothId: String) async throws -> BoothVisit { try await api.send(.post, "visits", body: IdBody(id: boothId)) }
    func saveVisitNote(boothId: String, text: String) async throws -> BoothVisit {
        try await api.send(.post, "visits/\(boothId)/note", body: TextBody(text: text))
    }
    func nextStop() async throws -> Booth? { try await api.send(.get, "map/next-stop") }
}

final class LiveFriendsService: FriendsService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    private struct ShareBody: Encodable { var mode: LocationShareMode }
    private struct FlagBody: Encodable { var enabled: Bool }
    private struct CodeBody: Encodable { var code: String }

    func friends() async throws -> [Friend] { try await api.send(.get, "friends") }
    func inviteLink() async throws -> InviteLink { try await api.send(.post, "friends/invites") }
    func resolveInvite(code: String) async throws -> IncomingInvite { try await api.send(.get, "friends/invites/\(code)") }
    func acceptInvite(_ invite: IncomingInvite) async throws -> Friend { try await api.send(.post, "friends/invites/\(invite.id)/accept") }
    func declineInvite(_ invite: IncomingInvite) async throws {
        let _: APIClient.Empty = try await api.send(.post, "friends/invites/\(invite.id)/decline")
    }
    func setShareMode(_ mode: LocationShareMode, with friendId: String) async throws -> Friend {
        try await api.send(.put, "friends/\(friendId)/sharing", body: ShareBody(mode: mode))
    }
    func setBackgroundSharing(_ enabled: Bool, with friendId: String) async throws -> Friend {
        try await api.send(.put, "friends/\(friendId)/sharing/background", body: FlagBody(enabled: enabled))
    }
    /// Visibility is a local display preference; it never changes what the friend shares.
    func setVisibleOnMap(_ visible: Bool, friendId: String) async throws -> Friend {
        try await api.send(.put, "friends/\(friendId)/visibility", body: FlagBody(enabled: visible))
    }
    func stopSharing(with friendId: String) async throws -> Friend { try await api.send(.delete, "friends/\(friendId)/sharing") }
    func removeFriend(_ friendId: String) async throws { let _: APIClient.Empty = try await api.send(.delete, "friends/\(friendId)") }
    func endVisit() async throws { let _: APIClient.Empty = try await api.send(.post, "visits/end") }
    func meetingPoints(with friendId: String) async throws -> [MeetingPoint] {
        try await api.send(.get, "friends/\(friendId)/meeting-points")
    }
    func proposeMeeting(_ point: MeetingPoint, with friendId: String) async throws -> MeetingState {
        try await api.send(.post, "friends/\(friendId)/meetings", body: IdBody(id: point.id))
    }
    func meetingStatus(with friendId: String) async throws -> MeetingState { try await api.send(.get, "friends/\(friendId)/meetings/current") }
}

final class LiveAssistantService: AssistantService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    private struct MessageBody: Encodable { var text: String; var context: AssistantContext }

    func welcome(context: AssistantContext, userName: String?) async throws -> AssistantReply {
        try await api.send(.post, "assistant/sessions", body: MessageBody(text: "", context: context))
    }
    func send(_ text: String, context: AssistantContext) async throws -> AssistantReply {
        try await api.send(.post, "assistant/messages", body: MessageBody(text: text, context: context))
    }
}

final class LiveJourneyService: JourneyService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func uploadPhoto(fileName: String, data: Data) async throws {
        _ = try await api.attachment(fileName, upload: data)
    }
    func downloadPhoto(fileName: String) async throws -> Data {
        guard let data = try await api.attachment(fileName) else { throw AppError.notFound }
        return data
    }
    private struct SavedResponse: Decodable { var saved: Bool }
    private struct CodeBody: Encodable { var code: String }

    func visits() async throws -> [JourneyVisit] { try await api.send(.get, "journey/visits") }
    func notes() async throws -> [VisitNote] { try await api.send(.get, "notes") }
    func saved() async throws -> [SavedPlace] { try await api.send(.get, "journey/saved") }
    func followUps() async throws -> [FollowUpItem] { try await api.send(.get, "journey/follow-ups") }
    func saveNote(_ note: VisitNote) async throws -> VisitNote { try await api.send(.put, "notes/\(note.id)", body: note) }
    func deleteNote(id: String) async throws { let _: APIClient.Empty = try await api.send(.delete, "notes/\(id)") }
    private struct PlaceBody: Encodable {
        var id: String
        var title: String
        var subtitle: String
        var photo: String?
    }
    private func placeBody(_ id: String) -> PlaceBody {
        if let p = MockCatalog.pavilion(id) {
            return PlaceBody(id: id, title: p.name,
                             subtitle: "\(p.axis.title) · \(p.experienceType)", photo: p.photo)
        }
        return PlaceBody(id: id, title: id, subtitle: "", photo: nil)
    }
    func confirmVisit(placeId: String) async throws {
        let _: APIClient.Empty = try await api.send(.post, "visits", body: placeBody(placeId))
    }
    func toggleSaved(placeId: String) async throws -> Bool {
        let r: SavedResponse = try await api.send(.post, "journey/saved/toggle", body: placeBody(placeId))
        return r.saved
    }
    func saveScannedVisit(_ place: ScannedPlace) async throws {
        let stamp = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let time = TimeOfDay(stamp.hour ?? 0, stamp.minute ?? 0)
        let record = JourneyVisit(id: "scan-\(place.placeId)", placeId: place.placeId,
                                  title: place.name, start: time, end: nil,
                                  confirmation: .scannedOnly(time), extrasText: nil,
                                  thumbnail: place.photo)
        let _: JourneyVisit = try await api.send(.put, "journey/visits/\(record.id)", body: record)
    }
    func scan(code: String) async throws -> ScannedPlace { try await api.send(.post, "qr/resolve", body: CodeBody(code: code)) }
    func summary() async throws -> JourneySummary { try await api.send(.post, "journey/summary") }
    private struct DoneBody: Encodable { var done: Bool }
    func setFollowUp(id: String, done: Bool) async throws {
        let _: APIClient.Empty = try await api.send(.put, "journey/follow-ups/\(id)", body: DoneBody(done: done))
    }
    func saveSummary(_ summary: JourneySummary) async throws {
        let _: APIClient.Empty = try await api.send(.post, "journey/summaries", body: summary)
    }
    func savedSummaries() async throws -> [JourneySummary] { try await api.send(.get, "journey/summaries") }
    /// Guest data lives on the device until the backend exists; the merge endpoint receives this summary.
    func guestDataSummary() async -> GuestDataSummary {
        GuestDataSummary(hasPlan: false, hasPreferences: false, notesCount: 0, photosCount: 0, savedPavilionsCount: 0)
    }
}

final class LiveProfileService: ProfileService {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    private struct LinkBody: Encodable { var fields: [ProfileField]; var validity: LinkValidity }
    func uploadCV(_ data: Data, fileName: String) async throws {
        try await api.uploadCV(data, fileName: fileName)
    }
    func removeCV() async throws {
        let _: APIClient.Empty = try await api.send(.delete, "me/cv")
    }

    func profile() async throws -> ProfessionalProfile? {
        do { return try await api.send(.get, "me/profile", as: ProfessionalProfile.self) } catch AppError.notFound { return nil }
    }
    func save(_ profile: ProfessionalProfile) async throws -> ProfessionalProfile { try await api.send(.put, "me/profile", body: profile) }
    func currentShareLink() async throws -> ProfileShareLink? {
        do { return try await api.send(.get, "me/profile/share-link", as: ProfileShareLink.self) } catch AppError.notFound { return nil }
    }
    func createShareLink(fields: Set<ProfileField>, validity: LinkValidity) async throws -> ProfileShareLink {
        try await api.send(.post, "me/profile/share-link", body: LinkBody(fields: Array(fields), validity: validity))
    }
    func disableShareLink() async throws { let _: APIClient.Empty = try await api.send(.delete, "me/profile/share-link") }
}
