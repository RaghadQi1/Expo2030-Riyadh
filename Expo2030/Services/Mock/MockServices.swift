import Foundation

/// In-memory state shared by the mock services so that actions on one screen show up on others
/// (e.g. a note saved from the map appears in «رحلتي»). Nothing is persisted or sent anywhere.
final class MockStore {
    var plan: Plan?
    var planBeforeLastChange: Plan?
    var notes: [VisitNote] = MockJourney.notes
    var visits: [JourneyVisit] = MockJourney.visits
    var saved: [SavedPlace] = MockJourney.saved
    var followUps: [FollowUpItem] = MockJourney.followUps
    var boothVisits: [String: BoothVisit] = [:]
    var friends: [Friend] = [MockMap.reem]
    var meeting: MeetingState = .none
    var profile: ProfessionalProfile? = nil
    var shareLink: ProfileShareLink? = nil
    var crowdResolved = false
    var summaries: [JourneySummary] = []

    init() {}
}

// MARK: - Catalog

final class MockCatalogService: CatalogService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func discoverFeed(personalized: Bool) async throws -> DiscoverFeed {
        try await MockNetwork.roundTrip(settings)
        if settings.emptyData {
            return DiscoverFeed(nextStop: nil, axes: ExpoAxis.allCases, opportunities: [], upcomingEvents: [], recommendations: [])
        }
        let next: NextStopSummary? = store.plan == nil ? nil : NextStopSummary(
            progressText: "رحلتك اليوم · 1 من 4", progress: 0.25, title: "التالي: جناح الذكاء والمستقبل",
            subtitle: "ورشة الروبوتات", startsAt: "تبدأ 3:30 م", pavilionId: "p1-ai-future")
        let pavilions = MockCatalog.pavilions
        return DiscoverFeed(
            nextStop: personalized ? next : nil,
            axes: ExpoAxis.allCases,
            opportunities: personalized ? [pavilions[0], pavilions[3], pavilions[8]] : [pavilions[0], pavilions[5], pavilions[8]],
            upcomingEvents: Array(MockCatalog.events.prefix(4)),
            recommendations: [pavilions[5], pavilions[4], pavilions[7], pavilions[9]])
    }

    func pavilions(filters: SearchFilters) async throws -> [Pavilion] {
        try await MockNetwork.roundTrip(settings)
        if settings.emptyData { return [] }
        return MockCatalog.pavilions.filter { p in
            (filters.axes.isEmpty || filters.axes.contains(p.axis))
                && (!filters.lowCrowdOnly || p.live.crowd == .low)
                && (filters.maxDistanceMeters == nil || (p.distanceMeters ?? .max) <= filters.maxDistanceMeters!)
        }
    }

    func pavilion(id: String) async throws -> Pavilion {
        try await MockNetwork.roundTrip(settings)
        guard let p = MockCatalog.pavilion(id) else { throw AppError.notFound }
        return p
    }

    func events() async throws -> [ExpoEvent] {
        try await MockNetwork.roundTrip(settings)
        return settings.emptyData ? [] : MockCatalog.events
    }

    func event(id: String) async throws -> ExpoEvent {
        try await MockNetwork.roundTrip(settings)
        guard let e = MockCatalog.event(id) else { throw AppError.notFound }
        return e
    }

    func search(_ query: String) async throws -> [Pavilion] {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !settings.emptyData else { return [] }
        return MockCatalog.pavilions.filter {
            $0.name.contains(q) || $0.organization.contains(q) || $0.axis.title.contains(q) || $0.experienceType.contains(q)
        }
    }

    func priorityCandidates() async throws -> [PriorityCandidate] {
        try await MockNetwork.roundTrip(settings)
        return MockCatalog.priorityCandidates
    }
}

// MARK: - Plan

final class MockPlanService: PlanService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func generatePlan(_ preferences: PlanPreferences,
                      progress: @escaping @MainActor (PlanGenerationStage) -> Void) async throws -> [PlanOption] {
        for stage in PlanGenerationStage.allCases {
            await progress(stage)
            try await Task.sleep(nanoseconds: UInt64((0.6 + settings.latency * 0.5) * 1_000_000_000))
            try Task.checkCancellation()
        }
        if let error = settings.consumeFailure() { throw error }
        return MockPlans.options
    }

    func currentPlan() async throws -> Plan? {
        try await MockNetwork.roundTrip(settings)
        return store.plan
    }

    func addCandidates() async throws -> [PriorityCandidate] {
        try await MockNetwork.roundTrip(settings)
        return MockCatalog.priorityCandidates
    }

    func adopt(_ option: PlanOption) async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        let plan = MockPlans.plan(from: option)
        store.plan = plan
        return plan
    }

    func add(itemId: String) async throws -> AddToPlanResult {
        try await MockNetwork.roundTrip(settings)
        if store.plan == nil { store.plan = MockPlans.plan(from: MockPlans.moreExperiences) }
        // The AI-education session (17:30) overlaps the pinned workshop window in the demo.
        if itemId == "e-ai-education" {
            return .conflict(PlanConflict(
                title: "تتعارض مع ورشتك المثبتة",
                message: "الجلسة 5:30–6:10 م وخطتك تنتهي 5:30 م. وقت المشي من مختبر الروبوتات إلى جناح صحة الإنسان 11 د.",
                options: [
                    ConflictOption(id: "extend", title: "مدّ الخطة حتى 6:10 م", detail: "تبقى الورشة كما هي · +11 د مشي", isSuggested: true),
                    ConflictOption(id: "replace-last", title: "استبدل آخر محطة (جناح الفضاء)", detail: "نهاية الخطة 6:10 م · تفقد عرض القبة"),
                    ConflictOption(id: "later", title: "احفظها فقط دون إضافتها للخطة", detail: "تظهر في «محفوظة» مع تذكير اختياري"),
                ]))
        }
        return .added(position: 1, time: TimeOfDay(15, 34))
    }

    func resolveConflict(_ conflict: PlanConflict, with option: ConflictOption) async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        guard var plan = store.plan else { throw AppError.notFound }
        store.planBeforeLastChange = plan
        if option.id != "later" {
            if option.id == "replace-last" { plan.steps.removeAll { $0.id == "s7" || $0.id == "s8" } }
            plan.steps.append(PlanStep(id: "added-ai-edu", time: TimeOfDay(17, 30), kind: .experience(placeId: "e-ai-education"),
                                       title: "عرض «الذكاء الاصطناعي والتعليم»", subtitle: "40 د · يتطلب حجزًا خارجيًا",
                                       change: .new(reason: "أضفتِه من تفاصيل الفعالية")))
            plan.endsAt = TimeOfDay(18, 10)
            plan.undoAvailableUntil = Date().addingTimeInterval(600)
            plan.lastChangeDescription = "أُضيف عرض «الذكاء الاصطناعي والتعليم»"
        }
        store.plan = plan
        return plan
    }

    func proposeReplan(_ reason: ReplanReason) async throws -> ReplanProposal {
        try await MockNetwork.roundTrip(settings, extra: 0.6)
        let plan = store.plan ?? MockPlans.plan(from: MockPlans.moreExperiences)
        switch reason {
        case .needBreak: return MockPlans.breakProposal(for: plan)
        default: return MockPlans.lateProposal(for: plan)
        }
    }

    func apply(_ proposal: ReplanProposal) async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        store.planBeforeLastChange = store.plan
        var after = proposal.after
        after.undoAvailableUntil = Date().addingTimeInterval(600)
        after.lastChangeDescription = "اعتمدتِ الخطة المعدّلة"
        store.plan = after
        return after
    }

    func crowdSituation() async throws -> CrowdSituation? {
        try await MockNetwork.roundTrip(settings)
        return store.crowdResolved ? nil : MockPlans.crowdSituation
    }

    func swap(to alternative: CrowdAlternative) async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        let plan = store.plan ?? MockPlans.plan(from: MockPlans.moreExperiences)
        store.planBeforeLastChange = plan
        let after = MockPlans.swapped(plan, with: alternative)
        store.plan = after
        store.crowdResolved = true
        return after
    }

    func postponeCrowded() async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        guard var plan = store.plan else { throw AppError.notFound }
        store.planBeforeLastChange = plan
        if let idx = plan.steps.firstIndex(where: { if case .experience("e-city-2050") = $0.kind { true } else { false } }) {
            var show = plan.steps.remove(at: idx)
            show.time = TimeOfDay(17, 18)
            show.subtitle = "20 د · العرض التالي 5:30 م"
            show.change = .new(reason: "أُجّل بسبب الازدحام")
            plan.steps.removeAll { $0.id == "s8" }
            plan.steps.append(show)
        }
        plan.undoAvailableUntil = Date().addingTimeInterval(600)
        plan.lastChangeDescription = "أجّلتِ المدن الذكية إلى العرض التالي"
        store.plan = plan
        store.crowdResolved = true
        return plan
    }

    func undoLastChange() async throws -> Plan {
        try await MockNetwork.roundTrip(settings)
        guard let previous = store.planBeforeLastChange else { throw AppError.notFound }
        store.plan = previous
        store.planBeforeLastChange = nil
        store.crowdResolved = false
        return previous
    }

    func finishVisit() async throws {
        try await MockNetwork.roundTrip(settings)
        store.plan = nil
    }
}

// MARK: - Map

final class MockMapService: MapService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func booths() async throws -> [Booth] {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        return MockMap.booths
    }

    func landmarks() async throws -> [MapLandmark] { MockMap.landmarks }

    func crowdHotspots() async throws -> [CrowdHotspot] { MockMap.hotspots }

    func currentLocation() async throws -> UserLocation {
        if settings.simulateOffline { return MockMap.lowAccuracyLocation }
        return MockMap.myLocation
    }

    func search(_ query: String, filter: MapFilter) async throws -> [SearchResult] {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        if settings.emptyData { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let techWords = ["تقنية", "تقني", "tech"]
        return MockMap.booths
            .filter { b in
                let matchesQuery: Bool
                if q.isEmpty {
                    matchesQuery = true
                } else if techWords.contains(where: { q.contains($0) }) {
                    matchesQuery = ["A7", "A6", "A5", "A4", "B4", "B3"].contains(b.id)
                } else {
                    matchesQuery = b.name.lowercased().contains(q) || b.id.lowercased() == q
                }
                let matchesCategory = filter.category == .all || filter.category == .pavilions || b.category == filter.category
                let matchesCrowd = filter.crowd.isEmpty || filter.crowd.contains(b.crowd)
                let matchesDistance = filter.maxDistance == nil || b.distanceMeters <= filter.maxDistance!
                return matchesQuery && matchesCategory && matchesCrowd && matchesDistance
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .map { SearchResult(booth: $0, subtitle: $0.codeTitle) }
    }

    func routes(to booth: Booth) async throws -> [Route] {
        try await MockNetwork.roundTrip(settings)
        return MockMap.routes(to: booth)
    }

    func route(to target: NavigationTarget) async throws -> Route {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        switch target {
        case .booth(let b): return MockMap.routes(to: b)[0]
        case .friend(let f): return MockMap.friendRoute(f)
        case .meetingPoint(let m): return MockMap.meetingRoute(m)
        }
    }

    func alternatives(for booth: Booth) async throws -> [BoothAlternative] {
        try await MockNetwork.roundTrip(settings)
        return MockMap.tawalAlternatives.filter { $0.booth.id != booth.id }
    }

    func confirmVisit(boothId: String) async throws -> BoothVisit {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        var visit = store.boothVisits[boothId] ?? BoothVisit(boothId: boothId, arrivedAt: TimeOfDay(21, 45), confirmed: false)
        visit.confirmed = true
        store.boothVisits[boothId] = visit
        if let booth = MockMap.booth(boothId), !store.visits.contains(where: { $0.placeId == boothId }) {
            store.visits.append(JourneyVisit(id: "bv-\(boothId)", placeId: boothId, title: "\(booth.name) · جناح \(booth.id)",
                                             start: visit.arrivedAt, end: visit.arrivedAt.adding(minutes: 10),
                                             confirmation: .confirmed, extrasText: nil, thumbnail: booth.photo))
        }
        return visit
    }

    func saveVisitNote(boothId: String, text: String) async throws -> BoothVisit {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        var visit = store.boothVisits[boothId] ?? BoothVisit(boothId: boothId, arrivedAt: TimeOfDay(21, 45), confirmed: false)
        visit.note = text
        store.boothVisits[boothId] = visit
        let name = MockMap.booth(boothId)?.name ?? boothId
        store.notes.insert(VisitNote(id: "bn-\(boothId)", placeId: boothId, placeName: name, freeText: text), at: 0)
        return visit
    }

    func nextStop() async throws -> Booth? {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        return MockMap.booth(MockMap.nextStopBoothId)
    }
}

// MARK: - Friends

final class MockFriendsService: FriendsService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    private func update(_ id: String, _ change: (inout Friend) -> Void) throws -> Friend {
        guard let idx = store.friends.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        change(&store.friends[idx])
        return store.friends[idx]
    }

    func friends() async throws -> [Friend] {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        return settings.emptyData ? [] : store.friends
    }

    func inviteLink() async throws -> InviteLink {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        return MockMap.myInvite
    }

    func resolveInvite(code: String) async throws -> IncomingInvite {
        try await MockNetwork.roundTrip(settings)
        return IncomingInvite(id: code, from: MockMap.thikra)
    }

    func acceptInvite(_ invite: IncomingInvite) async throws -> Friend {
        try await MockNetwork.roundTrip(settings)
        if !store.friends.contains(where: { $0.id == invite.from.id }) { store.friends.append(invite.from) }
        return invite.from
    }

    func declineInvite(_ invite: IncomingInvite) async throws {
        try await MockNetwork.roundTrip(settings)
    }

    func setShareMode(_ mode: LocationShareMode, with friendId: String) async throws -> Friend {
        try await MockNetwork.roundTrip(settings)
        return try update(friendId) { f in
            f.myShare = mode
            switch mode {
            case .live(let minutes): f.myShareEndsAt = TimeOfDay(21, 41).adding(minutes: minutes)
            case .untilEndOfVisit: f.myShareEndsAt = TimeOfDay(23, 0)
            default: f.myShareEndsAt = nil
            }
        }
    }

    func setBackgroundSharing(_ enabled: Bool, with friendId: String) async throws -> Friend {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        return try update(friendId) { $0.shareInBackground = enabled }
    }

    func setVisibleOnMap(_ visible: Bool, friendId: String) async throws -> Friend {
        try update(friendId) { $0.isVisibleOnMap = visible }
    }

    func stopSharing(with friendId: String) async throws -> Friend {
        try await MockNetwork.roundTrip(settings)
        return try update(friendId) { f in
            f.myShare = .none
            f.myShareEndsAt = nil
            f.shareInBackground = false
        }
    }

    func removeFriend(_ friendId: String) async throws {
        try await MockNetwork.roundTrip(settings)
        store.friends.removeAll { $0.id == friendId }
    }

    func endVisit() async throws {
        try await MockNetwork.roundTrip(settings)
        for i in store.friends.indices where store.friends[i].myShare != .none {
            store.friends[i].myShare = .none
            store.friends[i].myShareEndsAt = nil
        }
    }

    func meetingPoints(with friendId: String) async throws -> [MeetingPoint] {
        try await MockNetwork.roundTrip(settings)
        return MockMap.meetingPoints
    }

    func proposeMeeting(_ point: MeetingPoint, with friendId: String) async throws -> MeetingState {
        try await MockNetwork.roundTrip(settings)
        switch store.meeting {
        case .agreed(let current) where current.id != point.id:
            store.meeting = .pendingEdit(current: current, proposed: point)
        default:
            store.meeting = .waiting(point)
        }
        return store.meeting
    }

    /// Demo: the friend accepts the first proposal shortly after it is sent.
    func meetingStatus(with friendId: String) async throws -> MeetingState {
        try await MockNetwork.roundTrip(settings, extra: 1.2)
        switch store.meeting {
        case .waiting(let p) where settings.friendDeclinesMeeting:
            settings.friendDeclinesMeeting = false
            store.meeting = .declined(p, reason: "«النافورة مزدحمة، نختار مكانًا آخر؟»")
        case .waiting(let p): store.meeting = .agreed(p)
        case .pendingEdit(_, let proposed): store.meeting = .agreed(proposed)
        default: break
        }
        return store.meeting
    }
}

// MARK: - Assistant

final class MockAssistantService: AssistantService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func welcome(context: AssistantContext, userName: String?) async throws -> AssistantReply {
        let name = userName ?? ""
        switch context {
        case .map:
            return AssistantReply(
                message: AssistantMessage(role: .assistant, text: MockAssistant.mapWelcome(name: name)),
                followUps: MockAssistant.mapPrompts)
        default:
            return AssistantReply(
                message: AssistantMessage(role: .assistant, text: MockAssistant.planWelcome(name: name)),
                followUps: MockAssistant.planPrompts)
        }
    }

    func send(_ text: String, context: AssistantContext) async throws -> AssistantReply {
        try await MockNetwork.roundTrip(settings, extra: 1.0)
        return MockAssistant.reply(to: text, context: context)
    }
}

// MARK: - Journey

final class MockJourneyService: JourneyService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func visits() async throws -> [JourneyVisit] {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        return settings.emptyData ? [] : store.visits
    }

    func notes() async throws -> [VisitNote] {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        return settings.emptyData ? [] : store.notes
    }

    func saved() async throws -> [SavedPlace] {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        return settings.emptyData ? [] : store.saved
    }

    func followUps() async throws -> [FollowUpItem] {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        return settings.emptyData ? [] : store.followUps
    }

    /// Notes are always saved locally first (offline-friendly); when the demo is offline they are queued.
    func saveNote(_ note: VisitNote) async throws -> VisitNote {
        var saved = note
        saved.updatedAt = Date()
        saved.isPendingSync = settings.simulateOffline
        if let idx = store.notes.firstIndex(where: { $0.id == note.id }) {
            store.notes[idx] = saved
        } else {
            store.notes.insert(saved, at: 0)
        }
        return saved
    }

    func deleteNote(id: String) async throws {
        store.notes.removeAll { $0.id == id }
    }

    func confirmVisit(placeId: String) async throws {
        try await MockNetwork.roundTrip(settings, extra: -0.3)
        if let idx = store.visits.firstIndex(where: { $0.placeId == placeId }) {
            store.visits[idx].confirmation = .confirmed
            if store.visits[idx].end == nil { store.visits[idx].end = store.visits[idx].start.adding(minutes: 15) }
        } else if let p = MockCatalog.pavilion(placeId) {
            store.visits.append(JourneyVisit(id: "v-\(placeId)", placeId: placeId, title: p.name, start: TimeOfDay(17, 22),
                                             end: TimeOfDay(17, 40), confirmation: .confirmed, extrasText: nil, thumbnail: p.photo))
        }
    }

    func toggleSaved(placeId: String) async throws -> Bool {
        if let idx = store.saved.firstIndex(where: { $0.id == placeId }) {
            store.saved.remove(at: idx)
            return false
        }
        if let p = MockCatalog.pavilion(placeId) {
            store.saved.insert(SavedPlace(id: p.id, title: p.name, subtitle: "\(p.axis.title) · \(p.experienceType)", photo: p.photo), at: 0)
        }
        return true
    }

    func scan(code: String) async throws -> ScannedPlace {
        try await MockNetwork.roundTrip(settings)
        let key = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard let id = MockJourney.pavilionCodes[key] ?? (key.isEmpty ? nil : (key == "QR-DEMO" ? "p9-digital-arts" : nil)),
              let p = MockCatalog.pavilion(id) else {
            throw AppError.validation(["code": "لم نتعرف على هذا الرمز. تأكد من الرمز المكتوب تحت QR."])
        }
        if !store.visits.contains(where: { $0.placeId == id }) {
            store.visits.append(JourneyVisit(id: "scan-\(id)", placeId: id, title: p.name, start: TimeOfDay(17, 22), end: nil,
                                             confirmation: .scannedOnly(TimeOfDay(17, 22)), extrasText: nil, thumbnail: p.photo))
        }
        return ScannedPlace(placeId: id, name: p.name, subtitle: "\(p.axis.title) · \(p.experienceType)", photo: p.photo)
    }

    func summary() async throws -> JourneySummary {
        try await MockNetwork.roundTrip(settings, extra: 1.0)
        return MockJourney.summary
    }

    func setFollowUp(id: String, done: Bool) async throws {
        if let i = store.followUps.firstIndex(where: { $0.id == id }) { store.followUps[i].isDone = done }
    }

    func saveSummary(_ summary: JourneySummary) async throws {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        store.summaries.removeAll { $0.title == summary.title }
        store.summaries.insert(summary, at: 0)
    }

    func savedSummaries() async throws -> [JourneySummary] { store.summaries }

    func guestDataSummary() async -> GuestDataSummary {
        GuestDataSummary(hasPlan: store.plan != nil, hasPreferences: true, notesCount: store.notes.count,
                         photosCount: store.notes.flatMap(\.attachments).filter { $0.kind == .photo }.count,
                         savedPavilionsCount: store.saved.count)
    }
}

// MARK: - Profile

final class MockProfileService: ProfileService {
    private let store: MockStore
    private let settings: DemoSettings

    init(store: MockStore, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    func profile() async throws -> ProfessionalProfile? {
        try await MockNetwork.roundTrip(settings, extra: -0.2)
        return store.profile
    }

    func save(_ profile: ProfessionalProfile) async throws -> ProfessionalProfile {
        try await MockNetwork.roundTrip(settings)
        store.profile = profile
        return profile
    }

    func currentShareLink() async throws -> ProfileShareLink? { store.shareLink }

    func createShareLink(fields: Set<ProfileField>, validity: LinkValidity) async throws -> ProfileShareLink {
        try await MockNetwork.roundTrip(settings)
        let until: String
        switch validity {
        case .oneHour: until = "صالح حتى اليوم 5:40 م"
        case .today: until = "صالح حتى اليوم 11:59 م"
        case .oneDay: until = "صالح حتى غد 4:40 م"
        case .oneWeek: until = "صالح حتى 8 أكتوبر 4:40 م"
        }
        let link = ProfileShareLink(url: MockProfile.shareLink.url, fields: fields, validity: validity,
                                    validUntilText: "\(until) · \(fields.count) حقول", isActive: true)
        store.shareLink = link
        return link
    }

    func disableShareLink() async throws {
        try await MockNetwork.roundTrip(settings)
        store.shareLink?.isActive = false
    }
}

// MARK: - Sync

/// Simulated offline queue (17.04 / 17.06).
final class MockSyncService: SyncService {
    private let settings: DemoSettings
    private let store: MockStore?
    private var queued = 0
    private(set) var lastSyncedText = "آخر مزامنة 9:12 ص"

    init(store: MockStore? = nil, settings: DemoSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    /// Notes saved while offline plus anything explicitly queued.
    var pendingChanges: Int { queued + (store?.notes.filter(\.isPendingSync).count ?? 0) }

    func enqueue(_ description: String) {
        queued += 1
    }

    func syncNow() async throws -> Int {
        try await MockNetwork.roundTrip(settings, extra: 0.6)
        let synced = pendingChanges
        queued = 0
        if let store {
            for i in store.notes.indices { store.notes[i].isPendingSync = false }
        }
        lastSyncedText = "تمت المزامنة الآن"
        return synced
    }
}
