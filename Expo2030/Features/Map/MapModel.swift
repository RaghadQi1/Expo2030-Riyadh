import SwiftUI

/// Camera over the hall map: which map point sits at the visual centre, and the zoom factor.
struct MapCamera: Equatable {
    var center: MapPoint
    var zoom: CGFloat

    static let minZoom: CGFloat = 0.55
    static let maxZoom: CGFloat = 3.2
    /// Approximate metres per map point (PwC: 180 m ≈ 255 pt of corridor).
    static let metersPerPoint: Double = 0.7
}

/// What the bottom of «خريطتي» shows. Exactly one panel is visible at a time (Figma never stacks them).
enum MapPanel: Equatable {
    case none                                                    // 1.0 map + tab bar
    case locationPeek                                            // 1.1 «أنتِ الآن»
    case filterResults([SearchResult])                           // 1.5
    case categoryPeek(PlaceCategory)                             // 1.6
    case booth(Booth, expanded: Bool)                            // 2.1 / 2.2 / 3.1 (crowded)
    case alternatives(Booth, [BoothAlternative])                 // 3.2
    case replaceReview(from: Booth, to: Booth)                   // 3.3
    case routeOptions(NavigationTarget, [Route], selected: RouteKind) // 2.3 / 2.5 / 3.4 / 3.10
    case navigating                                              // 2.6 – 2.11, 5.10, 6.7
    case arrived(Booth)                                          // 3.5 – 3.8, 3.12
    case nextStop(Booth)                                         // 3.9
    case friends                                                 // 4.1
    case friendCard(Friend)                                      // 5.7 / 5.8
    case meetingPicker(editing: Bool)                            // 6.1 / 6.6 / 6.9
    case meetingReview(MeetingPoint)                             // 6.2
    case meetingStatus                                           // 6.3 / 6.5 / 6.10 / 6.11
    case meetingArrived(MeetingPoint)                            // 6.8

    /// Panels that replace the tab bar (Figma hides it for every task sheet).
    var hidesTabBar: Bool { self != .none }
}

/// Full-height / modal sheets presented over the map.
enum MapSheet: Identifiable, Equatable {
    case filter
    case compareRoutes(target: NavigationTarget, routes: [Route], current: RouteKind)
    case note(Booth)
    case invite
    case scanFriend
    case incomingInvite(IncomingInvite)
    case shareMode(Friend)
    case shareSettings(Friend)
    case locationExplainer
    case notificationsExplainer

    var id: String {
        switch self {
        case .filter: "filter"
        case .compareRoutes: "compare"
        case .note(let b): "note-\(b.id)"
        case .invite: "invite"
        case .scanFriend: "scan"
        case .incomingInvite(let i): "incoming-\(i.id)"
        case .shareMode(let f): "share-\(f.id)"
        case .shareSettings(let f): "settings-\(f.id)"
        case .locationExplainer: "location"
        case .notificationsExplainer: "notifications"
        }
    }
}

struct NavigationSession: Equatable {
    var target: NavigationTarget
    var route: Route
    var stepIndex = 0
    var isRerouting = false

    var step: NavigationStep? { route.steps.indices.contains(stepIndex) ? route.steps[stepIndex] : route.steps.last }
    var isLastStep: Bool { stepIndex >= route.steps.count - 1 }
}

/// State of «خريطتي». All data comes from `MapService` / `FriendsService`; nothing here talks to the network.
@MainActor
@Observable
final class MapModel {
    // Data
    var booths: [Booth] = []
    var landmarks: [MapLandmark] = []
    var hotspots: [CrowdHotspot] = []
    var location: UserLocation?
    var friends: [Friend] = []
    var loadError: AppError?
    var isLoaded = false

    // Camera
    var camera = MapCamera(center: MapPoint(x: HallMap.width / 2, y: 400), zoom: 1.1)
    var isFollowing = true
    var isFlat = false
    var showScaleBar = false

    // Browsing
    var category: PlaceCategory = .all
    var filter = MapFilter()
    var isSearching = false
    var panel: MapPanel = .none
    var sheet: MapSheet?

    // Route / navigation
    var previewRoutes: [Route] = []
    var navigation: NavigationSession?
    var visits: [String: BoothVisit] = [:]
    /// Arrival time per booth, taken from the route that brought the visitor there.
    var arrivalTimes: [String: TimeOfDay] = [:]
    /// Booths postponed by the visitor («سنحفظ توال في لاحقًا»).
    var later: [Booth] = []
    var lastAlternatives: [BoothAlternative] = []

    /// Hall-wide crowd level for «ازدحام المعرض الآن». Derived from the crowd feed until the API returns
    /// an explicit hall level (see API_CONTRACT.md `GET /map/crowd`).
    var hallCrowd: CrowdLevel {
        if hotspots.isEmpty { return .unknown }
        return hotspots.contains { $0.level == .high } ? .medium : .low
    }

    // Friends & meeting
    var meeting: MeetingState = .none
    var meetingPoints: [MeetingPoint] = []
    var activeFriendId: String?
    var meetingPreviewRoute: Route?

    // Permissions (4.10 – 4.17)
    let permissions = LocationPermissionModel()

    private var services: AppServices?
    private var navigationTask: Task<Void, Never>?

    func attach(_ services: AppServices) { self.services = services }

    var isMock: Bool { services?.environment.isMock ?? true }

    /// Clock used for sharing countdowns. The demo runs at the time drawn in Figma (9:43 م);
    /// live mode uses the device clock.
    var now: TimeOfDay {
        if isMock { return TimeOfDay(21, 43) }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return TimeOfDay(c.hour ?? 0, c.minute ?? 0)
    }
    var demo: DemoSettings { services?.demo ?? .shared }

    // MARK: Loading

    func load() async {
        guard let services else { return }
        loadError = nil
        do {
            async let b = services.map.booths()
            async let l = services.map.landmarks()
            async let h = services.map.crowdHotspots()
            async let f = services.friends.friends()
            booths = try await b
            landmarks = try await l
            hotspots = try await h
            friends = try await f
            await refreshLocation()
            isLoaded = true
        } catch let e as AppError {
            loadError = e
        } catch {
            loadError = .unknown
        }
    }

    func refreshLocation() async {
        guard let services else { return }
        permissions.refresh()
        guard permissions.canShowLocation else { location = nil; return }
        var loc = try? await services.map.currentLocation()
        if permissions.isApproximate, var l = loc {
            l.accuracy = .low
            l.headingDegrees = nil
            l.areaDetail = "الاتجاه غير متاح بدقة الآن"
            loc = l
        }
        location = loc
        if isFollowing, let loc { camera.center = loc.point }
    }

    // MARK: Camera

    func recenter() {
        isFollowing = true
        if panel == .none, navigation == nil { panel = .locationPeek }
        if let p = navigation?.step?.position ?? location?.point {
            withAnimation(.easeInOut(duration: 0.35)) { camera.center = p }
        }
    }

    func zoom(by factor: CGFloat) {
        withAnimation(.easeInOut(duration: 0.25)) {
            camera.zoom = min(MapCamera.maxZoom, max(MapCamera.minZoom, camera.zoom * factor))
        }
        flashScaleBar()
    }

    func flashScaleBar() {
        showScaleBar = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            showScaleBar = false
        }
    }

    func focus(on point: MapPoint, zoom: CGFloat? = nil) {
        isFollowing = false
        withAnimation(.easeInOut(duration: 0.35)) {
            camera.center = point
            if let zoom { camera.zoom = zoom }
        }
    }

    /// «موقعك على بعد ٣٢٠ م شمالًا» while exploring (1.7).
    var distanceToMeText: String? {
        guard let me = location?.point, !isFollowing else { return nil }
        let dx = me.x - camera.center.x
        let dy = me.y - camera.center.y
        let meters = Int((hypot(dx, dy) * MapCamera.metersPerPoint / 10).rounded()) * 10
        guard meters >= 20 else { return nil }
        let dir: String
        if abs(dy) >= abs(dx) { dir = dy < 0 ? "شمالًا" : "جنوبًا" } else { dir = dx < 0 ? "غربًا" : "شرقًا" }
        return "موقعك على بعد \(ArabicDigits.format(meters)) م \(dir)"
    }

    // MARK: Booths

    func booth(at point: MapPoint) -> Booth? {
        booths.first { $0.frame.contains(point) }
    }

    func select(_ booth: Booth) {
        isSearching = false
        panel = .booth(booth, expanded: false)
        focus(on: MapPoint(x: booth.frame.center.x, y: booth.frame.center.y + 60))
    }

    func boothIds(in category: PlaceCategory) -> Set<String> {
        guard category != .all else { return [] }
        return Set(booths.filter { category == .pavilions || $0.category == category }.map(\.id))
    }

    func setCategory(_ c: PlaceCategory) {
        category = c
        panel = c == .all ? .none : .categoryPeek(c)
    }

    func applyFilter() async {
        guard let services else { return }
        do {
            let results = try await services.map.search("", filter: filter)
            panel = .filterResults(results)
        } catch {
            panel = .filterResults([])
        }
    }

    func clearFilter() {
        filter = MapFilter()
        panel = .none
    }

    // MARK: Routes

    func showRoutes(to booth: Booth) async throws {
        guard let services else { return }
        if booth.crowd == .high {
            // 3.2: offer quieter alternatives before routing into a crowded booth.
            let alts = try await services.map.alternatives(for: booth)
            if !alts.isEmpty {
                lastAlternatives = alts
                panel = .alternatives(booth, alts)
                return
            }
        }
        let routes = try await services.map.routes(to: booth)
        previewRoutes = routes
        panel = .routeOptions(.booth(booth), routes, selected: routes.first?.kind ?? .fastest)
        isFollowing = false
        withAnimation { camera.center = MapPoint(x: (booth.frame.center.x + (location?.point.x ?? 335)) / 2, y: booth.frame.center.y - 20) }
    }

    /// 3.10 «متابعة الوجهة الأصلية» — skip the alternatives and route to the crowded booth anyway.
    func routeIgnoringCrowd(to booth: Booth) async throws {
        guard let services else { return }
        let routes = try await services.map.routes(to: booth)
        previewRoutes = [routes[0]]
        panel = .routeOptions(.booth(booth), [routes[0]], selected: routes[0].kind)
    }

    func selectRoute(_ kind: RouteKind) {
        if case .routeOptions(let target, let routes, _) = panel {
            panel = .routeOptions(target, routes, selected: kind)
        }
    }

    func replace(_ from: Booth, with to: Booth) async throws {
        later.removeAll { $0.id == from.id }
        later.append(from)
        guard let services else { return }
        let routes = try await services.map.routes(to: to)
        // 3.4 shows one combined option: «الأسرع والأهدأ».
        let best = routes.min { $0.minutes < $1.minutes } ?? routes[0]
        previewRoutes = [best]
        panel = .routeOptions(.booth(to), [best], selected: best.kind)
    }

    func startNavigation(target: NavigationTarget, route: Route) {
        navigation = NavigationSession(target: target, route: route)
        previewRoutes = []
        panel = .navigating
        isFollowing = true
        if let p = route.steps.first?.position {
            withAnimation(.easeInOut(duration: 0.35)) { camera.center = p; camera.zoom = max(camera.zoom, 1.3) }
        }
        runDemoProgress()
    }

    func startNavigation(to target: NavigationTarget) async throws {
        guard let services else { return }
        let route = try await services.map.route(to: target)
        startNavigation(target: target, route: route)
    }

    /// Moves to the next instruction. On a real device this is driven by indoor positioning; in the demo it
    /// advances on a timer (and when the instruction card is tapped).
    func advanceStep() {
        guard var nav = navigation, !nav.isRerouting else { return }
        if nav.isLastStep {
            arrive()
            return
        }
        nav.stepIndex += 1
        navigation = nav
        if isFollowing, let p = nav.step?.position {
            withAnimation(.easeInOut(duration: 0.5)) { camera.center = p }
        }
    }

    private func runDemoProgress() {
        navigationTask?.cancel()
        guard isMock else { return }
        navigationTask = Task { @MainActor [weak self] in
            var missedTurnShown = false
            while let self, self.navigation != nil, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, self.navigation != nil else { return }
                if self.demo.simulateMissedTurn, !missedTurnShown, self.navigation?.stepIndex == 1 {
                    missedTurnShown = true
                    self.demo.simulateMissedTurn = false
                    self.navigation?.isRerouting = true
                    try? await Task.sleep(for: .seconds(3))
                    self.navigation?.isRerouting = false
                    continue
                }
                self.advanceStep()
            }
        }
    }

    func endNavigation() {
        navigationTask?.cancel()
        navigation = nil
        panel = .none
        recenter()
    }

    private func arrive() {
        navigationTask?.cancel()
        guard let nav = navigation else { return }
        navigation = nil
        switch nav.target {
        case .booth(let b):
            arrivalTimes[b.id] = nav.route.arrival
            panel = .arrived(b)
            focus(on: MapPoint(x: b.frame.center.x + 60, y: b.frame.center.y + 120))
        case .meetingPoint(let m):
            panel = .meetingArrived(m)
        case .friend(let f):
            panel = .friendCard(f)
        }
    }

    // MARK: Visits

    func confirmVisit(_ booth: Booth) async throws {
        guard let services else { return }
        visits[booth.id] = try await services.map.confirmVisit(boothId: booth.id)
    }

    func saveNote(_ booth: Booth, text: String) async throws {
        guard let services else { return }
        let visit = try await services.map.saveVisitNote(boothId: booth.id, text: text)
        var merged = visits[booth.id] ?? visit
        merged.note = visit.note
        visits[booth.id] = merged
    }

    func showNextStop() async {
        guard let services else { return }
        if let next = try? await services.map.nextStop() {
            panel = .nextStop(next)
            if let routes = try? await services.map.routes(to: next) { previewRoutes = [routes[0]] }
            focus(on: MapPoint(x: next.frame.center.x + 80, y: next.frame.center.y - 60))
        }
    }

    // MARK: Friends

    func friend(_ id: String) -> Friend? { friends.first { $0.id == id } }

    func reloadFriends() async {
        guard let services else { return }
        if let list = try? await services.friends.friends() { friends = list }
    }

    func upsert(_ friend: Friend) {
        if let i = friends.firstIndex(where: { $0.id == friend.id }) { friends[i] = friend } else { friends.append(friend) }
        if case .friendCard(let f) = panel, f.id == friend.id { panel = .friendCard(friend) }
    }

    /// Friend shown on the map (5.6): shares with me, visible, and has a location.
    var visibleFriends: [Friend] {
        friends.filter { $0.sharesWithMe && $0.isVisibleOnMap && $0.location != nil }
    }

    /// «تشاركين موقعك مع ذكرى، باقي ٥٨ د» (5.6) — the first friend I'm actively sharing with.
    var mySharingFriend: Friend? { friends.first { $0.myShare != .none && $0.myShare != .staticOnce } }

    // MARK: Meeting

    var meetingFriend: Friend? {
        friends.first { $0.id == activeFriendId } ?? friends.first { $0.sharesWithMe } ?? friends.first
    }

    func openMeetingPicker(editing: Bool = false) async {
        guard let services, let friend = meetingFriend else {
            panel = .friends
            return
        }
        activeFriendId = friend.id
        if meetingPoints.isEmpty {
            meetingPoints = (try? await services.friends.meetingPoints(with: friend.id)) ?? []
        }
        panel = .meetingPicker(editing: editing)
    }

    /// 6.2 «مراجعة الاقتراح»: shows both walking lines before anything is sent.
    func review(_ point: MeetingPoint) async {
        meetingPreviewRoute = nil
        panel = .meetingReview(point)
        focus(on: point.point)
        meetingPreviewRoute = try? await services?.map.route(to: .meetingPoint(point))
    }

    func propose(_ point: MeetingPoint) async throws {
        guard let services, let friend = meetingFriend else { return }
        meeting = try await services.friends.proposeMeeting(point, with: friend.id)
        panel = .meetingStatus
        // Wait for the friend's answer (the real API would push it; the demo polls once).
        let status = try await services.friends.meetingStatus(with: friend.id)
        meeting = status
        if case .declined = status { panel = .meetingPicker(editing: false) }
    }

    var agreedPoint: MeetingPoint? {
        switch meeting {
        case .agreed(let p): p
        case .pendingEdit(let current, _): current
        default: nil
        }
    }

    var proposedPoint: MeetingPoint? {
        switch meeting {
        case .waiting(let p), .declined(let p, _): p
        case .pendingEdit(_, let p): p
        default: nil
        }
    }

    // MARK: Requests from other tabs / the assistant

    func handle(_ request: MapRequest) async {
        if !isLoaded { await load() }
        switch request {
        case .showBooth(let id):
            if let b = booths.first(where: { $0.id == id }) { select(b) }
        case .navigateToBooth(let id):
            if let b = booths.first(where: { $0.id == id }) { try? await showRoutes(to: b) }
        case .meetingPoint:
            await openMeetingPicker()
        case .friends:
            panel = .friends
        case .scanFriend:
            sheet = .scanFriend
        }
    }
}

extension UserLocation {
    func with(point: MapPoint) -> UserLocation {
        var copy = self
        copy.point = point
        return copy
    }
}
