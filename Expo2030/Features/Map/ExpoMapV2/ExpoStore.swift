import SwiftUI
import Combine

@MainActor
final class ExpoStore: ObservableObject {
    @Published private(set) var dataset: ExpoDataset
    @Published private(set) var backendConnected = false
    @Published private(set) var backendLoading = false
    @Published private(set) var crowdLoading = false
    @Published private(set) var crowdReady = false
    @Published private(set) var crowdFailureReason: String? = nil
    private var crowdFactors: [String: Double] = [:]
    private var crowdRequestVersion = 0

    // The demo sends real requests to the synthetic model at two fixed times.
    // It never changes the device clock or the application's local dataset.
    @Published private(set) var demoEnabled = false
    @Published private(set) var demoLoading = false
    @Published private(set) var demoHour = 11
    private var extraDemoFactors: [Int: [String: Double]] = [:]
    @Published private(set) var demoError: String? = nil
    private var demoRequestVersion = 0
    private var morningFactors: [String: Double] = [:]
    private var eveningFactors: [String: Double] = [:]

    struct CrowdDemoComparison {
        let morning: RoutePlan
        let evening: RoutePlan
        let routeChanged: Bool
    }

    var demoComparison: CrowdDemoComparison? {
        guard demoEnabled, !demoLoading, demoError == nil,
              let destination = selectedSpaceID,
              !morningFactors.isEmpty, !eveningFactors.isEmpty,
              let morning = indoor.shortestPath(from: position, to: "space/\(destination)", timeFactors: morningFactors),
              let evening = indoor.shortestPath(from: position, to: "space/\(destination)", timeFactors: eveningFactors) else {
            return nil
        }
        // Geometry comparison intentionally ignores seconds (travel costs).
        return CrowdDemoComparison(morning: morning, evening: evening,
                                   routeChanged: morning.takesDifferentGeometry(than: evening))
    }
    /// Per-route forecast from the very same edge times used by Dijkstra.
    /// Works for normal navigation AND the optional time demonstration.
    func crowdOnRoute(_ plan: RoutePlan?) -> RouteCrowdSummary? {
        guard crowdReady, let plan else { return nil }
        return RouteCrowdSummary(route: plan,
                                 walkingMetresPerMinute: indoor.walkingMetresPerMinute)
    }
    var selectedRouteCrowd: RouteCrowdSummary? { crowdOnRoute(route) }
    /// Floor-wide crowd conditions never imply that the selected route is itself crowded.
    var routeDecisionExplanation: String {
        guard crowdReady else {
            return "لا توجد توقعات زحمة من الخادم؛ الوقت الحالي محسوب بسرعة المشي العادية فقط."
        }
        if distinctRouteOptions, let quickest = fastestRoute,
           let shortest = shortestRoute {
            let saved = max(0, shortest.seconds - quickest.seconds)
            return "الأزرق يوفر \(Int(saved.rounded())) ثانية وفق التوقعات. قد يمر بممر مزدحم، لكنه الأقل في وقت الوصول الكلي. الأحمر أقصر مسافة، وقد يكون أبطأ."
        }
        return "أقصر مسافة هي الأسرع أيضًا في ظروف الزحمة الحالية؛ وجود زحمة لا يفرض تغيير الطريق إذا لم يوجد بديل أسرع."
    }

    // One indicator per displayed indoor floor; based on predicted delay for
    // *all physically walkable segments*, not only the selected destination.
    var crowdForecast: CrowdForecastSummary? {
        guard mode == .indoor, crowdReady else { return nil }
        return CrowdForecastSummary.calculate(graph: indoor, floor: floor, factors: crowdFactors)
    }
    // Expose corridor forecast for the indoor heat map in normal AND demo modes.
    func crowdFactor(for edge: GraphEdge) -> Double? {
        guard crowdReady, !edge.isVertical else { return nil }
        return crowdFactors[edge.key]
    }
    /// Find a booth whose *actual drawn path* changes between predictions.
    /// Never claim a reroute just because overlapping graph-node IDs changed.
    var demonstrableDestination: String? {
        guard demoEnabled, !demoLoading,
              !morningFactors.isEmpty, !eveningFactors.isEmpty else { return nil }
        for id in ["B014", "B013", "B015", "B016"] {
            guard let am = indoor.shortestPath(from: position, to: "space/\(id)", timeFactors: morningFactors),
                  let pm = indoor.shortestPath(from: position, to: "space/\(id)", timeFactors: eveningFactors) else { continue }
            if am.takesDifferentGeometry(than: pm) { return id }
        }
        return nil
    }
    func showDemonstrableRoute() {
        guard !navigating, let id = demonstrableDestination else { return }
        selectSpace(id)
        selectDemoHour(demoHour)
    }
    var crowdStatusText: String {
        if demoEnabled && demoLoading { return "جاري مقارنة الزحمة المتوقعة…" }
        if demoEnabled && demoError != nil { return "تعذّر جلب توقعات الزحمة" }
        if demoEnabled && crowdReady { return "عرض اختبار · يوم الأحد \(demoHour):00 · توقع محاكاة" }
        if crowdLoading { return "جاري توقع الزحمة وحساب أسرع طريق…" }
        if crowdReady { return "أسرع طريق حسب الزحمة المتوقعة · توقع تقديري" }
        return "الزحمة غير متاحة · الطريق دون ازدحام"
    }
    private(set) var outdoor: NavigationGraph
    private(set) var indoor: NavigationGraph
    @Published private(set) var selectedGateID: String? = nil
    @Published private(set) var gateDistances: [String: Double] = [:]
    @Published var position: MapPosition
    @Published var mode: MapZone = .outdoor
    @Published var floor: Int = 1
    @Published var selectedLocationID: String? = nil
    @Published var selectedEventID: String? = nil
    @Published var selectedSpaceID: String? = nil
    enum RoutePreference { case fastest, shortest }
    @Published var routePreference: RoutePreference = .fastest
    @Published private(set) var fastestRoute: RoutePlan? = nil
    @Published private(set) var shortestRoute: RoutePlan? = nil
    var distinctRouteOptions: Bool {
        guard crowdReady, let fast = fastestRoute, let short = shortestRoute else { return false }
        return fast.takesDifferentGeometry(than: short) && short.seconds > fast.seconds + 0.01
    }
    @Published var route: RoutePlan? = nil
    @Published var plannedIndoorRoute: RoutePlan? = nil
    @Published var routeVisible = false
    @Published var navigating = false
    @Published var elapsed = 0.0
    @Published var walkingMultiplier = 1.0
    @Published var placementMode = false
    @Published var cameraRevision = 0
    @Published var toast: String? = nil
    private var lastTick: Date?

    init() throws {
        let loaded = try ExpoDataset.load()
        let errors = loaded.validate()
        guard errors.isEmpty else {
            throw ExpoDataError.inconsistent(errors.joined(separator: ", "))
        }
        let outdoorGraph = ExpoGraphs.outdoor(loaded)
        let indoorGraph = ExpoGraphs.indoor(loaded)
        dataset = loaded
        outdoor = outdoorGraph
        indoor = indoorGraph
        position = outdoorGraph.nodes["location/gate3"]!.position
        // Optional gate filtering stays available in the outdoor map;
        // never block launch with a mandatory gate selection screen.
        selectedGateID = "gate3"
        gateDistances = GateDiscovery.distances(gateID: "gate3", data: loaded, graph: outdoorGraph)
    }
    /// Fetch the latest records from REST. Local JSON stays usable if the server is offline.
    func refreshFromBackend() async {
        guard !backendLoading else { return }
        backendLoading = true
        defer { backendLoading = false }
        do {
            let incoming = try await ExpoAPI().loadDataset()
            // Geometry, IDs, gate and indoor positions stay aligned to the bundled
            // navigation network; the API may only change descriptive records.
            guard Set(incoming.map.locations.map(\.id)) == Set(dataset.map.locations.map(\.id)),
                  Set(incoming.booths.map(\.id)) == Set(dataset.booths.map(\.id)),
                  Set(incoming.events.map(\.id)) == Set(dataset.events.map(\.id)) else {
                throw ExpoDataError.inconsistent("معرفات البيانات لا تطابق نسخة الخريطة")
            }
            dataset = incoming
            // All graph builders use the same data snapshot. Preserve current indoor
            // navigation; a refresh updates event details without interrupting walking.
            if mode == .outdoor, let gate = selectedGateID {
                gateDistances = GateDiscovery.distances(gateID: gate, data: dataset, graph: outdoor)
            }
            backendConnected = true
        } catch {
            backendConnected = false
            // On a failed request preserve the last good snapshot, which initially
            // is the packaged JSON fallback. Do not reset a visitor's selection.
        }
    }

    var selectedLocation: ExpoLocation? {
        dataset.map.locations.first { $0.id == selectedLocationID }
    }
    var selectedEvent: ExpoNavEvent? { dataset.events.first { $0.id == selectedEventID } }
    var selectedSpace: IndoorSpace? { dataset.indoor.spaces.first { $0.id == selectedSpaceID } }
    var selectedTitle: String? {
        if mode == .indoor {
            if let event = selectedEvent { return event.title_ar }
            if let space = selectedSpace {
                return dataset.booths.first(where: { $0.id == space.id })?.name_ar ?? Self.serviceNames[space.id] ?? space.id
            }
        }
        return selectedEvent?.title_ar ?? selectedLocation?.name
    }
    var selectedDescription: String {
        if mode == .indoor {
            if let event = selectedEvent { return event.description_ar }
            if let booth = dataset.booths.first(where: { $0.id == selectedSpaceID }) { return booth.description_ar }
            return "خدمة داخل جناح السعودية — موقع تقديري."
        }
        return selectedEvent?.description_ar ?? selectedLocation?.desc ?? ""
    }
    static let serviceNames: [String:String] = [
        "stage":"منصة الفعاليات", "cafe":"المقهى", "prayer":"المصلى",
        "wc":"دورات المياه", "lift1":"المصعد", "lift2":"المصعد", "exit":"الخروج"
    ]
    var activeGraph: NavigationGraph { mode == .outdoor ? outdoor : indoor }

    private func replanIndoorSelection() {
        guard mode == .indoor, !navigating else { return }
        guard let id = selectedSpaceID else {
            fastestRoute = nil; shortestRoute = nil; route = nil
            return
        }
        // Evaluate BOTH paths under exactly the same congestion forecast.
        let factors = crowdReady ? crowdFactors : [:]
        fastestRoute = indoor.shortestPath(from: position, to: "space/\(id)",
                                           timeFactors: factors)
        if let baseline = indoor.shortestPath(from: position, to: "space/\(id)") {
            shortestRoute = indoor.predictedTravelTime(for: baseline, timeFactors: factors)
        } else { shortestRoute = nil }
        if !distinctRouteOptions { routePreference = .fastest }
        route = routePreference == .shortest && distinctRouteOptions ? shortestRoute : fastestRoute
        elapsed = 0
        if routeVisible { cameraRevision += 1 }
    }
    func chooseRoute(_ preference: RoutePreference) {
        guard !navigating, mode == .indoor else { return }
        if preference == .shortest && !distinctRouteOptions { return }
        routePreference = preference
        route = preference == .shortest ? shortestRoute : fastestRoute
        routeVisible = route != nil
        cameraRevision += 1
    }

    /// Fetch corridor-by-corridor Random Forest estimates from FastAPI.
    /// Dijkstra remains local; the server never chooses or draws the route.
    func refreshCrowdPrediction() async {
        guard mode == .indoor, !navigating, !crowdLoading, !demoEnabled else { return }
        crowdRequestVersion += 1
        let requestVersion = crowdRequestVersion
        crowdLoading = true
        crowdFailureReason = nil
        do {
            let predictions = try await ExpoAPI().loadIndoorCrowd(graph: indoor)
            guard requestVersion == crowdRequestVersion, mode == .indoor else { return }
            crowdFactors = predictions
            crowdFailureReason = nil
            crowdReady = true
            crowdLoading = false
            replanIndoorSelection()
        } catch {
            guard requestVersion == crowdRequestVersion, mode == .indoor else { return }
            crowdFailureReason = error.localizedDescription
            print("Crowd prediction failed: \(error)")
            crowdFactors = [:]
            crowdReady = false
            crowdLoading = false
            replanIndoorSelection()
        }
    }
    /// Fetches two complete sets of corridor predictions from the same real API.
    /// Uses Sunday so that the comparison changes only the hour, not the day.
    func openCrowdDemo() async {
        guard mode == .indoor, !navigating else { return }
        if selectedSpaceID == nil {
            // B014 is a known, reachable first-floor booth: useful demo default.
            selectSpace("B014")
        }
        demoRequestVersion += 1
        let version = demoRequestVersion
        crowdRequestVersion += 1       // Ignore a previous live prediction response.
        crowdLoading = false           // The canceled live request must not block walking.
        demoEnabled = true
        demoLoading = true
        demoError = nil
        demoHour = 11
        morningFactors = [:]
        eveningFactors = [:]
        extraDemoFactors = [:]
        crowdReady = false
        do {
            let api = try ExpoAPI()
            let morning = try await api.loadIndoorCrowd(graph: indoor, overrideHour: 11, overrideDay: 0)
            let evening = try await api.loadIndoorCrowd(graph: indoor, overrideHour: 17, overrideDay: 0)
            guard version == demoRequestVersion, demoEnabled, mode == .indoor else { return }
            morningFactors = morning
            eveningFactors = evening
            demoLoading = false
            selectDemoHour(11)
        } catch {
            guard version == demoRequestVersion, demoEnabled, mode == .indoor else { return }
            demoLoading = false
            demoError = "تعذر الاتصال بنموذج إكسبو v9/v10 على المنفذ 8001."
            crowdFactors = [:]
            crowdReady = false
            replanIndoorSelection()
        }
    }

    /// One explicit hackathon preview: predictions for Sunday at 18:00.
    /// All factors come from the trained backend model; normal mode remains device-time based.
    func toggleHackathonCrowdPreview() async {
        guard mode == .indoor, !navigating, !demoLoading else { return }
        if demoEnabled {
            closeCrowdDemo()
            return
        }
        demoRequestVersion += 1
        let version = demoRequestVersion
        crowdRequestVersion += 1
        crowdLoading = false
        demoEnabled = true
        demoLoading = true
        demoError = nil
        demoHour = 18
        crowdReady = false
        do {
            let factors = try await ExpoAPI().loadIndoorCrowd(graph: indoor, overrideHour: 18, overrideDay: 0)
            guard version == demoRequestVersion, demoEnabled, mode == .indoor else { return }
            crowdFactors = factors
            crowdFailureReason = nil
            crowdReady = true
            demoLoading = false
            routePreference = .fastest
            replanIndoorSelection()
        } catch {
            guard version == demoRequestVersion, mode == .indoor else { return }
            demoLoading = false
            crowdFailureReason = error.localizedDescription
            print("Hackathon crowd prediction failed: \(error)")
            demoError = "تعذر جلب توقع الساعة 6 مساءً"
            // Fall back to device-time predictions; never show hardcoded congestion.
            closeCrowdDemo()
            toast = "تعذر جلب توقع الساعة 6 مساءً من الخادم"
        }
    }

    func selectDemoHour(_ hour: Int) {
        guard demoEnabled, !demoLoading, demoError == nil, !navigating,
              hour == 11 || hour == 17 else { return }
        let factors = hour == 11 ? morningFactors : eveningFactors
        guard !factors.isEmpty else { return }
        demoHour = hour
        crowdFactors = factors
        crowdReady = true
        routePreference = .fastest
        replanIndoorSelection()
        if route != nil {
            routeVisible = true
            cameraRevision += 1
        }
    }

    /// Additional pitch times are requested on demand from the very same model.
    /// No fabricated congestion values or hardcoded route changes.
    func previewDemoHour(_ hour: Int) async {
        guard demoEnabled, !navigating, !demoLoading, demoError == nil,
              [9, 11, 14, 17, 18, 19, 20].contains(hour) else { return }
        if hour == 11 || hour == 17 { selectDemoHour(hour); return }
        if let cached = extraDemoFactors[hour] {
            demoHour = hour; crowdFactors = cached; crowdReady = true
            routePreference = .fastest; replanIndoorSelection()
            routeVisible = route != nil
            return
        }
        demoLoading = true
        demoRequestVersion += 1
        let version = demoRequestVersion
        do {
            let estimated = try await ExpoAPI().loadIndoorCrowd(graph: indoor, overrideHour: hour, overrideDay: 0)
            guard version == demoRequestVersion, demoEnabled, mode == .indoor else { return }
            extraDemoFactors[hour] = estimated
            demoHour = hour; crowdFactors = estimated; crowdReady = true
            demoLoading = false
            routePreference = .fastest; replanIndoorSelection()
            routeVisible = route != nil
        } catch {
            guard version == demoRequestVersion else { return }
            demoLoading = false
            toast = "تعذر تحديث توقع الزحمة لهذا الوقت"
        }
    }

    private func resetCrowdDemo() {
        demoRequestVersion += 1  // Ignore any in-flight comparison response.
        demoEnabled = false
        demoLoading = false
        demoError = nil
        morningFactors = [:]
        eveningFactors = [:]
        extraDemoFactors = [:]
    }

    func closeCrowdDemo() {
        guard demoEnabled, !navigating else { return }
        resetCrowdDemo()
        crowdFactors = [:]
        crowdReady = false
        replanIndoorSelection()
        // Return to predictions for the device's real date/time.
        Task { await refreshCrowdPrediction() }
    }

    var metersRemaining: Double { route?.distanceRemaining(at: elapsed) ?? 0 }
    var secondsRemaining: Double { max(0,(route?.seconds ?? 0)-elapsed) }
    var journeyMeters: Double {
        (route?.metres ?? 0) + (mode == .outdoor ? (plannedIndoorRoute?.metres ?? 0) : 0)
    }
    var journeySeconds: Double {
        (route?.seconds ?? 0) + (mode == .outdoor ? (plannedIndoorRoute?.seconds ?? 0) : 0)
    }
    // Distances always originate from the user-selected entrance gate, not the camera
    // or a fixed/straight-line approximation. Each pavilion has one graph-derived cost.
    func gateDistance(to pavilionID: String) -> Double? { gateDistances[pavilionID] }
    func pavilionID(for event: ExpoNavEvent) -> String? {
        dataset.assignments.pavilionBooths.first(where: { $0.value.contains(event.booth_id) })?.key
    }
    var sortedPavilions: [ExpoLocation] {
        GateDiscovery.pavilions(data: dataset, distances: gateDistances)
    }
    var sortedEvents: [ExpoNavEvent] {
        GateDiscovery.events(data: dataset, distances: gateDistances)
    }
    var selectedGateName: String {
        dataset.gates.gates.first(where: { $0.id == selectedGateID })?.name_ar ?? "اختر بوابة"
    }
    var hasSelection: Bool {
        mode == .outdoor ? selectedLocationID != nil : selectedSpaceID != nil || selectedEventID != nil
    }
    func clearRoute() {
        navigating = false
        lastTick = nil
        elapsed = 0
        route = nil
        fastestRoute = nil
        shortestRoute = nil
        routeVisible = false
    }
    func selectLocation(_ id: String) {
        guard dataset.map.locations.contains(where: {$0.id == id}) else { return }
        clearRoute()
        selectedEventID = nil
        selectedSpaceID = nil
        selectedLocationID = id
        plannedIndoorRoute = nil
        // Exterior is browse-only. Graph distances remain available via gateDistances.
        route = nil
    }
    func selectEvent(_ eventID: String) {
        guard let event = dataset.events.first(where: {$0.id == eventID}) else { return }
        clearRoute()
        selectedEventID = eventID
        selectedSpaceID = mode == .indoor ? event.booth_id : nil
        if mode == .outdoor {
            guard let pavilionID = pavilionID(for: event) else {
                toast = "لا يوجد جناح مرتبط بهذه الفعالية"
                return
            }
            selectedLocationID = pavilionID
            // No exterior path display, simulated walking or location tracking.
            route = nil
            plannedIndoorRoute = nil
        } else {
            if let space = dataset.space(for: event.booth_id) {
                selectedSpaceID = space.id
                floor = position.floor
                routePreference = .fastest
                replanIndoorSelection()
                routeVisible = route != nil
            } else { toast = "هذه الفعالية ليست ضمن جناح السعودية" }
        }
        if mode == .indoor && route == nil { toast = "لا يوجد مسار صالح لهذه الفعالية" }
    }
    func selectSpace(_ id: String) {
        guard mode == .indoor, let space = dataset.indoor.spaces.first(where: {$0.id == id}) else { return }
        clearRoute()
        selectedSpaceID = space.id
        selectedEventID = nil
        routePreference = .fastest
        replanIndoorSelection()
        routeVisible = route != nil
        if route == nil { toast = "تعذر العثور على مسار" }
    }
    func showRoute() {
        guard mode == .indoor else { return }
        guard route != nil else { toast = "اختر وجهة متصلة بالممرات أولًا"; return }
        routeVisible = true
        cameraRevision += 1
    }
    func startNavigation() {
        guard mode == .indoor, route != nil else { return }
        if crowdLoading || demoLoading {
            toast = "جاري توقع الزحمة، انتظر قليلًا قبل بدء المشي"
            return
        }
        if !routeVisible { showRoute() }
        if let route, route.seconds < 0.001 {
            toast = "أنت بالفعل عند الوجهة"
            return
        }
        navigating = true
        lastTick = nil
    }
    func stopNavigation() { navigating = false; lastTick = nil }
    func cancelWalking() {
        stopNavigation()
        elapsed = 0
        routeVisible = false
        // Replan from the precise point reached so the next start never jumps backward.
        if let id = selectedSpaceID {
            replanIndoorSelection()
        } else { route = nil }
        toast = "تم إلغاء المشي، ويمكنك عرض الطريق مجددًا"
    }
    func tick(date: Date) {
        guard mode == .indoor, navigating, let route else { return }
        let delta = min(0.25, max(0, date.timeIntervalSince(lastTick ?? date)))
        lastTick = date
        elapsed = min(route.seconds, elapsed + delta * walkingMultiplier)
        position = route.position(at: elapsed)
        if mode == .indoor && floor != position.floor {
            floor = position.floor
            cameraRevision += 1
        }
        if elapsed >= route.seconds {
            stopNavigation()
            toast = "وصلت إلى الوجهة المحددة"
        }
    }
    func chooseGate(_ gateID: String) {
        guard mode == .outdoor, let gate = outdoor.nodes["location/\(gateID)"] else { return }
        clearRoute()
        selectedLocationID = nil
        selectedEventID = nil
        plannedIndoorRoute = nil
        position = gate.position
        selectedGateID = gateID
        gateDistances = GateDiscovery.distances(gateID: gateID, data: dataset, graph: outdoor)
        cameraRevision += 1
        toast = "تم تحديد \(dataset.gates.gates.first(where: {$0.id == gateID})?.name_ar ?? gateID) نقطةً للبداية"
    }
    func enterSaudi() {
        guard mode == .outdoor else { return }
        clearRoute()
        mode = .indoor
        floor = 1
        position = indoor.nodes["f1/entrance"]!.position
        selectedLocationID = "sa"
        selectedSpaceID = selectedEvent?.booth_id
        plannedIndoorRoute = nil
        // Never carry a prior prediction or demo session into a new visit.
        resetCrowdDemo()
        crowdRequestVersion += 1
        crowdReady = false
        crowdLoading = false
        crowdFactors = [:]
        if selectedSpaceID != nil {
            routePreference = .fastest
            replanIndoorSelection()
            routeVisible = route != nil
        }
        cameraRevision += 1
        toast = "أنت الآن عند المدخل الرئيسي لجناح السعودية"
        Task { await refreshCrowdPrediction() }
    }
    func exitSaudi() {
        guard mode == .indoor else { return }
        // Invalidate any in-flight prediction response before leaving the pavilion.
        resetCrowdDemo()
        crowdRequestVersion += 1
        crowdLoading = false
        crowdReady = false
        crowdFactors = [:]
        clearRoute()
        mode = .outdoor
        floor = 1
        position = outdoor.nodes["location/\(selectedGateID ?? "gate3")"]!.position
        selectedSpaceID = nil
        selectedEventID = nil
        selectedLocationID = "sa"
        cameraRevision += 1
        toast = "العودة إلى خريطة إكسبو الخارجية"
    }
    func placeAt(_ point: ExpoNavPoint) {
        guard mode == .indoor, placementMode,
              let valid = indoor.nearestWalkablePosition(to: point, floor: floor) else { return }
        let preservedDestination = selectedSpaceID
        let preservedEvent = selectedEventID
        position = valid
        clearRoute()
        selectedLocationID = nil
        selectedSpaceID = preservedDestination
        selectedEventID = preservedEvent
        plannedIndoorRoute = nil
        placementMode = false
        routePreference = .fastest
        replanIndoorSelection()
        routeVisible = route != nil
        toast = "تم تحديد موقعك على الممر وإعادة حساب المسار"
    }
    func currentFloorEvents() -> [ExpoNavEvent] {
        dataset.events(for: "sa").filter { dataset.floor(for: $0.booth_id) == floor }
    }
}
