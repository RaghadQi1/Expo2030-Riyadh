import Foundation

private struct Payload: Decodable {
    let map: ExpoMapData
    let booths: [ExpoBooth]
    let events: [ExpoEvent]
    let assignments: BoothAssignments
    let indoor: SaudiIndoorData
    let gates: GatesData
}

@main
struct Smoke {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else { fatalError("Supply dataset JSON path") }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let loaded = try JSONDecoder().decode(Payload.self, from: bytes)
        let data = ExpoDataset(map: loaded.map, booths: loaded.booths, events: loaded.events,
                               assignments: loaded.assignments, indoor: loaded.indoor, gates: loaded.gates)
        guard data.validate().isEmpty else { fatalError("Bad dataset: \(data.validate())") }
        let outdoor = ExpoGraphs.outdoor(data)
        let indoor = ExpoGraphs.indoor(data)
        let meters = outdoor.pathBetweenNodes("location/gate3", "location/sa")?.metres ?? -1
        let journey = indoor.pathBetweenNodes("f1/entrance", "space/B015")
        guard meters > 0, let journey, journey.metres > 0,
              journey.levels.contains(2) else { fatalError("Bad linked route geometry") }
        let count = data.map.locations.filter { $0.kind == "pavilion" }.count
        print("Swift decoded API JSON: \(count) pavilions, \(data.events.count) events; Gate3–Saudi route \(Int(meters))m")
    }
}
