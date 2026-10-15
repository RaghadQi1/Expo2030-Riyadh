import Foundation

// Every screen talks to these protocols only. `Mock*` implementations (Services/Mock) run on demo data;
// `Live*` implementations (Services/Live) call the endpoints proposed in API_CONTRACT.md.

/// Pavilions, events and the Discover feed. Screens: 08.01, 08.06, 08.07, 07.05.
protocol CatalogService: AnyObject {
    func discoverFeed(personalized: Bool) async throws -> DiscoverFeed
    func pavilions(filters: SearchFilters) async throws -> [Pavilion]
    func pavilion(id: String) async throws -> Pavilion
    func events() async throws -> [ExpoEvent]
    func event(id: String) async throws -> ExpoEvent
    func search(_ query: String) async throws -> [Pavilion]
    func priorityCandidates() async throws -> [PriorityCandidate]
}

/// Personalised plans and live re-planning. Screens: 07.06 – 07.08, 09.01 – 09.09, 08.10, conflict sheet.
protocol PlanService: AnyObject {
    /// Builds plan options. `progress` is called for each stage shown on 07.07.
    func generatePlan(_ preferences: PlanPreferences,
                      progress: @escaping @MainActor (PlanGenerationStage) -> Void) async throws -> [PlanOption]
    func currentPlan() async throws -> Plan?
    /// Schedulable dataset IDs for the Add Stop sheet; never fabricated catalog IDs.
    func addCandidates() async throws -> [PriorityCandidate]
    func adopt(_ option: PlanOption) async throws -> Plan
    /// Adds a pavilion or event. Returns `.conflict` when it overlaps a pinned item.
    func add(itemId: String) async throws -> AddToPlanResult
    func resolveConflict(_ conflict: PlanConflict, with option: ConflictOption) async throws -> Plan
    func proposeReplan(_ reason: ReplanReason) async throws -> ReplanProposal
    func apply(_ proposal: ReplanProposal) async throws -> Plan
    func crowdSituation() async throws -> CrowdSituation?
    func swap(to alternative: CrowdAlternative) async throws -> Plan
    func postponeCrowded() async throws -> Plan
    func undoLastChange() async throws -> Plan
    func finishVisit() async throws
}

/// Indoor hall map, search, routing and arrival. Screens: خريطتي 1.x – 3.x.
protocol MapService: AnyObject {
    func booths() async throws -> [Booth]
    func landmarks() async throws -> [MapLandmark]
    func crowdHotspots() async throws -> [CrowdHotspot]
    func currentLocation() async throws -> UserLocation
    func search(_ query: String, filter: MapFilter) async throws -> [SearchResult]
    func routes(to booth: Booth) async throws -> [Route]
    /// Single walking route to a friend or a meeting point (5.10, 6.7).
    func route(to target: NavigationTarget) async throws -> Route
    func alternatives(for booth: Booth) async throws -> [BoothAlternative]
    func confirmVisit(boothId: String) async throws -> BoothVisit
    func saveVisitNote(boothId: String, text: String) async throws -> BoothVisit
    func nextStop() async throws -> Booth?
}

/// Friends, invitations, location sharing and meeting points. Screens: خريطتي 4.x – 6.x.
protocol FriendsService: AnyObject {
    func friends() async throws -> [Friend]
    func inviteLink() async throws -> InviteLink
    func resolveInvite(code: String) async throws -> IncomingInvite
    func acceptInvite(_ invite: IncomingInvite) async throws -> Friend
    func declineInvite(_ invite: IncomingInvite) async throws
    func setShareMode(_ mode: LocationShareMode, with friendId: String) async throws -> Friend
    func setBackgroundSharing(_ enabled: Bool, with friendId: String) async throws -> Friend
    func setVisibleOnMap(_ visible: Bool, friendId: String) async throws -> Friend
    func stopSharing(with friendId: String) async throws -> Friend
    func removeFriend(_ friendId: String) async throws
    func endVisit() async throws
    func meetingPoints(with friendId: String) async throws -> [MeetingPoint]
    func proposeMeeting(_ point: MeetingPoint, with friendId: String) async throws -> MeetingState
    func meetingStatus(with friendId: String) async throws -> MeetingState
}

/// Expo assistant (12.x, خريطتي 7.x). Answers are suggestions; changes always need a preview + confirmation.
protocol AssistantService: AnyObject {
    func welcome(context: AssistantContext, userName: String?) async throws -> AssistantReply
    func send(_ text: String, context: AssistantContext) async throws -> AssistantReply
}

/// «رحلتي»: visits, notes, saved items, QR scanning and the AI summary. Screens: 13.x, 14.10 – 14.18, 17.x.
protocol JourneyService: AnyObject {
    func visits() async throws -> [JourneyVisit]
    func notes() async throws -> [VisitNote]
    func saved() async throws -> [SavedPlace]
    func followUps() async throws -> [FollowUpItem]
    func saveNote(_ note: VisitNote) async throws -> VisitNote
    func deleteNote(id: String) async throws
    func confirmVisit(placeId: String) async throws
    func toggleSaved(placeId: String) async throws -> Bool
    func scan(code: String) async throws -> ScannedPlace
    func summary() async throws -> JourneySummary
    func setFollowUp(id: String, done: Bool) async throws
    /// «حفظ الملخص» (13.07) — keeps an approved copy; the original notes are never changed.
    func saveSummary(_ summary: JourneySummary) async throws
    func savedSummaries() async throws -> [JourneySummary]
    /// What a guest has on this device (used before merging into a new account, 06.24).
    func guestDataSummary() async -> GuestDataSummary
}

/// Professional profile and share links. Screens: 14.01 – 14.09, 16.01.
protocol ProfileService: AnyObject {
    func profile() async throws -> ProfessionalProfile?
    func save(_ profile: ProfessionalProfile) async throws -> ProfessionalProfile
    func currentShareLink() async throws -> ProfileShareLink?
    func createShareLink(fields: Set<ProfileField>, validity: LinkValidity) async throws -> ProfileShareLink
    func disableShareLink() async throws
}

/// Offline queue (17.x). The mock keeps changes in memory and "syncs" when the demo goes back online.
protocol SyncService: AnyObject {
    var pendingChanges: Int { get }
    var lastSyncedText: String { get }
    func enqueue(_ description: String)
    func syncNow() async throws -> Int
}
