import Foundation

public struct GraphNode: Sendable {
    public let id: String
    public let position: MapPosition
    public init(_ id: String, _ position: MapPosition) { self.id = id; self.position = position }
}
public struct GraphEdge: Sendable {
    public let from: String
    public let to: String
    public let metres: Double
    public let transitionSeconds: Double
    public var isVertical: Bool { transitionSeconds > 0 }
    /// Stable, direction-independent identifier shared with the crowd API.
    public var key: String { Self.key(from, to) }
    public static func key(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}
public struct RouteSegment: Sendable {
    public let from: MapPosition
    public let to: MapPosition
    public let metres: Double
    public let seconds: Double
    public let isVertical: Bool
}
public struct RoutePlan: Sendable {
    public let segments: [RouteSegment]
    public let start: MapPosition
    public let end: MapPosition
    public var metres: Double { segments.reduce(0) { $0 + $1.metres } }
    public var seconds: Double { segments.reduce(0) { $0 + $1.seconds } }
    public var minutes: Double { seconds / 60 }
    public var levels: [Int] { Array(Set(segments.map { $0.to.floor })).sorted() }
    /// Remove redundant points on the same straight physical corridor.
    /// Two routes that only differ by overlapping graph-node subdivisions have
    /// the SAME geometry; they must not be reported as AI rerouting.
    public var geometryCorners: [MapPosition] {
        let points = [start] + segments.map(\.to)
        var corners: [MapPosition] = []
        for point in points {
            if let last = corners.last, last.floor == point.floor,
               last.point.distance(to: point.point) < 0.00001 { continue }
            while corners.count >= 2 {
                let a = corners[corners.count - 2], b = corners[corners.count - 1]
                guard a.floor == b.floor, b.floor == point.floor else { break }
                let abx = b.point.x-a.point.x, aby = b.point.y-a.point.y
                let bcx = point.point.x-b.point.x, bcy = point.point.y-b.point.y
                let cross = abs(abx*bcy - aby*bcx)
                let dot = abx*bcx + aby*bcy
                if cross <= 0.00001 && dot >= -0.00001 { corners.removeLast() }
                else { break }
            }
            corners.append(point)
        }
        return corners
    }
    public func takesDifferentGeometry(than other: RoutePlan) -> Bool {
        let left = geometryCorners, right = other.geometryCorners
        guard left.count == right.count else { return true }
        return zip(left,right).contains { a,b in
            a.floor != b.floor || a.point.distance(to: b.point) > 0.001
        }
    }
    public func position(at elapsedSeconds: Double) -> MapPosition {
        var remaining = max(0, elapsedSeconds)
        for segment in segments {
            if remaining <= segment.seconds {
                if segment.isVertical { return remaining < segment.seconds ? segment.from : segment.to }
                let ratio = segment.seconds <= 0 ? 1 : min(1, remaining / segment.seconds)
                return MapPosition(segment.from.zone, segment.from.floor,
                    segment.from.point.interpolated(to: segment.to.point, fraction: ratio))
            }
            remaining -= segment.seconds
        }
        return end
    }
    public func distanceRemaining(at elapsedSeconds: Double) -> Double {
        var remaining = max(0, elapsedSeconds)
        for (index, segment) in segments.enumerated() {
            if remaining <= segment.seconds {
                let ratio = segment.seconds <= 0 ? 1 : min(1, remaining / segment.seconds)
                let segmentRemaining = segment.isVertical ? 0 : segment.metres * (1 - ratio)
                return segmentRemaining + segments.dropFirst(index + 1).reduce(0) { $0 + $1.metres }
            }
            remaining -= segment.seconds
        }
        return 0
    }
}

/// Congestion *along a computed route*, not the floor-wide forecast.
/// Every RouteSegment already contains its congestion-weighted travel seconds.
/// This means snapped positions and partial corridors are handled correctly,
/// without looking up another edge or inventing a separate crowd prediction.
public struct RouteCrowdSummary: Sendable {
    public let averageFactor: Double
    public let peakFactor: Double
    public let congestedMetres: Double
    public let walkingMetres: Double
    public let delaySeconds: Double

    public var level: Int { Self.level(for: averageFactor) }
    public var peakLevel: Int { Self.level(for: peakFactor) }
    public var congestedPercent: Int {
        guard walkingMetres > 0 else { return 0 }
        return Int((100 * congestedMetres / walkingMetres).rounded())
    }
    public static func level(for factor: Double) -> Int {
        factor >= 1.55 ? 2 : (factor >= 1.12 ? 1 : 0)
    }
    public init(route: RoutePlan, walkingMetresPerMinute speed: Double) {
        var baseline = 0.0
        var predicted = 0.0
        var peak = 1.0
        var congested = 0.0
        var walking = 0.0
        for segment in route.segments where !segment.isVertical && segment.metres > 0 {
            let normal = segment.metres / speed * 60.0
            guard normal > 0 else { continue }
            let factor = max(1.0, segment.seconds / normal)
            baseline += normal
            predicted += segment.seconds
            peak = max(peak, factor)
            walking += segment.metres
            if Self.level(for: factor) >= 1 { congested += segment.metres }
        }
        walkingMetres = walking
        congestedMetres = congested
        peakFactor = peak
        averageFactor = baseline > 0 ? max(1.0, predicted / baseline) : 1.0
        delaySeconds = max(0, predicted - baseline)
    }
}

public struct NavigationGraph: Sendable {
    public private(set) var nodes: [String: GraphNode] = [:]
    public private(set) var edges: [GraphEdge] = []
    public let zone: MapZone
    public let walkingMetresPerMinute: Double
    public let scale: Double

    public init(zone: MapZone, scale: Double, speed: Double = 78) {
        self.zone = zone; self.scale = scale; self.walkingMetresPerMinute = speed
    }
    public mutating func addNode(_ id: String, floor: Int, _ point: ExpoNavPoint) {
        nodes[id] = GraphNode(id, MapPosition(zone, floor, point))
    }
    public mutating func connect(_ a: String, _ b: String, verticalSeconds: Double = 0) {
        guard let aa = nodes[a], let bb = nodes[b] else { return }
        guard !edges.contains(where: { ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a) }) else { return }
        let validFloors = aa.position.floor == bb.position.floor
        guard validFloors || verticalSeconds > 0 else { return }
        let length = verticalSeconds > 0 ? 0 : aa.position.point.distance(to: bb.position.point) * scale
        edges.append(GraphEdge(from: a, to: b, metres: length, transitionSeconds: verticalSeconds))
    }
    /// Cost = (edge length / walking speed) × predicted congestion factor.
    /// Vertical connections always use their explicitly modeled transition time.
    /// No predictions (or an offline server) means a factor of 1 on every edge.
    public func shortestPath(from origin: MapPosition, to targetID: String,
                             timeFactors: [String: Double] = [:]) -> RoutePlan? {
        guard nodes[targetID] != nil, origin.zone == zone else { return nil }
        let sameFloorEdges = edges.filter { edge in
            guard let a = nodes[edge.from], let b = nodes[edge.to] else { return false }
            return !edge.isVertical && a.position.floor == origin.floor && b.position.floor == origin.floor
        }
        // Snap only on a walkable edge, then insert a temporary origin into that edge.
        var best: (edge: GraphEdge, point: ExpoNavPoint, t: Double, separation: Double)?
        for edge in sameFloorEdges {
            guard let a = nodes[edge.from]?.position.point, let b = nodes[edge.to]?.position.point else { continue }
            let dx = b.x - a.x, dy = b.y - a.y
            let len2 = dx*dx + dy*dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((origin.point.x - a.x)*dx + (origin.point.y - a.y)*dy) / len2))
            let projected = a.interpolated(to: b, fraction: t)
            let d = origin.point.distance(to: projected)
            if best == nil || d < best!.separation { best = (edge, projected, t, d) }
        }
        if best == nil, let match = nodes.first(where: { $0.value.position == origin }) {
            return path(from: match.key, to: targetID, temporary: nil, timeFactors: timeFactors)
        }
        guard let best else { return nil }
        // The origin is always put on the actual walkway, not directly linked through obstacles.
        return path(from: "__origin__", to: targetID,
                    temporary: (best.edge.from, best.edge.to,
                                MapPosition(zone, origin.floor, best.point)),
                    timeFactors: timeFactors)
    }
    public func pathBetweenNodes(_ startID: String, _ endID: String,
                                 timeFactors: [String: Double] = [:]) -> RoutePlan? {
        path(from: startID, to: endID, temporary: nil, timeFactors: timeFactors)
    }
    private func path(from startID: String, to targetID: String,
                      temporary: (String, String, MapPosition)?,
                      timeFactors: [String: Double]) -> RoutePlan? {
        var locations = nodes
        var allEdges = edges
        var factors = timeFactors
        if let temp = temporary, let a = nodes[temp.0], let b = nodes[temp.1] {
            locations[startID] = GraphNode(startID, temp.2)
            // Snap-derived edges inherit the congestion of their source corridor.
            let originalFactor = timeFactors[GraphEdge.key(a.id, b.id)] ?? 1.0
            factors[GraphEdge.key(startID, a.id)] = originalFactor
            factors[GraphEdge.key(startID, b.id)] = originalFactor
            allEdges.append(GraphEdge(from: startID, to: a.id,
                metres: temp.2.point.distance(to: a.position.point) * scale, transitionSeconds: 0))
            allEdges.append(GraphEdge(from: startID, to: b.id,
                metres: temp.2.point.distance(to: b.position.point) * scale, transitionSeconds: 0))
        }
        guard let start = locations[startID]?.position, let end = locations[targetID]?.position else { return nil }
        if startID == targetID { return RoutePlan(segments: [], start: start, end: end) }
        var adjacency: [String: [(neighbor: String, edge: GraphEdge)]] = [:]
        for edge in allEdges {
            adjacency[edge.from, default: []].append((edge.to, edge))
            adjacency[edge.to, default: []].append((edge.from, edge))
        }
        func cost(_ edge: GraphEdge) -> Double {
            if edge.isVertical { return edge.transitionSeconds }
            let proposed = factors[edge.key] ?? 1.0
            let multiplier = proposed.isFinite && proposed >= 1.0 && proposed <= 10.0 ? proposed : 1.0
            return edge.metres / walkingMetresPerMinute * 60 * multiplier
        }
        var distance: [String: Double] = [startID: 0]
        var predecessor: [String: (String, GraphEdge)] = [:]
        var visited = Set<String>()
        // Dijkstra with deterministic tie-breaking for reproducible simulated routes.
        while let candidate = distance.filter({ !visited.contains($0.key) })
            .min(by: { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }) {
            let u = candidate.key
            if u == targetID { break }
            visited.insert(u)
            for item in adjacency[u] ?? [] {
                let alt = candidate.value + cost(item.edge)
                if alt < distance[item.neighbor, default: .infinity] - 0.000001 {
                    distance[item.neighbor] = alt
                    predecessor[item.neighbor] = (u, item.edge)
                }
            }
        }
        guard distance[targetID] != nil else { return nil }
        var reversed: [RouteSegment] = []
        var key = targetID
        while key != startID {
            guard let (prior, edge) = predecessor[key], let from = locations[prior]?.position,
                  let to = locations[key]?.position else { return nil }
            reversed.append(RouteSegment(from: from, to: to, metres: edge.metres,
                seconds: cost(edge), isVertical: edge.isVertical))
            key = prior
        }
        return RoutePlan(segments: reversed.reversed(), start: start, end: end)
    }
    /// Evaluate a geometry chosen by shortest distance under the SAME predicted
    /// crowd factors used by Dijkstra. Never compare baseline un-congested time
    /// against AI-congested time: both options must use identical conditions.
    /// Includes snapped origins that occupy part of an existing corridor edge.
    public func predictedTravelTime(for baseline: RoutePlan,
                                    timeFactors: [String: Double]) -> RoutePlan {
        let scored = baseline.segments.map { segment -> RouteSegment in
            guard !segment.isVertical else { return segment }
            let factor: Double = edges.first(where: { edge in
                guard !edge.isVertical,
                      let a = nodes[edge.from]?.position,
                      let b = nodes[edge.to]?.position,
                      a.floor == segment.from.floor,
                      b.floor == segment.to.floor else { return false }
                func liesOnEdge(_ p: ExpoNavPoint) -> Bool {
                    let length = a.point.distance(to: b.point)
                    return abs(a.point.distance(to: p) + p.distance(to: b.point) - length) < 0.0001
                }
                return liesOnEdge(segment.from.point) && liesOnEdge(segment.to.point)
            }).map { timeFactors[$0.key] ?? 1.0 } ?? 1.0
            let multiplier = factor.isFinite && (1...10).contains(factor) ? factor : 1.0
            return RouteSegment(from: segment.from, to: segment.to,
                                metres: segment.metres,
                                seconds: segment.metres / walkingMetresPerMinute * 60 * multiplier,
                                isVertical: false)
        }
        return RoutePlan(segments: scored, start: baseline.start, end: baseline.end)
    }

    public func nearestWalkablePosition(to requested: ExpoNavPoint, floor: Int) -> MapPosition? {
        let sample = MapPosition(zone, floor, requested)
        guard let first = edges.first(where: {
            nodes[$0.from]?.position.floor == floor && nodes[$0.to]?.position.floor == floor && !$0.isVertical
        }) else { return nil }
        var closest = nodes[first.from]!.position.point
        var minimum = Double.infinity
        for edge in edges where !edge.isVertical {
            guard let a = nodes[edge.from]?.position, let b = nodes[edge.to]?.position,
                  a.floor == floor && b.floor == floor else { continue }
            let dx = b.point.x-a.point.x, dy = b.point.y-a.point.y, len2 = dx*dx+dy*dy
            let t = len2 == 0 ? 0 : max(0,min(1,((sample.point.x-a.point.x)*dx+(sample.point.y-a.point.y)*dy)/len2))
            let projection = a.point.interpolated(to: b.point, fraction: t)
            let d = sample.point.distance(to: projection)
            if d < minimum { minimum = d; closest = projection }
        }
        return MapPosition(zone, floor, closest)
    }
}

public enum ExpoGraphs {
    public static let ringRadii: [Double] = [0, 118, 232, 330]
    public static let center = ExpoNavPoint(500, 350)
    public static let sectorCount = 10
    public static let samplesPerSector = 12
    public static func nodeID(_ ring: Int, _ slot: Int) -> String {
        if ring == 0 { return "hub" }
        let total = sectorCount * samplesPerSector
        return "ring/\(ring)/\((slot * samplesPerSector % total + total) % total)"
    }
    public static func polarPoint(_ ring: Int, _ subdivision: Int) -> ExpoNavPoint {
        if ring == 0 { return center }
        let total = Double(sectorCount * samplesPerSector)
        let angle = -Double.pi/2 + Double(subdivision) * 2 * .pi / total
        return ExpoNavPoint(center.x + cos(angle) * ringRadii[ring], center.y + sin(angle) * ringRadii[ring])
    }
    public static func mapNode(_ raw: String) -> ExpoNavPoint? {
        let parts = raw.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 2, (0...3).contains(parts[0]), (0..<10).contains(parts[1]) else { return nil }
        return polarPoint(parts[0], parts[1] * samplesPerSector)
    }
    public static func outdoor(_ dataset: ExpoDataset) -> NavigationGraph {
        var g = NavigationGraph(zone: .outdoor, scale: dataset.map.metresPerMapUnit,
                                speed: dataset.map.assumedWalkingSpeedMetresPerMinute)
        g.addNode("hub", floor: 0, center)
        for ring in 1...3 {
            for subdivision in 0..<(sectorCount * samplesPerSector) {
                g.addNode("ring/\(ring)/\(subdivision)", floor: 0, polarPoint(ring, subdivision))
            }
            for subdivision in 0..<(sectorCount * samplesPerSector) {
                g.connect("ring/\(ring)/\(subdivision)",
                          "ring/\(ring)/\((subdivision+1) % (sectorCount*samplesPerSector))")
            }
        }
        for s in 0..<sectorCount {
            g.connect("hub", nodeID(1,s))
            g.connect(nodeID(1,s), nodeID(2,s))
            g.connect(nodeID(2,s), nodeID(3,s))
        }
        for location in dataset.map.locations where location.id != "hub" {
            let parts = location.node.split(separator: ",").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let ring = parts[0], slot = parts[1]
            let anchorID = nodeID(ring, slot)
            if location.id.starts(with: "gate") {
                // Gate and walkway node share the exact simulated coordinates.
                g.addNode("location/\(location.id)", floor: 0, polarPoint(ring,slot*samplesPerSector))
            } else {
                let anchor = polarPoint(ring, slot*samplesPerSector)
                let angle = -Double.pi/2 + Double(slot)*2*Double.pi/Double(sectorCount)
                let offset = location.kind == "pavilion" ? 31.0 : 19.0
                let extra: ExpoNavPoint = ExpoNavPoint(anchor.x + cos(angle + 0.18)*offset,
                                                anchor.y + sin(angle + 0.18)*offset)
                g.addNode("location/\(location.id)", floor: 0, extra)
            }
            g.connect(anchorID, "location/\(location.id)")
        }
        return g
    }
    public static func indoor(_ dataset: ExpoDataset) -> NavigationGraph {
        var g = NavigationGraph(zone: .indoor, scale: dataset.indoor.indoor_meters_per_svg_unit,
                                speed: dataset.map.assumedWalkingSpeedMetresPerMinute)
        func add(_ floor: Int, _ name: String, _ x: Double, _ y: Double) {
            g.addNode("f\(floor)/\(name)", floor: floor, ExpoNavPoint(x,y))
        }
        func line(_ floor: Int, _ names: [String]) {
            for i in 1..<names.count { g.connect("f\(floor)/\(names[i-1])", "f\(floor)/\(names[i])") }
        }
        // Corridors are explicitly modeled and rendered from these same graph edges.
        for f in 1...2 {
            add(f,"lift",380,393); add(f,"walk406",380,406)
            add(f,"center428",380,428); add(f,"center332",380,332)
            line(f,["lift","walk406","center428"])
            add(f,"west428",252,428); add(f,"east428",506,428)
            add(f,"bypass428",320,428); add(f,"bypass332",320,332)
            // Each physical horizontal corridor is represented once, in coordinate order.
            // Do not add long overlapping edges over the same corridor: that caused
            // "route changed" to mean different node IDs but the SAME drawn line.
            // The floor-1 service nodes are inserted below into this same chain.
            if f == 2 { line(f,["west428","bypass428","center428","east428"]) }
            g.connect("f\(f)/bypass428","f\(f)/bypass332")
            g.connect("f\(f)/bypass332","f\(f)/center332")
        }
        add(1,"entrance",380,486); add(1,"center250",380,250); add(1,"center214",380,214)
        line(1,["entrance","center428","walk406","lift"])
        line(1,["center332","center250","center214"])
        add(1,"left250",280,250); add(1,"right250",482,250)
        line(1,["left250","center250","right250"])
        // Alternate real walkways along the two outer wings. They are rendered
        // from the same edges and allow the fastest route to differ from the
        // shortest route when the main passage is congested.
        add(1,"west250",252,250); add(1,"east250",506,250)
        line(1,["west428","west250","left250"])
        line(1,["east428","east250","right250"])
        add(1,"cafe428",194,428); add(1,"wc428",334,428); add(1,"exit428",426,428)
        line(1,["cafe428","west428","bypass428","wc428","center428","exit428","east428"])
        add(2,"left332",282,332); add(2,"right332",478,332)
        line(2,["left332","center332","right332"])
        add(2,"prayer428",566,428)
        g.connect("f2/east428","f2/prayer428")
        // Every door is a route destination; room centers are never used as shortcuts.
        let access: [String: String] = [
            "B013":"f1/left250","B014":"f1/right250",
            "B015":"f2/left332","B016":"f2/right332",
            "stage":"f1/center214","cafe":"f1/cafe428","prayer":"f2/prayer428",
            "wc":"f1/wc428","exit":"f1/exit428","lift1":"f1/lift","lift2":"f2/lift"
        ]
        for space in dataset.indoor.spaces {
            g.addNode("space/\(space.id)", floor: space.floor, space.entrance)
            if let parent = access[space.id] { g.connect(parent,"space/\(space.id)") }
        }
        g.connect("f1/lift", "f2/lift", verticalSeconds: 18)
        return g
    }
}

/// Browse-only discovery. "Nearest" means the shortest valid outdoor graph path
/// from the chosen gate; it is never based on latitude/GPS or Euclidean distance.
public enum GateDiscovery {
    public static func distances(gateID: String, data: ExpoDataset,
                                 graph: NavigationGraph) -> [String: Double] {
        guard let origin = graph.nodes["location/\(gateID)"]?.position else { return [:] }
        var result: [String: Double] = [:]
        for pavilion in data.map.locations where pavilion.kind == "pavilion" {
            if let route = graph.shortestPath(from: origin, to: "location/\(pavilion.id)") {
                result[pavilion.id] = route.metres
            }
        }
        return result
    }
    public static func pavilions(data: ExpoDataset,
                                 distances: [String: Double]) -> [ExpoLocation] {
        data.map.locations.filter { $0.kind == "pavilion" }.sorted { a, b in
            let left = distances[a.id] ?? .infinity
            let right = distances[b.id] ?? .infinity
            return left == right ? a.name < b.name : left < right
        }
    }
    public static func events(data: ExpoDataset,
                              distances: [String: Double]) -> [ExpoNavEvent] {
        var byBooth: [String: String] = [:]
        for (pavilionID, booths) in data.assignments.pavilionBooths {
            for booth in booths { byBooth[booth] = pavilionID }
        }
        return data.events.sorted { a, b in
            let da = distances[byBooth[a.booth_id] ?? ""] ?? .infinity
            let db = distances[byBooth[b.booth_id] ?? ""] ?? .infinity
            if da != db { return da < db }
            if a.start_time != b.start_time { return a.start_time < b.start_time }
            return a.id < b.id
        }
    }
}


/// A UI-facing interpretation of the same edge-delay factors used by Dijkstra.
/// Thresholds match backend/app/crowd.py's _level() exactly.
/// This is a *simulated delay indicator*, NOT live foot-traffic measurement.
public struct CrowdForecastSummary: Sendable {
    public let low: Int
    public let medium: Int
    public let high: Int
    public var total: Int { low + medium + high }
    public var congested: Int { medium + high }
    public var status: String {
        if high > 0 { return "عالية في بعض الممرات" }
        if medium > 0 { return "متوسطة في بعض الممرات" }
        return "خفيفة في الممرات"
    }
    public var peakLevel: Int { high > 0 ? 2 : (medium > 0 ? 1 : 0) }

    public static func calculate(graph: NavigationGraph, floor: Int,
                                 factors: [String: Double]) -> CrowdForecastSummary? {
        var low = 0, medium = 0, high = 0
        for edge in graph.edges where !edge.isVertical && edge.metres > 0.001 {
            guard let from = graph.nodes[edge.from]?.position,
                  let to = graph.nodes[edge.to]?.position,
                  from.floor == floor, to.floor == floor,
                  let factor = factors[edge.key], factor.isFinite, factor >= 1 else { continue }
            if factor >= 1.55 { high += 1 }
            else if factor >= 1.12 { medium += 1 }
            else { low += 1 }
        }
        return low + medium + high > 0 ? CrowdForecastSummary(low: low, medium: medium, high: high) : nil
    }
}
