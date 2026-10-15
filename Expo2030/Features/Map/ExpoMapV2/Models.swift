import Foundation

public struct ExpoNavPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to other: ExpoNavPoint) -> Double { hypot(x - other.x, y - other.y) }
    public func interpolated(to other: ExpoNavPoint, fraction: Double) -> ExpoNavPoint {
        .init(x + (other.x - x) * fraction, y + (other.y - y) * fraction)
    }
}
public enum MapZone: String, Codable, Sendable { case outdoor, indoor }
public struct MapPosition: Equatable, Sendable {
    public var zone: MapZone
    public var floor: Int
    public var point: ExpoNavPoint
    public init(_ zone: MapZone, _ floor: Int, _ point: ExpoNavPoint) {
        self.zone = zone; self.floor = floor; self.point = point
    }
}
public struct ExpoLocation: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let node: String
    public let district: String?
    public let size: String?
    public let desc: String?
}
public struct ExpoDistrict: Codable, Sendable {
    public let name: String
    public let sub: String
    public let color: String
    public let start: Int
}
public struct ExpoMapData: Codable, Sendable {
    public let districts: [ExpoDistrict]
    public let locations: [ExpoLocation]
    public let metresPerMapUnit: Double
    public let assumedWalkingSpeedMetresPerMinute: Double
}
public struct ExpoBooth: Codable, Identifiable, Sendable {
    public let booth_id: String
    public let name_en: String
    public let name_ar: String
    public let category: String
    public let description_ar: String
    public let floor: Int
    public var id: String { booth_id }
}
public struct ExpoNavEvent: Codable, Identifiable, Sendable {
    public let event_id: String
    public let booth_id: String
    public let title_ar: String
    public let description_ar: String
    public let category: String
    public let start_time: String
    public let end_time: String
    public var id: String { event_id }
}
public struct BoothAssignments: Codable, Sendable { public let pavilionBooths: [String: [String]] }
public struct IndoorSpace: Codable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let floor: Int
    public let x: Double
    public let y: Double
    public let via: [Double]
    public let door: [Double]
    public var center: ExpoNavPoint { ExpoNavPoint(x,y) }
    public var entrance: ExpoNavPoint { ExpoNavPoint(door[0],door[1]) }
    public var waypoint: ExpoNavPoint { ExpoNavPoint(via[0],via[1]) }
}
public struct SaudiIndoorData: Codable, Sendable {
    public let floor_count: Int
    public let entrance: [Double]
    public let indoor_meters_per_svg_unit: Double
    public let booth_ids: [String]
    public let spaces: [IndoorSpace]
}
public struct GateRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let name_ar: String
    public let map_node: String
}
public struct GatesData: Codable, Sendable {
    public let gates: [GateRecord]
    public let initial_visitor_node: String
}
public enum ExpoDataError: Error, LocalizedError {
    case missingFile(String), inconsistent(String)
    public var errorDescription: String? {
        switch self {
        case .missingFile(let file): return "ملف البيانات غير موجود: \(file)"
        case .inconsistent(let issue): return "بيانات غير متسقة: \(issue)"
        }
    }
}
public struct ExpoDataset: Sendable {
    public let map: ExpoMapData
    public let booths: [ExpoBooth]
    public let events: [ExpoNavEvent]
    public let assignments: BoothAssignments
    public let indoor: SaudiIndoorData
    public let gates: GatesData

    public static func load(from bundle: Bundle? = nil) throws -> ExpoDataset {
        let bundle = bundle ?? Bundle.main
        func decode<T: Decodable>(_ file: String) throws -> T {
            guard let url = bundle.url(forResource: file, withExtension: "json")
                    ?? bundle.url(forResource: file, withExtension: "json", subdirectory: "ExpoMapData") else {
                throw ExpoDataError.missingFile(file + ".json")
            }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        return ExpoDataset(map: try decode("expo-map-data"),
                           booths: try decode("booths"), events: try decode("events"),
                           assignments: try decode("assignments"),
                           indoor: try decode("saudi-pavilion-indoor"), gates: try decode("gates"))
    }
    public func booths(for pavilionID: String) -> [ExpoBooth] {
        let ids = Set(assignments.pavilionBooths[pavilionID] ?? [])
        return booths.filter { ids.contains($0.booth_id) }
    }
    public func events(for pavilionID: String) -> [ExpoNavEvent] {
        let ids = Set(assignments.pavilionBooths[pavilionID] ?? [])
        return events.filter { ids.contains($0.booth_id) }
    }
    public func space(for boothID: String) -> IndoorSpace? {
        indoor.spaces.first { $0.id == boothID }
    }
    public func floor(for boothID: String) -> Int {
        space(for: boothID)?.floor ?? booths.first(where: { $0.id == boothID })?.floor ?? 1
    }
    public func validate() -> [String] {
        var issues: [String] = []
        let locationIDs = Set(map.locations.map(\.id))
        let boothIDs = Set(booths.map(\.id))
        if boothIDs.count != booths.count { issues.append("معرفات بوثات مكررة") }
        if Set(events.map(\.id)).count != events.count { issues.append("معرفات فعاليات مكررة") }
        if Set(map.locations.map(\.id)).count != map.locations.count { issues.append("معرفات أجنحة مكررة") }
        for e in events where !boothIDs.contains(e.booth_id) { issues.append("فعالية \(e.id) بدون بوث") }
        for (pavilion, ids) in assignments.pavilionBooths {
            if !locationIDs.contains(pavilion) { issues.append("جناح غير موجود: \(pavilion)") }
            for id in ids where !boothIDs.contains(id) { issues.append("ربط بوث غير موجود: \(id)") }
        }
        for id in indoor.booth_ids where space(for: id) == nil { issues.append("موقع داخلي غير موجود: \(id)") }
        for gate in gates.gates where !locationIDs.contains(gate.id) { issues.append("بوابة غير موجودة: \(gate.id)") }
        return issues
    }
}
