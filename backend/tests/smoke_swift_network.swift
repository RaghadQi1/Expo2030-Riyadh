import Foundation

@main
struct APISmoke {
    static func main() async throws {
        let data = try await ExpoAPI().loadDataset()
        let pavilions = data.map.locations.filter { $0.kind == "pavilion" }
        guard pavilions.count == 12, data.events.count == 96,
              data.booths.count == 32 else { fatalError("Dataset was incomplete") }
        print("End-to-end Swift URLSession -> REST -> JSON decode: SUCCESS")
    }
}
